import SwiftUI

/// One user-scoped display preference shared by the Library hub, Train,
/// workout library and exercise pickers. Defaults to the established list
/// for existing users until they explicitly choose another layout.
enum ATHLTHLibraryDisplayMode: String, Codable, CaseIterable, Identifiable {
    case list, grid

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
    var title: String {
        switch self {
        case .list: return ATHLTHLocalization.choose(english: "List", norwegian: "Liste")
        case .grid: return ATHLTHLocalization.choose(english: "Grid", norwegian: "Rutenett")
        }
    }

    static func load(userID: UUID) -> Self {
        AccountLocalStorage.read(
            Self.self, name: "libraryDisplayModeV1", userID: userID
        ) ?? .list
    }
    func save(userID: UUID) {
        AccountLocalStorage.write(
            self, name: "libraryDisplayModeV1", userID: userID
        )
    }
}

struct ATHLTHLibraryDisplayPicker: View {
    @Binding var selection: ATHLTHLibraryDisplayMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ATHLTHLibraryDisplayMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            selection == mode
                                ? Color.white : ATHLTHPlanDesign.secondaryInk
                        )
                        .frame(width: 42, height: 37)
                        .background(
                            selection == mode
                                ? ATHLTHPlanDesign.ink : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selection == mode ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(
            ATHLTHPlanDesign.selectedSurface,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .accessibilityElement(children: .contain)
    }
}


/// Caps the library at three cards across. A small phone or enlarged text
/// automatically falls back to fewer columns rather than squeezing titles.
enum ATHLTHLibraryGridColumns {
    static func make(
        mode: ATHLTHLibraryDisplayMode,
        width: CGFloat,
        reservedHorizontalSpace: CGFloat = 0,
        spacing: CGFloat = 10,
        accessibilityText: Bool = false,
        preferredMinimumCardWidth: CGFloat = 0
    ) -> [GridItem] {
        guard mode == .grid else { return [GridItem(.flexible())] }
        let usable = max(0, width - reservedHorizontalSpace)
        let minimumCardWidth: CGFloat = max(
            accessibilityText ? 160 : 104, preferredMinimumCardWidth
        )
        let threeFit = usable >= 3 * minimumCardWidth + 2 * spacing
        let twoFit = usable >= 2 * minimumCardWidth + spacing
        let count = accessibilityText ? (twoFit ? 2 : 1) :
            (threeFit ? 3 : (twoFit ? 2 : 1))
        return (0..<count).map { _ in GridItem(.flexible(), spacing: spacing) }
    }
}


/// Card-only naming policy. Keep source names unchanged for training records,
/// workout reuse, search, synchronization and full accessibility labels.
enum ATHLTHLibraryName {
    static let maximumCustomExerciseCharacters = 40
    static let maximumWorkoutCharacters = 48
    static let gridCharacters = 24
    static let listCharacters = 40

    /// Human-edited aliases for legacy library labels. The originals remain
    /// intact in persisted workouts and are still visible in their details.
    static func conciseWorkoutName(_ original: String) -> String {
        switch original.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "nb_NO")) {
        case "half-cooper vo2-maks test":
            return "Half-Cooper VO2-test"
        case "terrreng fart", "terreng fart":
            return "Terrengfart"
        case "kritisk fart test":
            return "Kritisk fart-test"
        default:
            return original
        }
    }

    /// Limit the *visible* label, not the underlying model or exercise ID.
    /// Character-based slicing avoids splitting emoji/combined Unicode text.
    static func shortLabel(_ original: String, maximumCharacters: Int) -> String {
        guard maximumCharacters > 1, original.count > maximumCharacters else {
            return original
        }
        let prefix = String(original.prefix(maximumCharacters - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }

    static func workoutCard(_ original: String, grid: Bool) -> String {
        shortLabel(
            conciseWorkoutName(original),
            maximumCharacters: grid ? gridCharacters : listCharacters
        )
    }

    static func exerciseCard(_ original: String, grid: Bool) -> String {
        shortLabel(
            original,
            maximumCharacters: grid ? gridCharacters : listCharacters
        )
    }
}
