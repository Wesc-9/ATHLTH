import AVFoundation
import Supabase
import SwiftUI

/// Optional Azure Speech F0 preview. Voice is generated on the server using
/// a fixed sample, never from personal workout or HealthKit measurements.
/// Normal Quick Train speech stays available offline through iOS/watchOS.
@MainActor
final class ATHLTHAzureVoicePreviewPlayer:
    NSObject, ObservableObject, AVAudioPlayerDelegate
{
    @Published private(set) var loadingVoice: String?
    @Published private(set) var message: String?

    private var player: AVAudioPlayer?
    private var ownsAudioSession = false
    private var requestTask: Task<Void, Never>?
    private var requestIdentity = UUID()
    private struct Request: Encodable { let voice: String }
    private struct Reply: Decodable {
        let voice: String
        let audioBase64: String
    }
    private struct ServiceError: Decodable {
        let code: String?
    }

    static func diagnostic(_ error: Error) -> String {
        let code: String?
        let status: Int
        if let failure = error as? FunctionsError,
           case let .httpError(httpStatus, data) = failure {
            code = try? JSONDecoder().decode(ServiceError.self, from: data).code
            status = httpStatus
        } else {
            code = nil
            status = 0
        }

        switch code {
        case "PREMIUM_REQUIRED":
            return ATHLTHLocalization.choose(
                english: "Azure voices require an active ATHLTH+ subscription.",
                norwegian: "Azure-stemmer krever et aktivt ATHLTH+-abonnement.")
        case "NOT_AVAILABLE":
            return ATHLTHLocalization.choose(
                english: "Azure voice service is disabled on the server.",
                norwegian: "Azure-stemmer er deaktivert på serveren.")
        case "FREE_BUDGET_EXHAUSTED", "AI_RATE_LIMIT":
            return ATHLTHLocalization.choose(
                english: "The voice usage limit is reached. Try again later.",
                norwegian: "Talekvoten er brukt opp. Prøv igjen senere.")
        case "UNSUPPORTED_VOICE":
            return ATHLTHLocalization.choose(
                english: "The selected Azure voice is not available in this resource.",
                norwegian: "Den valgte Azure-stemmen finnes ikke i denne ressursen.")
        case "VOICE_CATALOG_UNAVAILABLE", "AZURE_UNAVAILABLE":
            return ATHLTHLocalization.choose(
                english: "Cannot reach the Azure voice service. Check region and voice configuration.",
                norwegian: "Får ikke kontakt med Azure-stemmene. Kontroller region og stemmeoppsett.")
        default:
            if status == 401 || status == 403 {
                return ATHLTHLocalization.choose(
                    english: "Sign in again and verify ATHLTH+ access for Azure voices.",
                    norwegian: "Logg inn på nytt og kontroller ATHLTH+-tilgangen.")
            }
            return ATHLTHLocalization.choose(
                english: "The Azure preview is unavailable right now. Local speech still works.",
                norwegian: "Azure-forhåndslytting er utilgjengelig nå. Lokal tale fungerer fortsatt.")
        }
    }


    func preview(_ voice: String, duckMusic: Bool) {
        guard loadingVoice == nil else { return }
        stop()
        let requestID = UUID()
        requestIdentity = requestID
        loadingVoice = voice
        message = nil

        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let answer: Reply = try await
                    SupabaseEnvironment.client.functions.invoke(
                        "azure-coach-voice",
                        options: FunctionInvokeOptions(body: Request(voice: voice))
                    )
                guard requestIdentity == requestID, !Task.isCancelled else {
                    return
                }
                guard answer.voice == voice,
                      let data = Data(base64Encoded: answer.audioBase64),
                      !data.isEmpty,
                      data.count <= 250_000
                else {
                    throw PreviewError.invalidAudio
                }
                try ATHLTHSpokenAudioSession.activate(duckOtherAudio: duckMusic)
                ownsAudioSession = true
                let audio = try AVAudioPlayer(data: data)
                audio.delegate = self
                guard audio.prepareToPlay(), audio.play() else {
                    throw PreviewError.invalidAudio
                }
                player = audio
                loadingVoice = nil
            } catch {
                guard requestIdentity == requestID, !Task.isCancelled else {
                    return
                }
                loadingVoice = nil
                releaseAudioSessionIfOwned()
                message = Self.diagnostic(error)
            }
        }
    }

    func stop() {
        requestIdentity = UUID()
        requestTask?.cancel()
        requestTask = nil
        loadingVoice = nil
        player?.stop()
        player = nil
        releaseAudioSessionIfOwned()
    }

    private func releaseAudioSessionIfOwned() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        ATHLTHSpokenAudioSession.deactivate()
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in self?.stop() }
    }

    private enum PreviewError: Error {
        case invalidAudio
    }
}

/// One compact list directly below the installed iOS voices. ATHLTH+ is
/// evaluated separately from the general Audio Coach settings so Free users
/// can see (but cannot choose or preview) the premium voices.
struct ATHLTHAzureCoachVoicePreviewView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var session: AppSessionStore
    @StateObject private var preview = ATHLTHAzureVoicePreviewPlayer()

    @AppStorage("settings.audioCoach.azureThirdPartyConsent")
    private var allowsAzureWorkoutText = false
    @State private var discoveredVoices: [Voice]?
    @State private var catalogMessage: String?
    @State private var pendingConsentVoice: Voice?
    @State private var showingRevokeConsent = false

    private struct CatalogRequest: Encodable {
        let action: String
    }
    private struct CatalogReply: Decodable {
        let voices: [Voice]
    }
    private struct Voice: Identifiable, Decodable {
        let id: String
        let name: String
        let detail: String
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    @MainActor
    private func loadAzureVoices() async {
        guard session.hasPaidAccess else { return }
        do {
            let response: CatalogReply = try await
                SupabaseEnvironment.client.functions.invoke(
                    "azure-coach-voice",
                    options: FunctionInvokeOptions(
                        body: CatalogRequest(action: "catalog")
                    )
                )
            if !response.voices.isEmpty {
                discoveredVoices = response.voices
                catalogMessage = nil
            }
        } catch {
            catalogMessage = ATHLTHAzureVoicePreviewPlayer.diagnostic(error)
        }
    }

    private var voices: [Voice] {
        discoveredVoices ?? [
            Voice(id: "finn", name: "Finn",
                  detail: tr("Norwegian · male", "Norsk · mannlig")),
            Voice(id: "iselin", name: "Iselin",
                  detail: tr("Norwegian · female", "Norsk · kvinnelig")),
            Voice(id: "pernille", name: "Pernille",
                  detail: tr("Norwegian · female", "Norsk · kvinnelig"))
        ]
    }

    private func select(_ voice: Voice) {
        guard session.hasPaidAccess else { return }
        guard allowsAzureWorkoutText else {
            pendingConsentVoice = voice
            return
        }
        settings.audioCoachLanguage = .norwegian
        settings.audioCoachVoiceIdentifier =
            ATHLTHAzureCoachVoice.prefix + voice.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                Text("ATHLTH+")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
            }
            .padding(.top, 7)
            .accessibilityAddTraits(.isHeader)

            ForEach(voices) { voice in
                HStack(spacing: 10) {
                    Button {
                        select(voice)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName:
                                settings.audioCoachVoiceIdentifier ==
                                ATHLTHAzureCoachVoice.prefix + voice.id
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(ATHLTHTheme.accentDeep)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(voice.detail)
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        settings.audioCoachVoiceIdentifier ==
                        ATHLTHAzureCoachVoice.prefix + voice.id
                            ? .isSelected : []
                    )
                    .accessibilityLabel(tr(
                        "Choose \(voice.name)", "Velg \(voice.name)"
                    ))

                    Button {
                        preview.preview(
                            voice.id,
                            duckMusic: settings.audioCoachDuckOtherAudio
                        )
                    } label: {
                        if preview.loadingVoice == voice.id {
                            ProgressView()
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .disabled(preview.loadingVoice != nil)
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr(
                        "Preview \(voice.name)", "Forhåndslytt på \(voice.name)"
                    ))
                }
                .padding(10)
                .background(ATHLTHTheme.accentSoft.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 14))
                .opacity(session.hasPaidAccess ? 1 : 0.38)
                .disabled(!session.hasPaidAccess)
            }

            if !session.hasPaidAccess {
                Text(tr(
                    "Azure voices require ATHLTH+.",
                    "Azure-stemmer krever ATHLTH+."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            } else if allowsAzureWorkoutText {
                Button {
                    showingRevokeConsent = true
                } label: {
                    Text(tr("Turn off Microsoft voice", "Slå av Microsoft-tale"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .underline()
                }
                .buttonStyle(.plain)
            }

            if session.hasPaidAccess, let message = preview.message ?? catalogMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert(
            tr("Allow Microsoft voice?", "Tillate Microsoft-tale?"),
            isPresented: Binding(
                get: { pendingConsentVoice != nil },
                set: { if !$0 { pendingConsentVoice = nil } }
            )
        ) {
            Button(tr("Allow and select", "Tillat og velg")) {
                guard let voice = pendingConsentVoice, session.hasPaidAccess else {
                    pendingConsentVoice = nil
                    return
                }
                allowsAzureWorkoutText = true
                pendingConsentVoice = nil
                select(voice)
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingConsentVoice = nil
            }
        } message: {
            Text(tr(
                "Workout speech can include pace, distance, time and heart rate. The speech text is sent to Microsoft for audio generation. GPS tracks and workout history are not sent. You can withdraw consent at any time.",
                "Talebeskjeder kan inneholde tempo, distanse, tid og puls. Teksten sendes til Microsoft for å lage tale. GPS-spor og treningshistorikk sendes ikke. Du kan trekke tilbake samtykket når som helst."
            ))
        }
        .confirmationDialog(
            tr("Turn off Microsoft voice?", "Slå av Microsoft-tale?"),
            isPresented: $showingRevokeConsent,
            titleVisibility: .visible
        ) {
            Button(tr("Turn off", "Slå av"), role: .destructive) {
                allowsAzureWorkoutText = false
                if ATHLTHAzureCoachVoice.key(
                    settings.audioCoachVoiceIdentifier
                ) != nil {
                    settings.audioCoachVoiceIdentifier = nil
                }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        }
        .task {
            await loadAzureVoices()
        }
        .onDisappear {
            preview.stop()
        }
    }
}
