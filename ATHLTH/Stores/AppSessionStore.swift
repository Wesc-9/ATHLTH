import Foundation

@MainActor
final class AppSessionStore: ObservableObject {
    @Published var profile: UserProfile
    @Published var activePlan: TrainingPlan?
    @Published var savedRoutes: [TrainingRoute]
    @Published var previewModeEnabled: Bool
    @Published var signedIn: Bool
    @Published var onboardingCompleted: Bool
    @Published var signInMethod: SignInMethod?
    @Published var onboardingProfile: OnboardingProfileData?
    @Published var usernameSeed: String
    @Published var accountCreatedAt: Date
    @Published private(set) var currentRole: AccountRole
    @Published private(set) var subscriptionAccess: SubscriptionAccess

    private let defaults: UserDefaults
    private var backendSubscriptionAccess: SubscriptionAccess
    private var storeEntitlement: StoreSubscriptionEntitlement?

    init(
        profile: UserProfile = PreviewData.profile,
        activePlan: TrainingPlan? = PreviewData.trainingPlan,
        savedRoutes: [TrainingRoute] = [],
        previewModeEnabled: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        self.profile = profile
        self.activePlan = activePlan
        self.savedRoutes = savedRoutes
        self.previewModeEnabled = previewModeEnabled
        self.defaults = defaults
        self.usernameSeed = defaults.string(forKey: "session.usernameSeed") ?? profile.displayName

        if let storedRole = defaults.string(forKey: "session.accountRole"),
           let role = AccountRole(rawValue: storedRole) {
            self.currentRole = role
        } else {
            self.currentRole = .user
        }

        let storedSubscriptionAccess: SubscriptionAccess
        if let subscriptionData = defaults.data(forKey: "session.subscriptionAccess"),
           let subscription = try? JSONDecoder().decode(SubscriptionAccess.self, from: subscriptionData) {
            storedSubscriptionAccess = subscription
        } else {
            storedSubscriptionAccess = .free
        }

        if storedSubscriptionAccess.state == .trial ||
            storedSubscriptionAccess.state == .expired ||
            storedSubscriptionAccess.state == .revoked ||
            storedSubscriptionAccess.source == .serverVerified {
            self.backendSubscriptionAccess = storedSubscriptionAccess
            self.subscriptionAccess = storedSubscriptionAccess
        } else {
            self.backendSubscriptionAccess = .free
            self.subscriptionAccess = .free
        }
        self.storeEntitlement = nil

        if let storedDate = defaults.object(forKey: "session.accountCreatedAt") as? Date {
            self.accountCreatedAt = storedDate
        } else {
            let createdAt = Date()
            self.accountCreatedAt = createdAt
            defaults.set(createdAt, forKey: "session.accountCreatedAt")
        }
        self.signedIn = defaults.bool(forKey: "session.signedIn")
        self.onboardingCompleted = defaults.bool(forKey: "session.onboardingCompleted")
        self.signInMethod = defaults.string(forKey: "session.signInMethod").flatMap(SignInMethod.init(rawValue:))

        if let data = defaults.data(forKey: "session.onboardingProfile") {
            self.onboardingProfile = try? JSONDecoder().decode(OnboardingProfileData.self, from: data)
        } else {
            self.onboardingProfile = nil
        }
    }

    var hasPaidAccess: Bool {
        subscriptionAccess.hasPaidAccess
    }

    var effectiveSubscriptionTier: SubscriptionTier {
        subscriptionAccess.effectiveTier
    }

    func canAccess(_ feature: ATHLTHFeature) -> Bool {
        !feature.requiresATHLTHPlus || hasPaidAccess
    }

    func applyBackendBootstrap(
        _ bootstrap: BackendUserBootstrap,
        method: SignInMethod? = nil
    ) {
        signedIn = true
        defaults.set(true, forKey: "session.signedIn")

        if let method {
            signInMethod = method
            defaults.set(method.rawValue, forKey: "session.signInMethod")
        }

        profile.userID = bootstrap.profile.id
        profile.username = bootstrap.profile.username ?? ""
        profile.displayName = bootstrap.profile.displayName ?? profile.displayName
        profile.bio = bootstrap.profile.bio ?? ""
        profile.avatarURL = bootstrap.profile.avatarURL.flatMap(URL.init(string:))

        accountCreatedAt = bootstrap.profile.createdAt
        defaults.set(accountCreatedAt, forKey: "session.accountCreatedAt")

        currentRole = AccountRole(rawValue: bootstrap.role.role) ?? .user
        defaults.set(currentRole.rawValue, forKey: "session.accountRole")

        switch bootstrap.entitlement.status {
        case "trialing":
            backendSubscriptionAccess = SubscriptionAccess(
                state: .trial,
                trialStartedAt: bootstrap.entitlement.trialStartedAt,
                trialEndsAt: bootstrap.entitlement.trialEndsAt,
                source: .athlthTrial
            )

        case "active":
            backendSubscriptionAccess = SubscriptionAccess(
                state: .paid,
                source: .serverVerified,
                productID: bootstrap.entitlement.appStoreProductID,
                currentPeriodEndsAt: bootstrap.entitlement.currentPeriodEndsAt
            )

        case "expired":
            backendSubscriptionAccess = SubscriptionAccess(
                state: .expired,
                trialStartedAt: bootstrap.entitlement.trialStartedAt,
                trialEndsAt: bootstrap.entitlement.trialEndsAt,
                source: bootstrap.entitlement.source == "athlth_trial"
                    ? .athlthTrial
                    : .serverVerified,
                productID: bootstrap.entitlement.appStoreProductID,
                currentPeriodEndsAt: bootstrap.entitlement.currentPeriodEndsAt
            )

        case "revoked":
            backendSubscriptionAccess = SubscriptionAccess(
                state: .revoked,
                source: .serverVerified,
                productID: bootstrap.entitlement.appStoreProductID,
                currentPeriodEndsAt: bootstrap.entitlement.currentPeriodEndsAt
            )

        case "free":
            backendSubscriptionAccess = .free

        default:
            backendSubscriptionAccess = .free
        }
        recomputeSubscriptionAccess()

        onboardingCompleted = bootstrap.profile.onboardingCompleted
        defaults.set(onboardingCompleted, forKey: "session.onboardingCompleted")

        let seed = bootstrap.profile.displayName
            ?? bootstrap.profile.username
            ?? "athlete"
        setUsernameSeed(seed)
    }

    func startNewUserPaidTrialIfNeeded() {
        guard backendSubscriptionAccess.lifecycleState == .free else { return }

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 60 * 60)

        backendSubscriptionAccess = SubscriptionAccess(
            state: .trial,
            trialStartedAt: start,
            trialEndsAt: end,
            source: .athlthTrial
        )
        recomputeSubscriptionAccess()
    }

    func applyStoreKitEntitlement(_ entitlement: StoreSubscriptionEntitlement?) {
        storeEntitlement = entitlement
        recomputeSubscriptionAccess()
    }

    private func recomputeSubscriptionAccess() {
        if backendSubscriptionAccess.lifecycleState == .revoked {
            subscriptionAccess = backendSubscriptionAccess
        } else if signedIn,
                  let entitlement = storeEntitlement,
                  entitlement.appAccountToken == profile.userID {
            subscriptionAccess = SubscriptionAccess(
                state: .paid,
                source: .appStore,
                productID: entitlement.productID,
                currentPeriodEndsAt: entitlement.expirationDate
            )
        } else if backendSubscriptionAccess.lifecycleState != .free {
            subscriptionAccess = backendSubscriptionAccess
        } else {
            subscriptionAccess = .free
        }

        persistSubscriptionAccess()
    }

    private func persistSubscriptionAccess() {
        if let data = try? JSONEncoder().encode(subscriptionAccess) {
            defaults.set(data, forKey: "session.subscriptionAccess")
        }
    }

    func applyAuthenticatedRole(_ role: AccountRole) {
        currentRole = role
        defaults.set(role.rawValue, forKey: "session.accountRole")
    }

    func resetRoleToUser() {
        currentRole = .user
        defaults.set(AccountRole.user.rawValue, forKey: "session.accountRole")
    }

    func setUsernameSeed(_ value: String) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        usernameSeed = clean
        defaults.set(clean, forKey: "session.usernameSeed")
    }

    func beginMockSignIn(method: SignInMethod, isNewUser: Bool = false) {
        signedIn = true
        signInMethod = method
        defaults.set(true, forKey: "session.signedIn")
        defaults.set(method.rawValue, forKey: "session.signInMethod")

        if isNewUser {
            startNewUserPaidTrialIfNeeded()
        }
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

    func setPersonalizedOfferConsent(_ consent: PersonalizedOfferConsent) {
        guard var profile = onboardingProfile else { return }
        profile.personalizedOfferConsent = consent
        saveOnboardingProfile(profile)
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
                currentGoal: existing?.currentGoal,
                interests: existing?.interests ?? [],
                personalizedOfferConsent: existing?.personalizedOfferConsent ?? .notAsked
            )
        )
    }

    func completeOnboarding() {
        onboardingCompleted = true
        defaults.set(true, forKey: "session.onboardingCompleted")
    }

    func clearAfterAccountDeletion() {
        resetOnboardingForPreview()
        profile = PreviewData.profile
        activePlan = nil
        savedRoutes = []
        previewModeEnabled = false
        usernameSeed = profile.displayName
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
        defaults.removeObject(forKey: "session.usernameSeed")
        defaults.removeObject(forKey: "session.accountCreatedAt")
        defaults.removeObject(forKey: "session.accountRole")
        defaults.removeObject(forKey: "session.subscriptionAccess")
        usernameSeed = profile.displayName
        accountCreatedAt = Date()
        currentRole = .user
        backendSubscriptionAccess = .free
        storeEntitlement = nil
        subscriptionAccess = .free
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
