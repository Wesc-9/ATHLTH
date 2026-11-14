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
    var columns: Binding<Int>? = nil

    var body: some View {
        Group {
            if let columns {
                HStack(spacing: 7) {
                    ATHLTHLibraryDisplayPicker(
                        selection: Binding(
                            get: { selection == .list ? .list : .grid },
                            set: { selection = $0 == .list ? .list : .cards }
                        ),
                        columns: Binding(
                            get: {
                                // Avoid showing both Map and a grid mode as
                                // selected when Map is the active presentation.
                                selection == .map ? -1 : columns.wrappedValue
                            },
                            set: { columns.wrappedValue = $0 }
                        )
                    )
                    Button {
                        selection = .map
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selection == .map
                                ? Color.white : ATHLTHPlanDesign.secondaryInk)
                            .frame(width: 40, height: 43)
                            .background(
                                selection == .map
                                    ? ATHLTHPlanDesign.ink : ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Map", norwegian: "Kart"
                    ))
                }
            } else {
                legacyPicker
            }
        }
    }

    private var legacyPicker: some View {
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
                                ? ATHLTHPlanDesign.ink
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
        .background(ATHLTHPlanDesign.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                ATHLTHPlanDesign.outline.opacity(0.55), lineWidth: 0.8
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Route view", norwegian: "Rutevisning"))
    }
}
