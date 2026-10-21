import SwiftUI

/// Shared presentation preference for Browse, My Routes and Choose Route.
/// Switching mode changes only the layout, never the data source or filters.
enum ATHLTHRouteBrowseMode: String, CaseIterable, Identifiable {
    case cards, list, map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards:
            return ATHLTHLocalization.choose(english: "Cards", norwegian: "Kort")
        case .list:
            return ATHLTHLocalization.choose(english: "List", norwegian: "Liste")
        case .map:
            return ATHLTHLocalization.choose(english: "Map", norwegian: "Kart")
        }
    }

    var symbol: String {
        switch self {
        case .cards: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .map: return "map"
        }
    }
}

/// One control used for all route-library presentations.
/// Supports Dynamic Type without overflowing the library header.
struct ATHLTHRouteBrowseModePicker: View {
    @Binding var selection: ATHLTHRouteBrowseMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ATHLTHRouteBrowseMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.17)) {
                        selection = mode
                    }
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(
                            selection == mode ? Color.white : ATHLTHPlanDesign.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 35)
                        .background(
                            selection == mode
                                ? ATHLTHTheme.accentDeep
                                : Color.clear,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(ATHLTHPlanDesign.warmSurface, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Route view", norwegian: "Rutevisning"))
    }
}
