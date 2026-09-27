import Foundation

protocol HealthDataProviding {
    func requestAuthorization() async throws
    func configureBackgroundDelivery() async throws
    func loadTodaySnapshot() async throws -> HealthSnapshot
    func loadRecoverySnapshot() async throws -> RecoverySnapshot
    func loadRecentWorkouts() async throws -> [WorkoutSummary]
}

protocol WorkoutSessionRecording {
    func start(
        session: PlannedSession,
        route: TrainingRoute?,
        captureDevice: WorkoutCaptureDevice
    ) async throws -> UUID?

    func finish(recordingID: UUID?) async throws -> LinkedHealthWorkoutMetrics
}

protocol WorkoutLaunching {
    func startOnWatch(
        session: PlannedSession,
        route: TrainingRoute?
    ) async throws -> UUID
}

protocol AuthenticationProviding {
    var currentUser: ATHLTHUser? { get async }
    func signInWithApple() async throws -> ATHLTHUser
    func signIn(email: String, password: String) async throws -> ATHLTHUser
    func signOut() async throws
    func isUsernameAvailable(_ username: String) async throws -> Bool
    func claimUsername(_ username: String) async throws
}

protocol SocialProviding {
    func loadProfile(username: String) async throws -> UserProfile
    func setPresence(_ presence: TrainingPresence) async throws
    func follow(userID: UUID) async throws
    func unfollow(userID: UUID) async throws
}

protocol MusicProviding {
    func connect() async throws
    func disconnect() async
    func play(playlistURI: String) async throws
}
