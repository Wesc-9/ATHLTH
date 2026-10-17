import SwiftUI

/// A deep-link destination that refreshes the correct challenge store before
/// showing details. The app can launch from a terminated state without having
/// loaded Community or the challenge lists first.
struct ATHLTHChallengeNotificationDestination: View {
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var officialWeekly: OfficialWeeklyChallengeStore
    @EnvironmentObject private var social: SocialStore

    let route: ATHLTHChallengeNotificationRoute

    @State private var didAttemptRefresh = false

    private var targetLoaded: Bool {
        switch route {
        case .personal(let id):
            return challenges.challenge(id: id) != nil
        case .officialWeekly(let id):
            return officialWeekly.challenges.contains { $0.id == id }
        }
    }

    var body: some View {
        Group {
            if !targetLoaded && !didAttemptRefresh {
                ProgressView(
                    ATHLTHLocalization.choose(
                        english: "Opening challenge…",
                        norwegian: "Åpner utfordringen…"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch route {
                case .personal(let id):
                    ChallengeDetailView(challengeID: id)
                case .officialWeekly(let id):
                    OfficialWeeklyChallengeDetailView(challengeID: id)
                }
            }
        }
        .task(id: route.id) {
            didAttemptRefresh = false
            if !targetLoaded {
                switch route {
                case .personal:
                    await social.refreshChallenges(
                        challengeStore: challenges
                    )
                case .officialWeekly:
                    await officialWeekly.refresh(
                        force: true,
                        ensureYearAheadSchedule: false
                    )
                }
            }
            guard !Task.isCancelled else { return }
            didAttemptRefresh = true
        }
    }
}
