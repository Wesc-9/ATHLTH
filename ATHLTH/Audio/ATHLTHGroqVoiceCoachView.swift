import AVFoundation
import Foundation
import Supabase
import SwiftUI

/// Groq pilot: user-initiated, short push-to-talk turns rather than a
/// permanently open microphone. Apple system speech handles Norwegian TTS.
@MainActor
final class ATHLTHGroqVoiceTurn: ObservableObject {
    enum Phase: Equatable {
        case idle, recording, processing, speaking
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var question: String?
    @Published private(set) var answer: String?

    private var recorder: AVAudioRecorder?
    private let synthesizer = AVSpeechSynthesizer()
    private var recordingURL: URL?
    private var recordingExpiryTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var turnGeneration = UUID()
    private var previousCategory: AVAudioSession.Category?
    private var previousMode: AVAudioSession.Mode?
    private var previousOptions: AVAudioSession.CategoryOptions?

    var isBusy: Bool {
        switch phase {
        case .recording, .processing, .speaking: true
        case .idle, .error: false
        }
    }

    func startRecording() async -> Bool {
        guard !isBusy else { return false }
        let generation = UUID()
        turnGeneration = generation
        question = nil
        answer = nil

        let allowed = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard turnGeneration == generation else { return false }
        guard allowed else {
            phase = .error(ATHLTHLocalization.choose(
                english: "Allow the microphone in iPhone settings.",
                norwegian: "Gi mikrofontillatelse i iPhone-innstillingene."
            ))
            return false
        }

        do {
            synthesizer.stopSpeaking(at: .immediate)
            let session = AVAudioSession.sharedInstance()
            capturePreviousAudioSessionIfNeeded(session)
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("athlth-groq-\(UUID().uuidString).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let current = try AVAudioRecorder(url: target, settings: settings)
            guard current.prepareToRecord(), current.record() else {
                throw ATHLTHGroqTurnFailure.microphone
            }
            recordingURL = target
            recorder = current
            phase = .recording
            recordingExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self,
                      self.turnGeneration == generation else { return }
                self.recorder?.stop()
                self.recorder = nil
                self.recordingExpiryTask = nil
                self.phase = .idle
                // User must explicitly tap Send. A timed-out clip never
                // silently leaves the device.
                self.removeTemporaryRecording()
                self.phase = .error(ATHLTHLocalization.choose(
                    english: "Recording limit is 10 seconds. Try again.",
                    norwegian: "Du kan snakke i opptil 10 sekunder. Prøv igjen."
                ))
            }
            return true
        } catch {
            clearRecording()
            restoreAudioSession()
            phase = .error(ATHLTHLocalization.choose(
                english: "Microphone recording could not start.",
                norwegian: "Kunne ikke starte mikrofonopptak."
            ))
            return false
        }
    }

    func sendRecording(
        language: WatchAudioCoachLanguage,
        motivating: Bool,
        selectedVoice: String?,
        voiceRate: Float,
        voiceVolume: Float
    ) {
        guard phase == .recording, let recorder, let recordingURL else { return }
        recorder.stop()
        self.recorder = nil
        recordingExpiryTask?.cancel()
        recordingExpiryTask = nil
        guard recorder.currentTime >= 0.25,
              let raw = try? Data(contentsOf: recordingURL),
              raw.count >= 3200,
              raw.count <= 390_000 else {
            removeTemporaryRecording()
            restoreAudioSession()
            phase = .error(ATHLTHLocalization.choose(
                english: "No clear voice recording. Try speaking again.",
                norwegian: "Fant ikke et tydelig lydopptak. Prøv igjen."
            ))
            return
        }
        removeTemporaryRecording()
        phase = .processing
        let generation = turnGeneration
        turnTask = Task { [weak self] in
            guard let self else { return }
            do {
                let request = GroqRequest(
                    providerConsent: true,
                    microphoneConsent: true,
                    language: self.resolvedLanguage(language),
                    tone: motivating ? "motivating" : "balanced",
                    audioBase64: raw.base64EncodedString()
                )
                let output: GroqReply = try await SupabaseEnvironment.client.functions.invoke(
                    "audio-coach-groq-turn",
                    options: FunctionInvokeOptions(body: request)
                )
                guard self.turnGeneration == generation,
                      !Task.isCancelled else { return }
                self.question = output.transcript
                self.answer = output.reply
                self.phase = .speaking
                self.restoreAudioSession()
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio,
                                         options: [.mixWithOthers])
                try? session.setActive(true)
                let utterance = AVSpeechUtterance(string: output.reply)
                utterance.voice = ATHLTHCoachPreferredSystemVoice.resolve(
                    selectedIdentifier: selectedVoice,
                    language: language
                )
                utterance.rate = voiceRate
                utterance.volume = voiceVolume
                self.synthesizer.speak(utterance)
            } catch {
                guard self.turnGeneration == generation else { return }
                self.restoreAudioSession()
                self.phase = .error(ATHLTHLocalization.choose(
                    english: "Groq is unavailable or not activated on the server. Your workout continues.",
                    norwegian: "Groq er utilgjengelig eller ikke aktivert på serveren. Treningen fortsetter."
                ))
            }
        }
    }

    /// Stops local capture/playback immediately and cancels pending responses.
    func stop() {
        turnGeneration = UUID()
        recordingExpiryTask?.cancel()
        recordingExpiryTask = nil
        turnTask?.cancel()
        turnTask = nil
        clearRecording()
        synthesizer.stopSpeaking(at: .immediate)
        restoreAudioSession()
        phase = .idle
    }

    private func resolvedLanguage(_ choice: WatchAudioCoachLanguage) -> String {
        switch choice {
        case .norwegian: return "no"
        case .english: return "en"
        case .system:
            let language = Locale.autoupdatingCurrent.language.languageCode?
                .identifier.lowercased() ?? "no"
            return ["nb", "nn", "no"].contains(language) ? "no" : "en"
        }
    }

    private func capturePreviousAudioSessionIfNeeded(_ session: AVAudioSession) {
        guard previousCategory == nil else { return }
        previousCategory = session.category
        previousMode = session.mode
        previousOptions = session.categoryOptions
    }

    private func restoreAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let category = previousCategory,
           let mode = previousMode,
           let options = previousOptions {
            try? session.setCategory(category, mode: mode, options: options)
        }
        previousCategory = nil
        previousMode = nil
        previousOptions = nil
    }

    private func clearRecording() {
        recorder?.stop()
        recorder = nil
        removeTemporaryRecording()
    }

    private func removeTemporaryRecording() {
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }
    }

    private enum ATHLTHGroqTurnFailure: Error { case microphone }

    private struct GroqRequest: Encodable {
        let providerConsent: Bool
        let microphoneConsent: Bool
        let language: String
        let tone: String
        let audioBase64: String
    }

    private struct GroqReply: Decodable {
        let transcript: String
        let reply: String
    }
}

struct ATHLTHGroqVoiceCoachView: View {
    enum Source { case phoneWorkout, mirroredWatchWorkout }
    let source: Source
    init(source: Source = .phoneWorkout) { self.source = source }

    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    @EnvironmentObject private var mirroring: WorkoutMirroringStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coach = ATHLTHGroqVoiceTurn()
    @State private var consent = false
    @State private var previousPhoneCoachWasPlaying = false
    @State private var hasPhoneCoachLease = false
    @State private var hasWatchCoachLease = false
    @State private var warning: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                ATHLTHPlusFeatureGate(
                    feature: .audioCoach,
                    title: "ATHLTH AI Coach",
                    message: ATHLTHLocalization.choose(
                        english: "Groq voice coaching is an ATHLTH+ feature.",
                        norwegian: "Groq talecoach er en ATHLTH+-funksjon."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 7) {
                            Image(systemName: coach.phase == .recording
                                ? "waveform.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            Text("ATHLTH · Groq")
                                .font(.title2.weight(.bold))
                            Text(phaseText)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 19)

                        Toggle(ATHLTHLocalization.choose(
                            english: "I agree that my voice is sent to Groq for transcription and a reply.",
                            norwegian: "Jeg godtar at stemmen sendes til Groq for transkribering og svar."
                        ), isOn: $consent)
                        .font(.subheadline)

                        Text(ATHLTHLocalization.choose(
                            english: "Speak for up to 10 seconds, then tap Send. No workout metrics, GPS, heart rate, health history or location are shared in this pilot. Your normal workout continues.",
                            norwegian: "Snakk i opptil 10 sekunder, og trykk Send. Ingen øktdata, GPS, puls, helsehistorikk eller posisjon deles i denne testutgaven. Treningsøkten fortsetter."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        if let warning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if let question = coach.question {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ATHLTHLocalization.choose(english: "You said", norwegian: "Du sa"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(question)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15))
                        }
                        if let answer = coach.answer {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ATHLTH Coach")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(answer)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15))
                        }

                        if coach.phase == .recording {
                            Button {
                                coach.sendRecording(
                                    language: settings.audioCoachLanguage,
                                    motivating: settings.audioCoachSpeechStyle == .motivating,
                                    selectedVoice: settings.audioCoachVoiceIdentifier,
                                    voiceRate: settings.audioCoachSpeechRate,
                                    voiceVolume: settings.audioCoachSpeechVolume
                                )
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Send question", norwegian: "Send spørsmål"
                                ), systemImage: "arrow.up.circle.fill")
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                        } else {
                            Button {
                                Task {
                                    guard activateCoachAudioIfPossible() else { return }
                                    let success = await coach.startRecording()
                                    if !success { restoreOrdinaryCoachAudio() }
                                }
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Tap to speak", norwegian: "Trykk for å snakke"
                                ), systemImage: "mic.fill")
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                            .disabled(!consent || coach.isBusy)
                        }

                        Button(role: .destructive) {
                            coach.stop()
                            restoreOrdinaryCoachAudio()
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Stop voice coach", norwegian: "Stopp talecoach"
                            ), systemImage: "stop.circle")
                                .frame(maxWidth: .infinity, minHeight: 45)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(17)
                }
            }
            .background(ATHLTHTheme.canvasBottom.ignoresSafeArea())
            .navigationTitle("AI Coach · Groq")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) {
                        stopAll()
                        dismiss()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { stopAll() }
            }
            .onChange(of: recorder.active?.id) { _, current in
                if case .phoneWorkout = source, current == nil {
                    stopAll()
                    dismiss()
                }
            }
            .onChange(of: mirroring.hasActiveMirroredWorkout) { _, active in
                if case .mirroredWatchWorkout = source, !active {
                    stopAll()
                    dismiss()
                }
            }
            .onDisappear { stopAll() }
        }
    }

    private var phaseText: String {
        switch coach.phase {
        case .idle: return ATHLTHLocalization.choose(
            english: "Ask your coach in Norwegian or English.",
            norwegian: "Still et spørsmål til coachen.")
        case .recording: return ATHLTHLocalization.choose(
            english: "Listening · Tap Send when finished.",
            norwegian: "Lytter · Trykk Send når du er ferdig.")
        case .processing: return ATHLTHLocalization.choose(
            english: "Groq is thinking…", norwegian: "Groq finner et svar …")
        case .speaking: return ATHLTHLocalization.choose(
            english: "Answer spoken with your system voice.",
            norwegian: "Svaret leses med den valgte systemstemmen.")
        case .error(let issue): return issue
        }
    }

    private func activateCoachAudioIfPossible() -> Bool {
        warning = nil
        switch source {
        case .phoneWorkout:
            guard recorder.active != nil else { return false }
            if !hasPhoneCoachLease {
                previousPhoneCoachWasPlaying = !recorder.coachSpeechPaused
                if previousPhoneCoachWasPlaying {
                    recorder.setCoachSpeechPaused(true)
                }
                hasPhoneCoachLease = true
            }
        case .mirroredWatchWorkout:
            guard mirroring.hasActiveMirroredWorkout else { return false }
            if !hasWatchCoachLease {
                guard watchConnection.sendAIConversationVoiceSuppression(true) else {
                    warning = ATHLTHLocalization.choose(
                        english: "Connect Apple Watch and iPhone before starting.",
                        norwegian: "Koble til Apple Watch og iPhone før du starter."
                    )
                    return false
                }
                mirroring.setAIConversationActive(true)
                hasWatchCoachLease = true
            }
        }
        return true
    }

    private func restoreOrdinaryCoachAudio() {
        if hasPhoneCoachLease {
            if previousPhoneCoachWasPlaying {
                recorder.setCoachSpeechPaused(false)
            }
            hasPhoneCoachLease = false
            previousPhoneCoachWasPlaying = false
        }
        if hasWatchCoachLease {
            mirroring.setAIConversationActive(false)
            _ = watchConnection.sendAIConversationVoiceSuppression(false)
            hasWatchCoachLease = false
        }
    }

    private func stopAll() {
        coach.stop()
        restoreOrdinaryCoachAudio()
        consent = false
    }
}
