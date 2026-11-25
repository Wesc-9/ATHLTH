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


// Opt-in anchor for a custom menu; other sports retain their existing
// navigation and presentation. Resolve it outside the top safe-area inset.
struct ATHLTHLiveAddMenuAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

enum ATHLTHLiveAddMenuLayout {
    static func frame(anchor: CGRect, container: CGSize) -> CGRect {
        let margin: CGFloat = 12
        let width = min(310, max(0, container.width - margin * 2))
        let x = min(max(margin, anchor.midX - width / 2),
                    max(margin, container.width - margin - width))
        let y = min(max(margin, anchor.maxY + 8), max(margin, container.height - margin))
        return CGRect(x: x, y: y, width: width,
                      height: max(0, container.height - y - margin))
    }
}

enum ATHLTHLiveAddAction: String, CaseIterable, Identifiable {
    case exercise
    case workout
    case reorder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exercise: ATHLTHLocalization.choose(english: "Add exercise", norwegian: "Legg til øvelse")
        case .workout: ATHLTHLocalization.choose(english: "Add workout", norwegian: "Legg til treningsøkt")
        case .reorder: ATHLTHLocalization.choose(english: "Edit order", norwegian: "Rediger rekkefølge")
        }
    }

    var subtitle: String {
        switch self {
        case .exercise: ATHLTHLocalization.choose(english: "An exercise from the library", norwegian: "Enkeltøvelse fra biblioteket")
        case .workout: ATHLTHLocalization.choose(english: "Insert a ready-made workout", norwegian: "Sett inn en ferdig økt")
        case .reorder: ATHLTHLocalization.choose(english: "Adjust exercises and structure", norwegian: "Flytt på øvelser og struktur")
        }
    }

    var symbol: String {
        switch self {
        case .exercise: "dumbbell"
        case .workout: "rectangle.stack"
        case .reorder: "list.number"
        }
    }
}

/// A lightweight, opaque menu, with no system confirmation bubble or
/// independent workout state. All selections route back to the host.
struct ATHLTHLiveAddMenu: View {
    let onSelect: (ATHLTHLiveAddAction) -> Void
    let onClose: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            menuRows
            ScrollView { menuRows }
                .scrollBounceBehavior(.basedOnSize)
        }
        .background(ATHLTHTrainDesign.paper, in: RoundedRectangle(cornerRadius: 21))
        .clipShape(RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .strokeBorder(ATHLTHTrainDesign.gold.opacity(0.38), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .shadow(color: ATHLTHTrainDesign.ink.opacity(0.13), radius: 15, x: 0, y: 7)
        .accessibilityIdentifier("athlth-live-add-menu")
        .accessibilityAction(.escape) { onClose() }
    }

    private var menuRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ATHLTHLocalization.choose(english: "ADD TO WORKOUT", norwegian: "LEGG TIL I ØKTEN"))
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)

            ForEach(ATHLTHLiveAddAction.allCases) { action in
                if action != .exercise {
                    Rectangle()
                        .fill(ATHLTHTrainDesign.rule.opacity(0.45))
                        .frame(height: 1)
                        .padding(.leading, 54)
                        .padding(.trailing, 10)
                }
                Button { onSelect(action) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                            .frame(width: 36, height: 36)
                            .background(ATHLTHTrainDesign.paleGold.opacity(0.65),
                                        in: RoundedRectangle(cornerRadius: 11))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTrainDesign.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 3)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ATHLTHTrainDesign.bronze)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ATHLTHLiveAddMenuRowStyle())
                .accessibilityIdentifier("athlth-live-add-" + action.rawValue)
            }
        }
        .padding(7)
    }
}

private struct ATHLTHLiveAddMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ATHLTHTrainDesign.paleGold.opacity(0.55) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12))
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
    var anchorsLiveAddMenu = false
    var liveAddMenuExpanded = false
    var onOverview: (() -> Void)? = nil
    let onMinimize: () -> Void
    let onSpotify: () -> Void
    let onAdd: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 2) {
                stripButton("chevron.down",
                            hint: ATHLTHLocalization.choose(
                                english: "Minimize workout", norwegian: "Legg ned økten"
                            ), action: onMinimize)

                if let onOverview {
                    stripButton("list.bullet",
                                hint: ATHLTHLocalization.choose(
                                    english: "Workout overview", norwegian: "Øktoversikt"
                                ), action: onOverview)
                }

                Button(action: onSpotify) {
                    ATHLTHSpotifyGlyph()
                        .frame(width: 28, height: 28)
                        .frame(width: 43, height: 44)
                        .background(spotifyExpanded
                            ? ATHLTHTheme.premiumGoldSoft : Color.clear,
                            in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Show or hide Spotify controls",
                    norwegian: "Vis eller skjul Spotify-kontroller"
                ))
                .accessibilityValue(spotifyExpanded
                    ? ATHLTHLocalization.choose(english: "Expanded", norwegian: "Åpen")
                    : ATHLTHLocalization.choose(english: "Collapsed", norwegian: "Lukket"))
            }
            .padding(.horizontal, 4)
            .background(ATHLTHTrainDesign.paper, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.8
                )
            }

            VStack(alignment: .center, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(minWidth: 36, maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            HStack(spacing: 0) {
                Button(action: onAdd) {
                    Image(systemName: liveAddMenuExpanded ? "xmark" : "plus")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .frame(width: 43, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!addEnabled)
                .opacity(addEnabled ? 1 : 0.4)
                .accessibilityLabel(liveAddMenuExpanded
                    ? ATHLTHLocalization.choose(english: "Close add menu", norwegian: "Lukk meny")
                    : ATHLTHLocalization.choose(english: "Add to workout", norwegian: "Legg til i økten"))
                .anchorPreference(key: ATHLTHLiveAddMenuAnchor.self, value: .bounds) {
                    anchorsLiveAddMenu ? $0 : nil
                }
                Button(action: onFinish) {
                    Text(ATHLTHLocalization.choose(
                        english: "Finish", norwegian: "Avslutt"
                    ))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(finishDisabled
                        ? ATHLTHTrainDesign.secondary : ATHLTHTrainDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: 52, minHeight: 48)
                    .padding(.trailing, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(finishDisabled)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Finish workout", norwegian: "Avslutt økten"
                ))
            }
            .background(ATHLTHTrainDesign.paper, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.8
                )
            }
        }
        .frame(minHeight: 52)
        .accessibilityIdentifier("athlth-live-workout-top-strip")
    }

    private func stripButton(
        _ symbol: String, hint: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 43, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hint)
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
