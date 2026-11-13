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
                        .frame(width: 36, height: 44)
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
                        .frame(width: 38, height: 44)
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
                        .frame(width: 39, height: 48)
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
