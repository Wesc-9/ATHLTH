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

struct ATHLTHAzureCoachVoicePreviewView: View {
    @StateObject private var preview = ATHLTHAzureVoicePreviewPlayer()
    @EnvironmentObject private var settings: AppSettingsStore
    @AppStorage("settings.audioCoach.azureThirdPartyConsent")
    private var allowsAzureWorkoutText = false
    @State private var discoveredVoices: [Voice]?
    @State private var catalogMessage: String?

    private struct CatalogRequest: Encodable {
        let action: String
    }
    private struct CatalogReply: Decodable {
        let voices: [Voice]
    }

    @MainActor
    private func loadAzureVoices() async {
        do {
            let response: CatalogReply = try await
                SupabaseEnvironment.client.functions.invoke(
                    "azure-coach-voice",
                    options: FunctionInvokeOptions(
                        body: CatalogRequest(action: "catalog")
                    )
                )
            guard !response.voices.isEmpty else { return }
            discoveredVoices = response.voices
            catalogMessage = nil
        } catch {
            catalogMessage = ATHLTHAzureVoicePreviewPlayer.diagnostic(error)
        }
    }


    private struct Voice: Identifiable, Decodable {
        let id: String
        let name: String
        let detail: String
    }

    private var voices: [Voice] {
        discoveredVoices ?? [
            Voice(id: "finn", name: "Finn", detail: ATHLTHLocalization.choose(
                english: "Norwegian · male",
                norwegian: "Norsk · mannlig"
            )),
            Voice(id: "iselin", name: "Iselin", detail: ATHLTHLocalization.choose(
                english: "Norwegian · female",
                norwegian: "Norsk · kvinnelig"
            )),
            Voice(id: "pernille", name: "Pernille", detail: ATHLTHLocalization.choose(
                english: "Norwegian · female",
                norwegian: "Norsk · kvinnelig"
            ))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                ATHLTHLocalization.choose(
                    english: "ATHLTH+ · Natural Norwegian voices",
                    norwegian: "ATHLTH+ · Naturlige norske stemmer"
                ),
                systemImage: "waveform.badge.mic"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "Pick an Azure voice for spoken workout guidance, or listen before choosing. If Azure is slow, unavailable or the free budget runs out, ATHLTH uses the offline iPhone voice.",
                norwegian: "Velg en Azure-stemme til talebeskjeder under trening, eller forhåndslytt. Hvis Azure er treg, utilgjengelig eller gratiskvoten er brukt opp, brukes iPhone-stemmen offline."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $allowsAzureWorkoutText) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ATHLTHLocalization.choose(
                        english: "Allow Azure voices during workouts",
                        norwegian: "Tillat Azure-stemmer under trening"
                    ))
                    .font(.subheadline.weight(.medium))
                    Text(ATHLTHLocalization.choose(
                        english: "Workout speech (possibly including pace, distance, time or heart rate) is sent to Microsoft to create audio. No GPS track or health history is sent. Turn off anytime.",
                        norwegian: "Talebeskjeder (som kan inneholde tempo, distanse, tid eller puls) sendes til Microsoft for å lage lyd. GPS-spor og helsehistorikk sendes ikke. Kan slås av når som helst."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
            .tint(ATHLTHTheme.accentDeep)
            .onChange(of: allowsAzureWorkoutText) { _, enabled in
                if !enabled,
                   ATHLTHAzureCoachVoice.key(
                       settings.audioCoachVoiceIdentifier
                   ) != nil {
                    settings.audioCoachVoiceIdentifier = nil
                }
            }

            ForEach(voices) { voice in
                HStack(spacing: 9) {
                    Button {
                        guard allowsAzureWorkoutText else { return }
                        settings.audioCoachLanguage = .norwegian
                        settings.audioCoachVoiceIdentifier =
                            ATHLTHAzureCoachVoice.prefix + voice.id
                    } label: {
                        HStack(spacing: 9) {
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
                            Spacer(minLength: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!allowsAzureWorkoutText)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Use \(voice.name) for Audio Coach",
                        norwegian: "Bruk \(voice.name) i Audio Coach"
                    ))

                    Button {
                        preview.preview(
                            voice.id,
                            duckMusic: settings.audioCoachDuckOtherAudio
                        )
                    } label: {
                        if preview.loadingVoice == voice.id {
                            ProgressView().frame(width: 35, height: 35)
                        } else {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .frame(width: 35, height: 35)
                        }
                    }
                    .disabled(preview.loadingVoice != nil)
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Preview \(voice.name)",
                        norwegian: "Forhåndslytt på \(voice.name)"
                    ))
                }
                .padding(10)
                .background(
                    ATHLTHTheme.accentSoft.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }

            if let message = preview.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let catalogMessage, preview.message == nil {
                Label(catalogMessage, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(ATHLTHLocalization.choose(
                english: "Azure voices require ATHLTH+. Apple Watch uses its own local voice whenever iPhone audio is unavailable. The existing system-voice menu is always available.",
                norwegian: "Azure-stemmer krever ATHLTH+. Apple Watch bruker lokal stemme når iPhone-lyden ikke er tilgjengelig. De vanlige systemstemmene er fortsatt tilgjengelige."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .task { await loadAzureVoices() }
        .onDisappear { preview.stop() }
    }
}
