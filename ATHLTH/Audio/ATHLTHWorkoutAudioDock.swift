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

    static func showsSpotifyLauncher(spotifyConnected: Bool) -> Bool {
        // Never surface a Spotify shortcut before ATHLTH is authorized.
        spotifyConnected
    }
}

struct ATHLTHWorkoutAudioDock: View {
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @State private var preferredMode: ATHLTHWorkoutAudioDockMode = .coach
    @State private var isExpanded = false

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
                VStack(alignment: .trailing, spacing: 8) {
                    if isExpanded {
                        expandedControlBar
                            .transition(
                                .opacity.combined(with: .move(edge: .bottom))
                            )
                    }

                    // A single icon is the resting state. Only show Spotify
                    // when ATHLTH has an authorized Spotify connection.
                    HStack(spacing: 9) {
                        if coachVisible {
                            launcher(for: .coach)
                        }
                        if ATHLTHWorkoutAudioDockPolicy.showsSpotifyLauncher(
                            spotifyConnected: spotify.isConnected
                        ) {
                            launcher(for: .spotify)
                        }
                    }
                    .padding(.trailing, 18)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 7)
                .animation(.easeInOut(duration: 0.22), value: isExpanded)
                .task(id: isExpanded && selectedMode == .spotify
                    && spotify.isConnected) {
                    // Never send a read or control request while collapsed.
                    guard isExpanded && selectedMode == .spotify &&
                            spotify.isConnected else { return }
                    await spotify.handleIPhoneAudioDockCommand(.requestState)
                }
                .onChange(of: spotify.isConnected) { _, connected in
                    if !connected && preferredMode == .spotify {
                        isExpanded = false
                    }
                }
                .onDisappear { isExpanded = false }
            }
        }
    }

    private func launcher(for mode: ATHLTHWorkoutAudioDockMode) -> some View {
        let active = isExpanded && selectedMode == mode
        return Button {
            if active {
                isExpanded = false
            } else {
                preferredMode = mode
                isExpanded = true
            }
        } label: {
            Group {
                if mode == .spotify {
                    ATHLTHSpotifyGlyph()
                        .frame(width: 31, height: 31)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 31, height: 31)
                        .background(ATHLTHTheme.accentSoft, in: Circle())
                }
            }
            .frame(width: 47, height: 47)
            .background(ATHLTHPlanDesign.surface, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        active
                            ? ATHLTHTheme.premiumGold.opacity(0.72)
                            : ATHLTHPlanDesign.outline,
                        lineWidth: active ? 1.5 : 0.8
                    )
            }
            .shadow(
                color: ATHLTHTheme.accentDeep.opacity(0.09),
                radius: 9,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .spotify
            ? (active
                ? ATHLTHLocalization.choose(
                    english: "Hide Spotify controls",
                    norwegian: "Skjul Spotify-kontroller"
                  )
                : ATHLTHLocalization.choose(
                    english: "Show Spotify controls",
                    norwegian: "Vis Spotify-kontroller"
                  ))
            : (active
                ? ATHLTHLocalization.choose(
                    english: "Hide Audio Coach controls",
                    norwegian: "Skjul Audio Coach-kontroller"
                  )
                : ATHLTHLocalization.choose(
                    english: "Show Audio Coach controls",
                    norwegian: "Vis Audio Coach-kontroller"
                  )))
    }

    private var expandedControlBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                if selectedMode == .spotify {
                    ATHLTHSpotifyGlyph()
                        .frame(width: 31, height: 31)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 31, height: 31)
                }

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

                if selectedMode == .spotify {
                    spotifyActions
                } else if let onCoachSettings {
                    Button(action: onCoachSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 35, height: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english: "Audio Coach settings",
                            norwegian: "Audio Coach-innstillinger"
                        )
                    )
                }
            }
            if selectedMode == .coach {
                HStack(spacing: 9) {
                    coachActions
                    if coachEnabled && !coachManagedOnWatch {
                        ATHLTHAudioRouteControl(compact: true)
                            .frame(width: 37, height: 35)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHPlanDesign.surface,
                    ATHLTHTheme.cardWarm.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.07),
            radius: 13,
            y: 5
        )
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
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


/// Vector Spotify glyph. No external logo files or network image dependencies.
private struct ATHLTHSpotifyGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Color(red: 0.114, green: 0.725, blue: 0.329))
                Path { path in
                    path.move(to: CGPoint(x: 0.19 * side, y: 0.36 * side))
                    path.addCurve(
                        to: CGPoint(x: 0.83 * side, y: 0.45 * side),
                        control1: CGPoint(x: 0.42 * side, y: 0.29 * side),
                        control2: CGPoint(x: 0.64 * side, y: 0.35 * side)
                    )
                    path.move(to: CGPoint(x: 0.22 * side, y: 0.52 * side))
                    path.addCurve(
                        to: CGPoint(x: 0.79 * side, y: 0.59 * side),
                        control1: CGPoint(x: 0.40 * side, y: 0.46 * side),
                        control2: CGPoint(x: 0.64 * side, y: 0.52 * side)
                    )
                    path.move(to: CGPoint(x: 0.25 * side, y: 0.66 * side))
                    path.addCurve(
                        to: CGPoint(x: 0.74 * side, y: 0.73 * side),
                        control1: CGPoint(x: 0.43 * side, y: 0.61 * side),
                        control2: CGPoint(x: 0.61 * side, y: 0.66 * side)
                    )
                }
                .stroke(
                    Color.black.opacity(0.86),
                    style: StrokeStyle(
                        lineWidth: max(1.3, side * 0.07),
                        lineCap: .round
                    )
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
