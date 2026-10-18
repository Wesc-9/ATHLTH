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
    private struct Request: Encodable { let voice: String }
    private struct Reply: Decodable {
        let voice: String
        let audioBase64: String
    }

    func preview(_ voice: String, duckMusic: Bool) {
        guard loadingVoice == nil else { return }
        player?.stop()
        player = nil
        loadingVoice = voice
        message = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let answer: Reply = try await
                    SupabaseEnvironment.client.functions.invoke(
                        "azure-coach-voice",
                        options: FunctionInvokeOptions(body: Request(voice: voice))
                    )
                guard answer.voice == voice,
                      let data = Data(base64Encoded: answer.audioBase64),
                      !data.isEmpty,
                      data.count <= 250_000
                else {
                    throw PreviewError.invalidAudio
                }
                try ATHLTHSpokenAudioSession.activate(duckOtherAudio: duckMusic)
                let audio = try AVAudioPlayer(data: data)
                audio.delegate = self
                guard audio.prepareToPlay(), audio.play() else {
                    throw PreviewError.invalidAudio
                }
                player = audio
                loadingVoice = nil
            } catch {
                loadingVoice = nil
                ATHLTHSpokenAudioSession.deactivate()
                message = ATHLTHLocalization.choose(
                    english: "Azure voice preview is unavailable. Your iPhone's offline voice still works during workouts.",
                    norwegian: "Azure-stemmen kan ikke forhåndslyttes nå. iPhone-stemmen fungerer fortsatt under treningsøkter."
                )
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
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

    private let voices: [(id: String, name: String, detail: String)] = [
        ("finn", "Finn", ATHLTHLocalization.choose(
            english: "Norwegian · male",
            norwegian: "Norsk · mannlig"
        )),
        ("iselin", "Iselin", ATHLTHLocalization.choose(
            english: "Norwegian · female",
            norwegian: "Norsk · kvinnelig"
        )),
        ("pernille", "Pernille", ATHLTHLocalization.choose(
            english: "Norwegian · female",
            norwegian: "Norsk · kvinnelig"
        ))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                ATHLTHLocalization.choose(
                    english: "Try natural Norwegian AI voices",
                    norwegian: "Prøv naturlige norske AI-stemmer"
                ),
                systemImage: "waveform.badge.mic"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.primaryText)

            Text(ATHLTHLocalization.choose(
                english: "Optional Azure Speech F0 pilot. Requires a configured free-tier server. Previews use sample text, not your workout data.",
                norwegian: "Valgfri test med Azure Speech F0. Krever at gratistjenesten er koblet til. Forhåndslytting bruker eksempeltekst, ikke treningsdataene dine."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(voices, id: \.id) { voice in
                HStack(spacing: 9) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name).font(.subheadline.weight(.medium))
                        Text(voice.detail)
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    Spacer(minLength: 4)

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

            Text(ATHLTHLocalization.choose(
                english: "The pilot is for listening and comparing voices. Live workouts still use your selected local system voice.",
                norwegian: "Dette er foreløpig stemmeprøver. Under selve treningen brukes fortsatt den valgte lokale systemstemmen."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .onDisappear { preview.stop() }
    }
}
