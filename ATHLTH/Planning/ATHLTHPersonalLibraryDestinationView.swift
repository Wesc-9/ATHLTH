import SwiftUI

/// Opens the same personal collection views used by TrainingLibraryHomeView.
/// No alternate data source or duplicate library implementation is introduced.
struct ATHLTHPersonalLibraryDestinationView: View {
    let section: ATHLTHPersonalLibrarySection
    let onStartRunning: (RunningWorkoutTemplate) -> Void
    var onOpenPlan: ((UUID) -> Void)? = nil

    @ViewBuilder
    var body: some View {
        switch section {
        case .exercises:
            ExerciseLibraryView(source: .mine)

        case .routes:
            RouteLibraryListView(source: .mine)

        case .trainingPlans:
            MyTrainingPlansLibraryView(onOpenPlan: onOpenPlan)

        case .workouts:
            LibrarySavedWorkoutsHubView(onStartRunning: onStartRunning)
        }
    }
}
