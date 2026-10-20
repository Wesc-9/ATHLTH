import SwiftUI

/// Compact, shared sound controls for active Quick Train sessions.
///
/// The workout's record/pause/finish controls remain separate. Spotify is
/// controlled through its existing OAuth-backed playback store; spoken
/// guidance is controlled by the workout's own coach engine.
enum ATHLTHWorkoutAudioDockMode: Equatable {
    case coach
    case spotify
}

enum ATHLTHWorkoutAudioDockPolicy {
    static func resolvedMode(
        preferred: ATHLTHWorkoutAudioDockMode,
        coachVisible: Bool,
        spotifyConnected: Bool
    ) -> ATHLTHWorkoutAudioDockMode {
        if !coachVisible && spotifyConnected { return .spotify }
        if !spotifyConnected { return .coach }
        return preferred
    }

    static func isVisible(
        coachVisible: Bool,
        spotifyConnected: Bool
    ) -> Bool {
        coachVisible || spotifyConnected
    }
}

struct ATHLTHWorkoutAudioDock: View {
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @State private var preferredMode: ATHLTHWorkoutAudioDockMode = .coach

    let coachVisible: Bool
    let coachEnabled: Bool
    let coachPaused: Bool
    let coachManagedOnWatch: Bool
    let canReplayCoach: Bool
    let onCoachStatus: () -> Void
    let onCoachTogglePause: () -> Void
    let onCoachReplay: () -> Void
    let onCoachSettings: (() -> Void)?

    private var selectedMode: ATHLTHWorkoutAudioDockMode {
        ATHLTHWorkoutAudioDockPolicy.resolvedMode(
            preferred: preferredMode,
            coachVisible: coachVisible,
            spotifyConnected: spotify.isConnected
        )
    }

    var body: some View {
        Group {
            if ATHLTHWorkoutAudioDockPolicy.isVisible(
                coachVisible: coachVisible,
                spotifyConnected: spotify.isConnected
            ) {
                VStack(spacing: 7) {
                    if selectedMode == .spotify && !coachVisible {
                        // One compact row when Spotify is the only audio source:
                        // leave maximum room for Set/Next Exercise controls.
                        HStack(spacing: 9) {
                            Image(systemName: "music.note")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 28, height: 35)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                    .lineLimit(1)
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            spotifyActions
                        }
                    } else {
                        HStack(spacing: 7) {
                            if coachVisible && spotify.isConnected {
                                modeButton(
                                    .coach,
                                    title: "Audio Coach",
                                    systemImage: "waveform"
                                )
                                modeButton(
                                    .spotify,
                                    title: "Spotify",
                                    systemImage: "music.note"
                                )
                            } else {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "AUDIO",
                                        norwegian: "LYD"
                                    )
                                )
                                .font(.caption2.weight(.bold))
                                .tracking(0.9)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer(minLength: 0)

                            if selectedMode == .coach, let onCoachSettings {
                                Button(action: onCoachSettings) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                        .frame(width: 35, height: 35)
                                        .background(
                                            Color.white.opacity(0.85),
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    ATHLTHLocalization.choose(
                                        english: "Audio Coach settings",
                                        norwegian: "Innstillinger for Audio Coach"
                                    )
                                )
                            }

                            if coachVisible && coachEnabled && !coachManagedOnWatch {
                                ATHLTHAudioRouteControl(compact: true)
                                    .frame(width: 37, height: 35)
                            }
                        }

                        HStack(spacing: 8) {
                            Image(
                                systemName: selectedMode == .coach
                                    ? "waveform"
                                    : "music.note"
                            )
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                ATHLTHTheme.accentDeep,
                                in: Circle()
                            )
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if selectedMode == .coach {
                                coachActions
                            } else {
                                spotifyActions
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 23, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                }
                .shadow(
                    color: ATHLTHTheme.accentDeep.opacity(0.12),
                    radius: 16,
                    y: 5
                )
                .padding(.horizontal, 14)
                .padding(.top, 5)
                .padding(.bottom, 4)
                .accessibilityElement(children: .contain)
                .task(id: spotify.isConnected) {
                    // Read-only metadata refresh: never auto-resume playback.
                    guard spotify.isConnected else { return }
                    await spotify.handleIPhoneAudioDockCommand(.requestState)
                }
                .onAppear {
                    if !coachEnabled && spotify.isConnected {
                        preferredMode = .spotify
                    }
                }
            }
        }
    }

    private var title: String {
        if selectedMode == .spotify {
            return spotify.watchTrackTitle
                ?? spotify.activePlaylist?.name
                ?? "Spotify"
        }
        return "Audio Coach"
    }

    private var subtitle: String {
        if selectedMode == .spotify {
            if let error = spotify.lastErrorMessage, !error.isEmpty {
                return error
            }
            if let artist = spotify.watchArtistName, !artist.isEmpty {
                return artist
            }
            return spotify.isPlaying
                ? ATHLTHLocalization.choose(
                    english: "Music playing",
                    norwegian: "Musikken spiller"
                )
                : ATHLTHLocalization.choose(
                    english: "Music paused",
                    norwegian: "Musikken er pauset"
                )
        }

        if !coachEnabled {
            return ATHLTHLocalization.choose(
                english: "Off · workout continues",
                norwegian: "Av · økten fortsetter"
            )
        }
        if coachManagedOnWatch {
            return ATHLTHLocalization.choose(
                english: "Controlled on Apple Watch",
                norwegian: "Styres på Apple Watch"
            )
        }
        return coachPaused
            ? ATHLTHLocalization.choose(
                english: "Voice paused · workout continues",
                norwegian: "Tale pauset · økten fortsetter"
            )
            : ATHLTHLocalization.choose(
                english: "Voice on · workout continues",
                norwegian: "Tale aktiv · økten fortsetter"
            )
    }

    @ViewBuilder
    private var coachActions: some View {
        if !coachEnabled {
            if let onCoachSettings {
                Button {
                    onCoachSettings()
                } label: {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Enable",
                            norwegian: "Aktiver"
                        )
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(ATHLTHTheme.accentDeep, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        } else if !coachManagedOnWatch {
            Button(action: onCoachStatus) {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Status now",
                        norwegian: "Status nå"
                    )
                )
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(ATHLTHTheme.accentDeep, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(coachPaused)
            .accessibilityLabel(
                ATHLTHLocalization.choose(
                    english: "Speak workout status now",
                    norwegian: "Les opp treningsstatus nå"
                )
            )

            roundAction(
                systemImage: coachPaused ? "play.fill" : "pause.fill",
                label: coachPaused
                    ? ATHLTHLocalization.choose(
                        english: "Resume voice",
                        norwegian: "Fortsett tale"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Pause voice",
                        norwegian: "Pause tale"
                    ),
                action: onCoachTogglePause
            )

            TimelineView(.periodic(from: .now, by: 5)) { _ in
                roundAction(
                    systemImage: "arrow.counterclockwise",
                    label: ATHLTHLocalization.choose(
                        english: "Listen again",
                        norwegian: "Hør igjen"
                    ),
                    enabled: canReplayCoach && !coachPaused,
                    action: onCoachReplay
                )
            }
        }
    }

    private var spotifyActions: some View {
        HStack(spacing: 6) {
            roundAction(
                systemImage: spotify.isPlaying ? "pause.fill" : "play.fill",
                label: spotify.isPlaying
                    ? ATHLTHLocalization.choose(
                        english: "Pause Spotify",
                        norwegian: "Pause Spotify"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Resume Spotify",
                        norwegian: "Fortsett Spotify"
                    )
            ) {
                Task {
                    await spotify.handleIPhoneAudioDockCommand(
                        spotify.isPlaying ? .pause : .resume
                    )
                }
            }

            roundAction(
                systemImage: "forward.end.fill",
                label: ATHLTHLocalization.choose(
                    english: "Next Spotify track",
                    norwegian: "Neste Spotify-låt"
                )
            ) {
                Task {
                    await spotify.handleIPhoneAudioDockCommand(.next)
                }
            }
        }
    }

    private func modeButton(
        _ mode: ATHLTHWorkoutAudioDockMode,
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            preferredMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    selectedMode == mode
                        ? ATHLTHTheme.accentDeep
                        : ATHLTHTheme.mutedText
                )
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(
                    selectedMode == mode
                        ? ATHLTHTheme.accentSoft
                        : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            selectedMode == mode ? [.isSelected] : []
        )
    }

    private func roundAction(
        systemImage: String,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 36, height: 38)
                .background(Color.white.opacity(0.9), in: Circle())
                .overlay {
                    Circle()
                        .stroke(
                            ATHLTHTheme.accentDeep.opacity(0.1),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}
