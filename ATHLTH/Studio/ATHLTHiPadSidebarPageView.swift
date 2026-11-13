import SwiftUI

/// Full-size Studio destinations for secondary iPad sidebar items.
/// Profile and Ghost Race use the detail column like Arena and Clubs.
/// Only Messages keeps its independent docked inspector.
struct ATHLTHiPadSidebarPageView: View {
    let destination: ATHLTHSideMenuDestination
    let onBack: () -> Void

    private let ink = ATHLTHStudioStyle.ink
    private let gold = ATHLTHStudioStyle.gold
    private let canvas = ATHLTHStudioStyle.canvas

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Button(action: onBack) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Back to Studio",
                            norwegian: "Tilbake til Studio"
                        ),
                        systemImage: "chevron.left"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(gold)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.72))

            Rectangle()
                .fill(ATHLTHStudioStyle.outline.opacity(0.55))
                .frame(height: 1)

            destinationContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(canvas.ignoresSafeArea())
        .accessibilityIdentifier(
            "athlth-ipad-sidebar-page-\(destination.rawValue)"
        )
    }

    var title: String {
        switch destination {
        case .search:
            return ATHLTHLocalization.choose(english: "Search", norwegian: "Søk")
        case .notifications:
            return ATHLTHLocalization.choose(
                english: "Notifications", norwegian: "Varsler"
            )
        case .trainTogether:
            return ATHLTHLocalization.choose(
                english: "Train Together", norwegian: "Tren sammen"
            )
        case .arena:
            return "Arena"
        case .ghostRace:
            return "Ghost Race"
        case .profile:
            return ATHLTHLocalization.choose(
                english: "Profile", norwegian: "Profil"
            )
        case .clubs:
            return ATHLTHLocalization.choose(
                english: "Clubs", norwegian: "Klubber"
            )
        default:
            return "ATHLTH"
        }
    }

    private var symbol: String {
        switch destination {
        case .search: "magnifyingglass"
        case .notifications: "bell"
        case .trainTogether: "person.2"
        case .arena: "trophy"
        case .ghostRace: "flag.checkered"
        case .profile: "person.crop.circle"
        case .clubs: "person.3"
        default: "square.grid.2x2"
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .search:
            ATHLTHGlobalSearchView()
        case .notifications:
            ATHLTHNotificationCenterView()
        case .trainTogether:
            TrainTogetherMarketplaceView()
        case .arena:
            ATHLTHArenaV3HomeView()
        case .ghostRace:
            GhostRaceHubView()
        case .profile:
            ATHLTHProfileView()
        case .clubs:
            ATHLTHCommunityV5View(initialTab: .clubs)
        default:
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english: "Select a Studio section",
                    norwegian: "Velg en Studio-side"
                ),
                systemImage: "square.grid.2x2"
            )
        }
    }
}
