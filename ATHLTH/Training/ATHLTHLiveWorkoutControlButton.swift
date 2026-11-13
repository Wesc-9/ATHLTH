import SwiftUI

/// Common live-workout navigation controls. Sport-specific metrics, maps,
/// intervals and set cards remain in the individual recording views.
enum ATHLTHLiveWorkoutControlKind: Equatable {
    case minimize
    case add
    case finish

    var symbol: String {
        switch self {
        case .minimize: return "chevron.down"
        case .add: return "plus"
        case .finish: return "stop.fill"
        }
    }

    var label: String {
        switch self {
        case .minimize: return ATHLTHLocalization.choose(
            english: "Minimize workout", norwegian: "Legg ned økten"
        )
        case .add: return ATHLTHLocalization.choose(
            english: "Add to workout", norwegian: "Legg til i økten"
        )
        case .finish: return ATHLTHLocalization.choose(
            english: "Finish workout", norwegian: "Avslutt økten"
        )
        }
    }
}

struct ATHLTHLiveWorkoutControlButton: View {
    let kind: ATHLTHLiveWorkoutControlKind
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: kind.symbol)
                .font(.system(
                    size: kind == .finish ? 14 : 17,
                    weight: .semibold
                ))
                .foregroundStyle(kind == .finish ? Color.red :
                    ATHLTHTheme.accentDeep)
                .frame(width: 43, height: 43)
                .background(
                    kind == .finish
                        ? Color.red.opacity(0.09)
                        : Color.white.opacity(0.90),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            kind == .finish
                                ? Color.red.opacity(0.26)
                                : Color.black.opacity(0.05),
                            lineWidth: 0.8
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(kind.label)
    }
}


/// Shared compact top controls for phone workouts and Apple Watch mirrors.
/// The content area owns the expanded Spotify player and the fixed pause dock.
struct ATHLTHLiveWorkoutTopStrip: View {
    let title: String
    let subtitle: String
    let spotifyExpanded: Bool
    var addEnabled = true
    var finishDisabled = false
    let onMinimize: () -> Void
    let onSpotify: () -> Void
    let onAdd: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Minimize workout", norwegian: "Legg ned økten"
                ))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Button(action: onSpotify) {
                    ATHLTHSpotifyGlyph()
                        .frame(width: 27, height: 27)
                        .frame(width: 44, height: 44)
                        .background(
                            spotifyExpanded
                                ? ATHLTHTheme.premiumGoldSoft
                                : Color.clear,
                            in: Capsule()
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Show or hide Spotify controls",
                    norwegian: "Vis eller skjul Spotify-kontroller"
                ))
                .accessibilityValue(spotifyExpanded
                    ? ATHLTHLocalization.choose(english: "Expanded", norwegian: "Åpen")
                    : ATHLTHLocalization.choose(english: "Collapsed", norwegian: "Lukket")
                )
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ATHLTHTrainDesign.paper, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.8
                )
            }

            HStack(spacing: 0) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .frame(width: 44, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!addEnabled)
                .opacity(addEnabled ? 1 : 0.4)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Add to workout", norwegian: "Legg til i økten"
                ))

                Button(action: onFinish) {
                    Text(ATHLTHLocalization.choose(
                        english: "Finish", norwegian: "Avslutt"
                    ))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(finishDisabled
                        ? ATHLTHTrainDesign.secondary
                        : ATHLTHTrainDesign.ink
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minWidth: 57, minHeight: 48)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(finishDisabled)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Finish workout", norwegian: "Avslutt økten"
                ))
            }
            .padding(.leading, 2)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 52)
            .background(ATHLTHTrainDesign.paper, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.8
                )
            }
        }
        .accessibilityIdentifier("athlth-live-workout-top-strip")
    }
}


/// Same expandable Spotify dock on local strength and mirrored Watch workouts.
/// The player is only instantiated when the athlete opens Spotify in the top strip.
struct ATHLTHLiveSpotifyExpandedBar: View {
    @EnvironmentObject private var spotify: SpotifyPlaybackStore
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        HStack(spacing: 6) {
            ATHLTHSpotifyGlyph()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            Text("Spotify")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ATHLTHTrainDesign.ink)

            Button {
                Task {
                    await spotify.handleIPhoneAudioDockCommand(
                        spotify.isPlaying ? .pause : .resume
                    )
                }
            } label: {
                Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 35, height: 42)
                    .contentShape(Rectangle())
            }
            .disabled(!spotify.isConnected)
            .accessibilityLabel(spotify.isPlaying
                ? ATHLTHLocalization.choose(english: "Pause Spotify", norwegian: "Pause Spotify")
                : ATHLTHLocalization.choose(english: "Play Spotify", norwegian: "Spill Spotify")
            )

            Button {
                Task { await spotify.handleIPhoneAudioDockCommand(.next) }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 35, height: 42)
                    .contentShape(Rectangle())
            }
            .disabled(!spotify.isConnected)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Next track", norwegian: "Neste låt"
            ))

            Rectangle()
                .fill(ATHLTHTrainDesign.rule)
                .frame(width: 1, height: 22)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    playlistButton(index: 1, playlist: settings.spotifyQuickPlaylistOne)
                    playlistButton(index: 2, playlist: settings.spotifyQuickPlaylistTwo)
                }
                .frame(minWidth: 150)

                playlistButton(index: 1, playlist: settings.spotifyQuickPlaylistOne)

                Text(
                    spotify.watchTrackTitle ??
                        spotify.activePlaylist?.name ??
                        ATHLTHLocalization.choose(
                            english: "No active playlist", norwegian: "Ingen aktiv spilleliste"
                        )
                )
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ATHLTHTrainDesign.ink)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(ATHLTHTrainDesign.paper, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.8
            )
        }
        .accessibilityIdentifier("athlth-live-expanded-spotify")
        .task {
            // Ask the existing App Remote for fresh playback state only when
            // the expanded player is visible. This never starts music.
            guard spotify.isConnected else { return }
            await spotify.handleIPhoneAudioDockCommand(.requestState)
            if spotify.playlists.isEmpty {
                await spotify.refreshPlaylists()
            }
        }
    }

    private func playlistButton(
        index: Int,
        playlist: SpotifyPlaylistReference?
    ) -> some View {
        Button {
            guard let playlist else { return }
            Task {
                await spotify.startLinkedPlaylist(
                    playlist, settings: settings,
                    respectGlobalAutoplay: false
                )
            }
        } label: {
            Text(playlist?.name ?? "\(index)")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    ATHLTHTheme.premiumGoldSoft,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .disabled(playlist == nil || !spotify.isConnected)
        .accessibilityLabel(playlist.map {
            ATHLTHLocalization.choose(
                english: "Play playlist \($0.name)",
                norwegian: "Spill spillelisten \($0.name)"
            )
        } ?? ATHLTHLocalization.choose(
            english: "Configure playlist \(index) in Settings",
            norwegian: "Velg spilleliste \(index) i Innstillinger"
        ))
    }
}
