import SwiftUI

/// Only offer actions that are valid for the current recorded workout.
enum HomeActivityRunAction: String, Hashable, Identifiable {
    case share
    case openMap
    case openSavedRoute
    case savePrivateRoute
    case removeFromATHLTH

    var id: String { rawValue }

    static func available(
        isIndoor: Bool,
        hasRecordedGPS: Bool,
        hasSavedRoute: Bool,
        canRemoveFromATHLTH: Bool
    ) -> [Self] {
        var result: [Self] = [.share]
        if !isIndoor && hasRecordedGPS { result.append(.openMap) }
        if hasSavedRoute {
            result.append(.openSavedRoute)
        } else if !isIndoor && hasRecordedGPS {
            result.append(.savePrivateRoute)
        }
        if canRemoveFromATHLTH { result.append(.removeFromATHLTH) }
        return result
    }

    var isDestructive: Bool { self == .removeFromATHLTH }

    var symbol: String {
        switch self {
        case .share: "square.and.arrow.up"
        case .openMap: "map"
        case .openSavedRoute: "figure.run.circle"
        case .savePrivateRoute: "bookmark"
        case .removeFromATHLTH: "trash"
        }
    }

    var title: String {
        switch self {
        case .share: localized("Share result", "Del resultat")
        case .openMap: localized("View route map", "Vis rutekart")
        case .openSavedRoute: localized("Route and Ghost Race", "Rute og Ghost Race")
        case .savePrivateRoute: localized("Save route privately", "Lagre ruten privat")
        case .removeFromATHLTH: localized("Remove from ATHLTH", "Fjern fra ATHLTH")
        }
    }

    var subtitle: String {
        switch self {
        case .share:
            localized("Create an image or share in the community",
                      "Del som bilde eller i fellesskapet")
        case .openMap:
            localized("Explore your recorded route",
                      "Utforsk den registrerte ruten")
        case .openSavedRoute:
            localized("Open your route and Ghost options",
                      "Åpne ruten og Ghost-alternativer")
        case .savePrivateRoute:
            localized("Keep this route in your own library",
                      "Behold ruten i ditt eget bibliotek")
        case .removeFromATHLTH:
            localized("Your Apple Health data will remain",
                      "Data i Apple Health beholdes")
        }
    }

    private func localized(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

/// The host handles navigation and destructive confirmation; this compact
/// panel provides one consistent premium entry point for workout actions.
struct HomeActivityRunActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let actions: [HomeActivityRunAction]
    let onSelect: (HomeActivityRunAction) -> Void

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 46, height: 46)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Workout actions", "Økthandlinger"))
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(tr("Options for this workout", "Valg for denne treningsøkten"))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                Spacer(minLength: 6)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .frame(width: 32, height: 32)
                        .background(ATHLTHPlanDesign.warmSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Close", "Lukk"))
            }
            .padding(.top, 13)

            Rectangle()
                .fill(ATHLTHPlanDesign.warmDivider)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(actions.filter { !$0.isDestructive }) { action in
                        actionRow(action)
                    }
                    if let removal = actions.first(where: { $0.isDestructive }) {
                        Rectangle()
                            .fill(ATHLTHPlanDesign.warmDivider)
                            .frame(height: 1)
                            .padding(.vertical, 7)
                        actionRow(removal)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .presentationDetents([.height(panelHeight), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .presentationBackground(ATHLTHPlanDesign.canvas)
    }

    private var panelHeight: CGFloat {
        CGFloat(174 + actions.count * 72 +
                (actions.contains(.removeFromATHLTH) ? 16 : 0))
    }

    private func actionRow(_ action: HomeActivityRunAction) -> some View {
        let foreground: Color = action.isDestructive
            ? Color(red: 0.69, green: 0.27, blue: 0.23)
            : ATHLTHPlanDesign.accentInk

        return Button {
            onSelect(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: 42, height: 42)
                    .background(
                        action.isDestructive
                            ? Color(red: 0.98, green: 0.93, blue: 0.91)
                            : ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            action.isDestructive
                                ? foreground : ATHLTHPlanDesign.ink
                        )
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                ATHLTHPlanDesign.warmSurface.opacity(0.85),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(ATHLTHPlanDesign.warmDivider.opacity(0.6),
                            lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
    }
}
