import Foundation

@MainActor
final class AppSessionStore: ObservableObject {
    @Published var profile: UserProfile
    @Published var activePlan: TrainingPlan?
    @Published var savedRoutes: [TrainingRoute]
    @Published var challenges: [RouteChallenge]
    @Published var previewModeEnabled: Bool
    @Published var signedIn: Bool
    @Published var onboardingCompleted: Bool
    @Published var signInMethod: SignInMethod?
    @Published var onboardingProfile: OnboardingProfileData?

    private let defaults: UserDefaults

    init(
        profile: UserProfile = PreviewData.profile,
        activePlan: TrainingPlan? = PreviewData.trainingPlan,
        savedRoutes: [TrainingRoute] = [PreviewData.route],
        challenges: [RouteChallenge] = [PreviewData.challenge],
        previewModeEnabled: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        self.profile = profile
        self.activePlan = activePlan
        self.savedRoutes = savedRoutes
        self.challenges = challenges
        self.previewModeEnabled = previewModeEnabled
        self.defaults = defaults
        self.signedIn = defaults.bool(forKey: "session.signedIn")
        self.onboardingCompleted = defaults.bool(forKey: "session.onboardingCompleted")
        self.signInMethod = defaults.string(forKey: "session.signInMethod").flatMap(SignInMethod.init(rawValue:))

        if let data = defaults.data(forKey: "session.onboardingProfile") {
            self.onboardingProfile = try? JSONDecoder().decode(OnboardingProfileData.self, from: data)
        } else {
            self.onboardingProfile = nil
        }
    }

    func beginMockSignIn(method: SignInMethod) {
        signedIn = true
        signInMethod = method
        defaults.set(true, forKey: "session.signedIn")
        defaults.set(method.rawValue, forKey: "session.signInMethod")
    }

    func setPendingUsername(_ username: String) {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        profile.username = cleaned
    }

    func saveOnboardingProfile(_ data: OnboardingProfileData) {
        onboardingProfile = data

        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: "session.onboardingProfile")
        }
    }

    func updatePersonalDetails(
        _ basics: HealthProfileBasics,
        source: PersonalDetailsSource
    ) {
        let existing = onboardingProfile

        saveOnboardingProfile(
            OnboardingProfileData(
                dateOfBirth: basics.dateOfBirth,
                healthSex: basics.healthSex,
                weightKilograms: basics.weightKilograms,
                heightCentimeters: basics.heightCentimeters,
                personalDetailsSource: source,
                goals: existing?.goals ?? [],
                primaryGoal: existing?.primaryGoal
            )
        )
    }

    func completeOnboarding() {
        onboardingCompleted = true
        defaults.set(true, forKey: "session.onboardingCompleted")
    }

    func resetOnboardingForPreview() {
        signedIn = false
        onboardingCompleted = false
        signInMethod = nil
        onboardingProfile = nil
        defaults.removeObject(forKey: "session.signedIn")
        defaults.removeObject(forKey: "session.onboardingCompleted")
        defaults.removeObject(forKey: "session.signInMethod")
        defaults.removeObject(forKey: "session.onboardingProfile")
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

    func addImportedRoute(_ route: TrainingRoute) {
        var ownedRoute = route
        ownedRoute.ownerID = profile.userID
        savedRoutes.insert(ownedRoute, at: 0)
    }

    func createStarterPlan() {
        activePlan = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: "My Training Plan",
            summary: "Flexible training plan",
            visibility: .privateOnly,
            version: 1,
            weeks: [makeEmptyWeek(number: 1)],
            tags: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func addWeekToActivePlan() {
        guard var plan = activePlan else {
            createStarterPlan()
            return
        }

        let number = (plan.weeks.map(\.weekNumber).max() ?? 0) + 1
        plan.weeks.append(makeEmptyWeek(number: number))
        plan.updatedAt = Date()
        plan.version += 1
        activePlan = plan
    }

    func addSession(_ session: PlannedSession, toDay dayID: UUID) {
        guard var plan = activePlan else { return }

        for weekIndex in plan.weeks.indices {
            guard let dayIndex = plan.weeks[weekIndex].days.firstIndex(where: { $0.id == dayID }) else {
                continue
            }

            plan.weeks[weekIndex].days[dayIndex].sessions.append(session)
            plan.updatedAt = Date()
            plan.version += 1
            activePlan = plan
            return
        }
    }

    func removeSession(_ sessionID: UUID, fromDay dayID: UUID) {
        guard var plan = activePlan else { return }

        for weekIndex in plan.weeks.indices {
            guard let dayIndex = plan.weeks[weekIndex].days.firstIndex(where: { $0.id == dayID }) else {
                continue
            }

            plan.weeks[weekIndex].days[dayIndex].sessions.removeAll { $0.id == sessionID }
            plan.updatedAt = Date()
            plan.version += 1
            activePlan = plan
            return
        }
    }

    func duplicateActivePlan() {
        guard let source = activePlan else { return }

        let duplicate = TrainingPlan(
            id: UUID(),
            ownerID: source.ownerID,
            title: "\(source.title) Copy",
            summary: source.summary,
            visibility: .privateOnly,
            version: 1,
            weeks: source.weeks,
            tags: source.tags,
            spotifyPlaylist: source.spotifyPlaylist,
            spotifyAutoplayOnWorkoutStart: source.spotifyAutoplayOnWorkoutStart,
            createdAt: Date(),
            updatedAt: Date()
        )
        activePlan = duplicate
    }

    func setActivePlanSpotifyPlaylist(_ playlist: SpotifyPlaylistReference?) {
        guard var plan = activePlan else { return }
        plan.spotifyPlaylist = playlist
        plan.updatedAt = Date()
        plan.version += 1
        activePlan = plan
    }

    func setActivePlanSpotifyAutoplay(_ enabled: Bool) {
        guard var plan = activePlan else { return }
        plan.spotifyAutoplayOnWorkoutStart = enabled
        plan.updatedAt = Date()
        plan.version += 1
        activePlan = plan
    }

    func setPlanVisibility(_ visibility: ProfileVisibility) {
        guard var plan = activePlan else { return }
        plan.visibility = visibility
        plan.updatedAt = Date()
        plan.version += 1
        activePlan = plan
    }

    private func makeEmptyWeek(number: Int) -> TrainingPlanWeek {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

        return TrainingPlanWeek(
            id: UUID(),
            weekNumber: number,
            title: "Week \(number)",
            days: dayNames.enumerated().map { index, title in
                TrainingPlanDay(
                    id: UUID(),
                    dayIndex: index + 1,
                    title: title,
                    sessions: []
                )
            }
        )
    }
}
