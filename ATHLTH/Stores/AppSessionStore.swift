import Foundation

@MainActor
final class AppSessionStore: ObservableObject {
    @Published var profile: UserProfile
    @Published var activePlan: TrainingPlan?
    @Published var savedRoutes: [TrainingRoute]
    @Published var challenges: [RouteChallenge]
    @Published var previewModeEnabled: Bool

    init(
        profile: UserProfile = PreviewData.profile,
        activePlan: TrainingPlan? = PreviewData.trainingPlan,
        savedRoutes: [TrainingRoute] = [PreviewData.route],
        challenges: [RouteChallenge] = [PreviewData.challenge],
        previewModeEnabled: Bool = true
    ) {
        self.profile = profile
        self.activePlan = activePlan
        self.savedRoutes = savedRoutes
        self.challenges = challenges
        self.previewModeEnabled = previewModeEnabled
    }

    func beginTrainingStatus(for session: PlannedSession) {
        profile.presence = TrainingPresence(
            state: .training,
            workoutTitle: session.title,
            startedAt: Date(),
            visibility: .friends
        )
    }

    func endTrainingStatus() {
        profile.presence = TrainingPresence(
            state: .available,
            workoutTitle: nil,
            startedAt: nil,
            visibility: profile.presence.visibility
        )
    }
}
