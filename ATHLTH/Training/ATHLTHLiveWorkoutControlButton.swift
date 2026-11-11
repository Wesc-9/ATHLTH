import SwiftUI

/// Common live-workout navigation controls. Sport-specific metrics, maps,
/// intervals and set cards remain in the individual recording views.
enum ATHLTHLiveWorkoutControlKind {
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
