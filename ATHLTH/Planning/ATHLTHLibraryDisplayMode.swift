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
        accessibilityText: Bool = false
    ) -> [GridItem] {
        guard mode == .grid else { return [GridItem(.flexible())] }
        let usable = max(0, width - reservedHorizontalSpace)
        let minimumCardWidth: CGFloat = accessibilityText ? 160 : 104
        let threeFit = usable >= 3 * minimumCardWidth + 2 * spacing
        let twoFit = usable >= 2 * minimumCardWidth + spacing
        let count = accessibilityText ? (twoFit ? 2 : 1) :
            (threeFit ? 3 : (twoFit ? 2 : 1))
        return (0..<count).map { _ in GridItem(.flexible(), spacing: spacing) }
    }
}
