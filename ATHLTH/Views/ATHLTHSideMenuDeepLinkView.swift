import SwiftUI

/// Reuses the app's real feature screens when launching from the iPhone
/// side menu. These tools are not clones of the five main tabs.
struct ATHLTHSideMenuDeepLinkView: View {
    @Environment(\.dismiss) private var dismiss

    let destination: ATHLTHSideMenuDestination

    @ViewBuilder
    var body: some View {
        if destination == .profile {
            // Keep the *existing* profile appearance edge-to-edge. The only
            // new control is a floating close affordance above the hero.
            NavigationStack {
                ATHLTHProfileView()
                    .overlay(alignment: .topLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Color.black.opacity(0.32),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ATHLTHLocalization.choose(
                            english: "Close profile",
                            norwegian: "Lukk profil"
                        ))
                        .padding(.leading, 14)
                        .padding(.top, 14)
                    }
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTheme.premiumGoldSoft.opacity(0.7),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Close and return to Home",
                    norwegian: "Lukk og gå tilbake til Hjem"
                ))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 57)
            .background(ATHLTHTheme.premiumGoldSoft.opacity(0.18))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ATHLTHTheme.premiumGold.opacity(0.2))
                    .frame(height: 1)
            }

            NavigationStack {
                destinationContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ATHLTHTheme.premiumGoldSoft.ignoresSafeArea())
            .accessibilityIdentifier("athlth-side-menu-full-screen-destination")
        }
    }

    private var title: String {
        switch destination {
        case .profile:
            return ATHLTHLocalization.choose(
                english: "My profile", norwegian: "Min profil"
            )
        case .trainTogether:
            return ATHLTHLocalization.choose(
                english: "Train Together", norwegian: "Tren sammen"
            )
        case .arena:
            return "Arena"
        case .clubs:
            return ATHLTHLocalization.choose(
                english: "Clubs", norwegian: "Klubber"
            )
        case .exerciseProgress:
            return ATHLTHLocalization.choose(
                english: "Exercise progression", norwegian: "Øvelsesfremdrift"
            )
        default:
            return "ATHLTH"
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .profile:
            // Full-screen profile presentation, rather than the previous
            // 90%-height sheet. The entire existing profile view is reused.
            ATHLTHProfileView()

        case .trainTogether:
            TrainTogetherMarketplaceView()

        case .arena:
            ATHLTHArenaV3HomeView()

        case .clubs:
            ATHLTHCommunityV5View(initialTab: .clubs)

        case .exerciseProgress:
            ScrollView {
                ATHLTHSpecificProgressView()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

        case .home, .search, .inbox, .notifications,
             .trainingLibrary, .myExercises, .myRoutes,
             .myTrainingPlans, .myWorkouts, .ghostRace, .settings:
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english: "Return to Home",
                    norwegian: "Gå tilbake til Hjem"
                ),
                systemImage: "house"
            )
        }
    }
}
