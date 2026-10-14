import AVFoundation
import Foundation
import SwiftUI

/// A manual, bounded Audio Coach conversation over Realtime WebSocket.
/// The API key never enters the app: the server issues an ephemeral token.
/// No workout telemetry is sent or read by this transport. The user's normal
/// HealthKit workout continues independently and remains the source of truth.
@MainActor
final class ATHLTHLiveAICoachConversation: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case listening
        case responding
        case failed(String)

        var isActive: Bool {
            switch self {
            case .connecting, .listening, .responding: true
            case .idle, .failed: false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastTranscript: String?

    private let issuer = ATHLTHLiveAICoachSessionService()
    private var socket: URLSessionWebSocketTask?
    private var readerTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var outputPlayer: AVAudioPlayerNode?
    private var waitingAudio: [Data] = []
    private var senderTask: Task<Void, Never>?
    private var generation = UUID()
    private var ownsAudioSession = false

    func start(
        microphoneConsent: Bool,
        providerConsent: Bool,
        language: WatchAudioCoachLanguage,
        style: ATHLTHCoachSpeechStyle
    ) async {
        guard !state.isActive else { return }
        guard microphoneConsent && providerConsent else {
            state = .failed(ATHLTHLocalization.choose(
                english: "Confirm both audio permissions first.",
                norwegian: "Bekreft begge lydtillatelsene først."
            ))
            return
        }

        state = .connecting
        lastTranscript = nil
        let sessionID = UUID()
        generation = sessionID
        let permission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard generation == sessionID else { return }
        guard permission else {
            state = .failed(ATHLTHLocalization.choose(
                english: "Microphone permission is off in Settings.",
                norwegian: "Mikrofontilgang er avslått i innstillingene."
            ))
            return
        }

        do {
            let secret = try await issuer.requestToken(
                microphoneConsent: microphoneConsent,
                aiAudioProcessingConsent: providerConsent,
                language: language,
                speechStyle: style
            )
            guard generation == sessionID else { return }

            var components = URLComponents(
                string: "wss://api.openai.com/v1/realtime"
            )!
            components.queryItems = [
                URLQueryItem(name: "model", value: secret.model)
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(
                "Bearer " + secret.token, forHTTPHeaderField: "Authorization"
            )
            request.timeoutInterval = 20
            let connection = URLSession.shared.webSocketTask(with: request)
            socket = connection
            connection.resume()

            // A session is never left listening indefinitely. Network loss,
            // navigation away or app background also stops capture.
            readerTask = Task { [weak self] in
                guard let self else { return }
                await self.receiveEvents(for: sessionID)
            }
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, let self else { return }
                self.stop()
            }
        } catch {
            guard generation == sessionID else { return }
            stop()
            state = .failed(ATHLTHLocalization.choose(
                english: "AI voice conversations are not available yet. Your workout keeps recording.",
                norwegian: "AI-samtale er ikke tilgjengelig ennå. Treningsøkten registreres videre."
            ))
        }
    }

    private func receiveEvents(for id: UUID) async {
        guard let socket else { return }
        do {
            while generation == id {
                let message = try await socket.receive()
                guard generation == id else { break }
                let bytes: Data
                switch message {
                case .string(let text):
                    bytes = Data(text.utf8)
                case .data(let data):
                    bytes = data
                @unknown default:
                    continue
                }
                guard let event = try? JSONSerialization.jsonObject(
                    with: bytes
                ) as? [String: Any],
                let type = event["type"] as? String else { continue }
                switch type {
                case "session.created":
                    try configureAudio()
                    try await send([
                        "type": "session.update",
                        "session": [
                            "type": "realtime",
                            "audio": [
                                "input": [
                                    "format": ["type": "audio/pcm", "rate": 24_000],
                                    "turn_detection": [
                                        "type": "server_vad",
                                        "silence_duration_ms": 550,
                                        "prefix_padding_ms": 300,
                                    ],
                                ],
                                "output": ["format": [
                                    "type": "audio/pcm", "rate": 24_000
                                ]],
                            ],
                        ],
                    ])
                    state = .listening
                case "input_audio_buffer.speech_started":
                    outputPlayer?.stop()
                    outputPlayer?.play()
                    state = .listening
                case "response.created":
                    state = .responding
                case "response.output_audio.delta":
                    if let delta = event["delta"] as? String,
                       let raw = Data(base64Encoded: delta) {
                        playPCM(raw)
                    }
                case "response.output_audio_transcript.delta":
                    if let text = event["delta"] as? String {
                        let previous = lastTranscript ?? ""
                        lastTranscript = String((previous + text).suffix(600))
                    }
                case "response.done":
                    state = .listening
                case "error":
                    throw ATHLTHConversationFailure.provider
                default:
                    break
                }
            }
        } catch {
            guard generation == id else { return }
            stop()
            state = .failed(ATHLTHLocalization.choose(
                english: "Voice connection ended. Your workout is still running.",
                norwegian: "Taleforbindelsen ble brutt. Treningsøkten fortsetter."
            ))
        }
    }

    private func configureAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.setActive(true)
        ownsAudioSession = true

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(
            from: inputFormat, to: captureFormat
        ) else { throw ATHLTHConversationFailure.audio }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(
                (Double(buffer.frameLength) * 24_000 / inputFormat.sampleRate)
                    .rounded(.up) + 64
            )
            guard let pcm = AVAudioPCMBuffer(
                pcmFormat: captureFormat, frameCapacity: capacity
            ) else { return }
            var didProvideInput = false
            var conversionError: NSError?
            let status = converter.convert(to: pcm, error: &conversionError) {
                _, inputStatus in
                if didProvideInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard conversionError == nil,
                  status != .error,
                  pcm.frameLength > 0,
                  let channel = pcm.int16ChannelData?[0]
            else { return }
            let bytes = Data(
                bytes: channel,
                count: Int(pcm.frameLength) * MemoryLayout<Int16>.size
            )
            Task { @MainActor [weak self] in
                self?.enqueueMicrophone(bytes)
            }
        }

        do {
            try engine.start()
            player.play()
            audioEngine = engine
            outputPlayer = player
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }
    }

    private func enqueueMicrophone(_ data: Data) {
        guard state.isActive, socket != nil else { return }
        // Bounded upload queue: stale mic chunks are dropped on poor networks.
        if waitingAudio.count >= 8 {
            waitingAudio.removeFirst(waitingAudio.count - 7)
        }
        waitingAudio.append(data)
        guard senderTask == nil else { return }
        senderTask = Task { [weak self] in
            guard let self else { return }
            await self.sendQueuedAudio()
        }
    }

    private func sendQueuedAudio() async {
        defer { senderTask = nil }
        while !waitingAudio.isEmpty, socket != nil {
            let frame = waitingAudio.removeFirst()
            do {
                try await send([
                    "type": "input_audio_buffer.append",
                    "audio": frame.base64EncodedString(),
                ])
            } catch {
                stop()
                state = .failed(ATHLTHLocalization.choose(
                    english: "Microphone connection was interrupted.",
                    norwegian: "Mikrofonforbindelsen ble avbrutt."
                ))
                return
            }
        }
    }

    private func send(_ event: [String: Any]) async throws {
        guard let socket else { throw ATHLTHConversationFailure.provider }
        let data = try JSONSerialization.data(withJSONObject: event)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ATHLTHConversationFailure.provider
        }
        try await socket.send(.string(text))
    }

    private func playPCM(_ bytes: Data) {
        guard let player = outputPlayer,
              bytes.count >= 2 else { return }
        let frameCount = bytes.count / 2
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)
        ), let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        bytes.withUnsafeBytes { raw in
            for index in 0..<frameCount {
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1]) << 8
                samples[index] = Float(Int16(bitPattern: low | high)) / 32768
            }
        }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }

    func stop() {
        generation = UUID()
        readerTask?.cancel()
        readerTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        senderTask?.cancel()
        senderTask = nil
        waitingAudio.removeAll(keepingCapacity: false)
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        outputPlayer?.stop()
        outputPlayer = nil
        audioEngine = nil
        if ownsAudioSession {
            ownsAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation
            )
        }
        lastTranscript = nil
        state = .idle
    }

    private enum ATHLTHConversationFailure: Error {
        case provider, audio
    }
}

/// The user must explicitly consent and tap Start. Closing, backgrounding or
/// completing a conversation immediately releases the microphone and resumes
/// the user's previous ordinary Audio Coach mute state.
struct ATHLTHLiveAICoachConversationView: View {
    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var conversation = ATHLTHLiveAICoachConversation()
    @State private var allowMicrophone = false
    @State private var allowProviderProcessing = false
    @State private var restoreCoachVoice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ATHLTHPlusFeatureGate(
                    feature: .audioCoach,
                    title: "ATHLTH AI Coach",
                    message: ATHLTHLocalization.choose(
                        english: "Private voice conversations are an ATHLTH+ feature.",
                        norwegian: "Private AI-samtaler er en ATHLTH+-funksjon."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(spacing: 9) {
                            Image(systemName: conversation.state.isActive
                                ? "waveform.circle.fill" : "mic.circle")
                                .font(.system(size: 54))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                            Text(ATHLTHLocalization.choose(
                                english: "Talk with ATHLTH",
                                norwegian: "Snakk med ATHLTH"
                            ))
                            .font(.title2.bold())
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)

                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Before you begin",
                                    norwegian: "Før du starter"
                                ),
                                systemImage: "lock.shield"
                            )
                            .font(.headline)

                            if !conversation.state.isActive {
                                Toggle(ATHLTHLocalization.choose(
                                    english: "Allow microphone while this conversation is active",
                                    norwegian: "Tillat mikrofon mens samtalen pågår"
                                ), isOn: $allowMicrophone)
                                Toggle(ATHLTHLocalization.choose(
                                    english: "I agree that my voice will be processed by the AI provider",
                                    norwegian: "Jeg godtar at stemmen behandles av AI-leverandøren"
                                ), isOn: $allowProviderProcessing)
                            }
                            Text(ATHLTHLocalization.choose(
                                english: "No live heart rate, route or pace is shared with this AI yet. The recording continues in ATHLTH, and the conversation ends automatically after five minutes.",
                                norwegian: "AI-en mottar ennå ikke puls, rute eller tempo. Økten registreres videre i ATHLTH. Samtalen avsluttes automatisk etter fem minutter."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))

                        if let transcript = conversation.lastTranscript {
                            Text(transcript)
                                .font(.subheadline)
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                        }

                        if conversation.state.isActive {
                            Button(role: .destructive) {
                                finish()
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "End conversation",
                                    norwegian: "Avslutt samtale"
                                ), systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button {
                                begin()
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Start voice conversation",
                                    norwegian: "Start talesamtale"
                                ), systemImage: "mic.fill")
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accentDeep)
                            .disabled(!allowMicrophone || !allowProviderProcessing)
                        }
                    }
                    .padding(17)
                }
            }
            .background(ATHLTHTheme.canvasBottom.ignoresSafeArea())
            .navigationTitle("ATHLTH AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) {
                        finish()
                        dismiss()
                    }
                }
            }
            .onChange(of: conversation.state) { _, updated in
                if !updated.isActive { restoreOrdinaryCoach() }
            }
            .onChange(of: scenePhase) { _, updated in
                if updated != .active { finish() }
            }
            .onDisappear { finish() }
        }
    }

    private var statusText: String {
        switch conversation.state {
        case .idle:
            return ATHLTHLocalization.choose(
                english: "Opt in, then start when you want to speak.",
                norwegian: "Gi samtykke, og start når du vil snakke."
            )
        case .connecting:
            return ATHLTHLocalization.choose(
                english: "Connecting securely…",
                norwegian: "Oppretter sikker forbindelse …"
            )
        case .listening:
            return ATHLTHLocalization.choose(
                english: "Listening · tap End to stop",
                norwegian: "Lytter · trykk Avslutt for å stoppe"
            )
        case .responding:
            return ATHLTHLocalization.choose(
                english: "Coach is replying…",
                norwegian: "Coachen svarer …"
            )
        case .failed(let error):
            return error
        }
    }

    private func begin() {
        if !recorder.coachSpeechPaused {
            recorder.setCoachSpeechPaused(true)
            restoreCoachVoice = true
        }
        Task {
            await conversation.start(
                microphoneConsent: allowMicrophone,
                providerConsent: allowProviderProcessing,
                language: settings.audioCoachLanguage,
                style: settings.audioCoachSpeechStyle
            )
        }
    }

    private func restoreOrdinaryCoach() {
        if restoreCoachVoice {
            recorder.setCoachSpeechPaused(false)
            restoreCoachVoice = false
        }
    }

    private func finish() {
        conversation.stop()
        restoreOrdinaryCoach()
    }
}
