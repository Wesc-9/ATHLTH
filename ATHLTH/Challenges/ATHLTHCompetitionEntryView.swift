import SwiftUI

/// Every generic competition entry (friend, Arena, Community and Challenges)
/// uses the exact same six-card activity picker as Train Together and Plan.
struct ATHLTHCompetitionEntryView: View {
    var preselectedFriend: SocialProfileCard? = nil
    var initialFormat: ATHLTHCompetitionFormat? = nil

    @State private var selectedActivity: ATHLTHQuickStartActivity?

    var body: some View {
        ATHLTHPlannedWorkoutTypePickerView(
            purpose: .competition,
            onCreateNew: { type in
                selectedActivity = ATHLTHCompetitionCreationPolicy.quickStartActivity(for: type)
            },
            onSelect: { _, _ in }
        )
        .sheet(item: $selectedActivity) { activity in
            // Keep the existing cold boundary and all invitation/scoring
            // parameters. Only the activity selection surface changes.
            AnyView(ATHLTHCompetitionCreationView(
                initialActivity: activity,
                advanced: true,
                initialFormat: initialFormat,
                preselectedFriend: preselectedFriend
            ))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
