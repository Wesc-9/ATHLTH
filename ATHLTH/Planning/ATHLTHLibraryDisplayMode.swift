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


/// Width rules shared by iPhone, iPad and Stage Manager. The old 760-point
/// content cap left most of the iPad landscape screen unused. Allow library
/// content to fill its parent, but keep individual cards easy to scan.
enum ATHLTHLibraryResponsiveLayout {
    static func columns(
        mode: ATHLTHLibraryDisplayMode,
        width: CGFloat,
        reservedHorizontalSpace: CGFloat = 36,
        spacing: CGFloat = 10,
        accessibilityText: Bool = false,
        preferredMinimumCardWidth: CGFloat = 0
    ) -> [GridItem] {
        let usable = max(0, width - reservedHorizontalSpace)
        if mode == .list {
            // Two readable list columns instead of one enormous landscape row.
            let threshold: CGFloat = accessibilityText ? 1450 : 900
            let count = usable >= threshold ? 2 : 1
            return (0..<count).map { _ in GridItem(.flexible(), spacing: spacing) }
        }
        if usable < 820 || accessibilityText {
            // Preserve the familiar iPhone layouts and larger text sizes.
            return ATHLTHLibraryGridColumns.make(
                mode: mode,
                width: width,
                reservedHorizontalSpace: reservedHorizontalSpace,
                spacing: spacing,
                accessibilityText: accessibilityText,
                preferredMinimumCardWidth: preferredMinimumCardWidth
            )
        }
        let minimum = max(215, preferredMinimumCardWidth)
        let count = min(5, max(1, Int((usable + spacing) / (minimum + spacing))))
        return (0..<count).map { _ in GridItem(.flexible(), spacing: spacing) }
    }

    static func hubColumns(for width: CGFloat) -> [GridItem] {
        let count = width >= 1100 ? 4 : (width >= 720 ? 3 : 2)
        return (0..<count).map { _ in GridItem(.flexible(), spacing: 11) }
    }

    static func featuredCardWidth(
        for width: CGFloat,
        accessibilityText: Bool
    ) -> CGFloat {
        if accessibilityText { return 300 }
        // One horizontally scrollable card at phone width, two equal cards
        // spanning the available width on larger iPad windows.
        return max(246, (width - 48) / 2)
    }

    static func featuredCardHeight(for cardWidth: CGFloat, accessibilityText: Bool) -> CGFloat {
        if accessibilityText { return 280 }
        return min(320, max(228, cardWidth * 0.49))
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


/// Identical ATHLTH / Mine selector across exercises, workouts, plans and routes.
struct ATHLTHLibrarySourcePicker: View {
    @Binding var selection: ATHLTHUnifiedLibraryScope

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ATHLTHUnifiedLibraryScope.allCases) { source in
                Button {
                    selection = source
                } label: {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == source ? Color.white : ATHLTHPlanDesign.ink)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            selection == source ? ATHLTHPlanDesign.ink : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == source ? [.isSelected] : [])
                .accessibilityIdentifier("athlth-library-source-\(source.rawValue)")
            }
        }
        .padding(4)
        .background(
            ATHLTHPlanDesign.selectedSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }
}
