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
        ) ?? .grid
    }
    func save(userID: UUID) {
        AccountLocalStorage.write(
            self, name: "libraryDisplayModeV1", userID: userID
        )
    }
}

/// A single compact layout control for exercises, workouts, plans and
/// routes. The grid density is shared across library categories; map remains
/// a route-specific presentation.
struct ATHLTHLibraryDisplayPicker: View {
    @Binding var selection: ATHLTHLibraryDisplayMode
    var columns: Binding<Int>? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let columns {
                layoutButton(symbol: "list.bullet", title: label("List", "Liste"),
                             active: selection == .list) {
                    selection = .list
                }
                layoutButton(symbol: "square.grid.2x2", title: label("2 columns", "2 kolonner"),
                             active: selection == .grid && columns.wrappedValue == 2) {
                    columns.wrappedValue = 2
                    selection = .grid
                }
                layoutButton(symbol: "square.grid.3x2", title: label("3 columns", "3 kolonner"),
                             active: selection == .grid && columns.wrappedValue == 3) {
                    columns.wrappedValue = 3
                    selection = .grid
                }
                Menu {
                    Button(label("Automatic", "Automatisk"),
                           systemImage: selection == .grid && columns.wrappedValue == 0
                               ? "checkmark" : "square.grid.2x2") {
                        columns.wrappedValue = 0
                        selection = .grid
                    }
                    Button(label("4 columns (iPad)", "4 kolonner (iPad)")) {
                        columns.wrappedValue = 4
                        selection = .grid
                    }
                    Button(label("5 columns (iPad)", "5 kolonner (iPad)")) {
                        columns.wrappedValue = 5
                        selection = .grid
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selection == .grid &&
                            (columns.wrappedValue == 0 || columns.wrappedValue >= 4)
                                ? Color.white : ATHLTHPlanDesign.secondaryInk)
                        .frame(width: 35, height: 37)
                        .background(
                            selection == .grid &&
                            (columns.wrappedValue == 0 || columns.wrappedValue >= 4)
                                ? ATHLTHPlanDesign.ink : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(label("More layout options", "Flere visninger"))
            } else {
                ForEach(ATHLTHLibraryDisplayMode.allCases) { mode in
                    layoutButton(symbol: mode.symbol, title: mode.title,
                                 active: selection == mode) {
                        selection = mode
                    }
                }
            }
        }
        .padding(3)
        .background(
            ATHLTHPlanDesign.selectedSurface,
            in: RoundedRectangle(cornerRadius: 13)
        )
        .accessibilityElement(children: .contain)
    }

    private func label(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func layoutButton(symbol: String, title: String, active: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Color.white : ATHLTHPlanDesign.secondaryInk)
                .frame(width: 36, height: 37)
                .background(active ? ATHLTHPlanDesign.ink : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// Personal layout preference, not a server-side workout or route setting.
/// Stored by account so multiple users on one device do not affect each other.
enum ATHLTHLibraryColumnPreference {
    static func load(userID: UUID) -> Int {
        let value = AccountLocalStorage.read(
            Int.self, name: "libraryColumnPreferenceV1", userID: userID
        ) ?? 0
        return (0...5).contains(value) ? value : 0
    }

    static func save(_ value: Int, userID: UUID) {
        AccountLocalStorage.write(
            max(0, min(5, value)),
            name: "libraryColumnPreferenceV1",
            userID: userID
        )
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
        preferredMinimumCardWidth: CGFloat = 0,
        preferredColumns: Int = 0
    ) -> [GridItem] {
        let usable = max(0, width - reservedHorizontalSpace)
        if mode == .list {
            // Two readable list columns instead of one enormous landscape row.
            let threshold: CGFloat = accessibilityText ? 1450 : 900
            let count = usable >= threshold ? 2 : 1
            return (0..<count).map { _ in GridItem(.flexible(), spacing: spacing) }
        }
        if preferredColumns > 0 {
            // On iPhone, let users choose two or three. On iPad allow four
            // or five, but always respect the actual Stage Manager window.
            let desired = min(usable < 740 ? 3 : 5, preferredColumns)
            let minimum: CGFloat = accessibilityText ? 160.0
                : (desired == 2 ? 140.0 : (desired == 3 ? 102.0 : 185.0))
            let fitting = max(1, Int((usable + spacing) / (minimum + spacing)))
            let count = min(desired, fitting)
            return (0..<count).map { _ in
                GridItem(.flexible(), spacing: spacing)
            }
        }
        if usable < 820 || accessibilityText {
            // Adaptive defaults: 2 or 3 phone cards, up to 5 on iPad.
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
    /// Route library uses “Public”; other libraries keep ATHLTH branding.
    var athlthTitle: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ATHLTHUnifiedLibraryScope.allCases) { source in
                Button {
                    selection = source
                } label: {
                    Text(source == .athlth ? (athlthTitle ?? source.title) : source.title)
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
