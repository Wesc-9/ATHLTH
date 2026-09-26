import Foundation

enum TrainingPlanTimingStatus: String, CaseIterable, Identifiable {
    case active
    case upcoming
    case completed
    case unscheduled

    var id: String { rawValue }
}

@MainActor
final class AppSessionStore: ObservableObject {
    @Published var profile: UserProfile
    @Published var activePlan: TrainingPlan? {
        didSet {
            persistActivePlan()
        }
    }
    @Published private(set) var scheduledPlans: [TrainingPlan]
    @Published private(set) var planTemplates: [TrainingPlan]
    @Published private(set) var savedWorkoutTemplates: [PlannedSession]
    @Published private(set) var manuallyCompletedPlanSessions: Set<String>
    @Published var savedRoutes: [TrainingRoute] {
        didSet {
            persistSavedRoutes()
        }
    }
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
        profile: UserProfile? = nil,
        activePlan: TrainingPlan? = nil,
        savedRoutes: [TrainingRoute] = [],
        previewModeEnabled: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        let resolvedProfile = profile ?? Self.makeSignedOutProfile()

        self.profile = resolvedProfile
        self.activePlan = activePlan ?? Self.loadActivePlan(from: defaults)
        self.scheduledPlans = Self.loadScheduledPlans(from: defaults)
        self.planTemplates = Self.loadPlanTemplates(from: defaults)
        self.savedWorkoutTemplates = Self.loadSavedWorkoutTemplates(from: defaults)
        self.manuallyCompletedPlanSessions =
            Self.loadManuallyCompletedPlanSessions(from: defaults)
        self.savedRoutes = savedRoutes.isEmpty
            ? Self.loadSavedRoutes(from: defaults)
            : savedRoutes
        self.previewModeEnabled = previewModeEnabled
        self.defaults = defaults
        self.usernameSeed = defaults.string(forKey: "session.usernameSeed") ?? resolvedProfile.displayName

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

        migrateLegacyTrainingPlanIfNeeded()
        refreshActivePlanForToday()
    }

    private static func makeSignedOutProfile() -> UserProfile {
        UserProfile(
            id: UUID(),
            userID: UUID(),
            username: "",
            displayName: "",
            bio: "",
            avatarURL: nil,
            presence: TrainingPresence(
                state: .available,
                workoutTitle: nil,
                startedAt: nil,
                visibility: .friends
            )
        )
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

    func setPendingUsername(_ username: String) {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        profile.username = cleaned
    }

    func applyProfileEdits(
        displayName: String,
        username: String,
        bio: String,
        avatarURL: URL?
    ) {
        profile.displayName = displayName
        profile.username = username
        profile.bio = bio
        profile.avatarURL = avatarURL
        setUsernameSeed(displayName)
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

    func setTrainingFocus(_ focus: TrainingFocus?) {
        if var profile = onboardingProfile {
            profile.trainingFocus = focus
            saveOnboardingProfile(profile)
            return
        }

        saveOnboardingProfile(
            OnboardingProfileData(
                dateOfBirth: nil,
                healthSex: nil,
                weightKilograms: nil,
                heightCentimeters: nil,
                maximumHeartRateBPM: nil,
                personalDetailsSource: .none,
                trainingFocus: focus,
                currentGoal: nil,
                interests: [],
                personalizedOfferConsent: .declined
            )
        )
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
                maximumHeartRateBPM: basics.maximumHeartRateBPM,
                personalDetailsSource: source,
                trainingFocus: existing?.trainingFocus,
                currentGoal: existing?.currentGoal,
                interests: existing?.interests ?? [],
                personalizedOfferConsent: existing?.personalizedOfferConsent ?? .notAsked
            )
        )
    }


    func mergePersonalDetailsFromAppleHealth(
        _ healthBasics: HealthProfileBasics
    ) {
        guard healthBasics.hasAnyValue else { return }

        let existing = onboardingProfile
        let merged = HealthProfileBasics(
            dateOfBirth: healthBasics.dateOfBirth ?? existing?.dateOfBirth,
            healthSex: healthBasics.healthSex ?? existing?.healthSex,
            weightKilograms:
                healthBasics.weightKilograms ?? existing?.weightKilograms,
            heightCentimeters:
                healthBasics.heightCentimeters ?? existing?.heightCentimeters,
            maximumHeartRateBPM:
                existing?.maximumHeartRateBPM ??
                healthBasics.maximumHeartRateBPM
        )

        let usesManualFallback =
            (healthBasics.dateOfBirth == nil && existing?.dateOfBirth != nil) ||
            (healthBasics.healthSex == nil && existing?.healthSex != nil) ||
            (healthBasics.weightKilograms == nil &&
                existing?.weightKilograms != nil) ||
            (healthBasics.heightCentimeters == nil &&
                existing?.heightCentimeters != nil) ||
            existing?.maximumHeartRateBPM != nil

        updatePersonalDetails(
            merged,
            source: usesManualFallback ? .mixed : .appleHealth
        )
    }

    func completeOnboarding() {
        onboardingCompleted = true
        defaults.set(true, forKey: "session.onboardingCompleted")
    }

    func clearAfterAccountDeletion() {
        clearAfterSignOut()
    }

    func clearAfterSignOut() {
        resetAuthenticationState()
        profile = Self.makeSignedOutProfile()
        activePlan = nil
        scheduledPlans = []
        savedRoutes = []
        planTemplates = []
        savedWorkoutTemplates = []
        manuallyCompletedPlanSessions = []
        previewModeEnabled = false
        usernameSeed = profile.displayName
        defaults.removeObject(forKey: "session.activeTrainingPlan")
        defaults.removeObject(forKey: "session.scheduledTrainingPlans")
        defaults.removeObject(forKey: "session.savedRoutes")
        defaults.removeObject(forKey: "session.trainingPlanTemplates")
        defaults.removeObject(forKey: "session.savedWorkoutTemplates")
        defaults.removeObject(forKey: "session.manuallyCompletedPlanSessions")
    }

    func resetAuthenticationState() {
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
        usernameSeed = ""
        accountCreatedAt = Date()
        currentRole = .user
        backendSubscriptionAccess = .free
        storeEntitlement = nil
        subscriptionAccess = .free
    }

    func isPlanSessionManuallyCompleted(
        planID: UUID,
        sessionID: UUID
    ) -> Bool {
        manuallyCompletedPlanSessions.contains(
            Self.manualCompletionKey(
                planID: planID,
                sessionID: sessionID
            )
        )
    }

    func setPlanSessionManuallyCompleted(
        planID: UUID,
        sessionID: UUID,
        completed: Bool
    ) {
        let key = Self.manualCompletionKey(
            planID: planID,
            sessionID: sessionID
        )

        if completed {
            manuallyCompletedPlanSessions.insert(key)
        } else {
            manuallyCompletedPlanSessions.remove(key)
        }

        persistManuallyCompletedPlanSessions()
    }

    func togglePlanSessionManualCompletion(
        planID: UUID,
        sessionID: UUID
    ) {
        let completed = isPlanSessionManuallyCompleted(
            planID: planID,
            sessionID: sessionID
        )

        setPlanSessionManuallyCompleted(
            planID: planID,
            sessionID: sessionID,
            completed: !completed
        )
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

    func applyStrengthProgression(
        from workout: StrengthWorkoutLog
    ) {
        guard workout.trackingMode == .advanced,
              workout.isFinished,
              let plannedSessionID = workout.plannedSessionID,
              var plan = activePlan
        else {
            return
        }

        var changed = false

        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                guard let sessionIndex = plan.weeks[weekIndex]
                    .days[dayIndex]
                    .sessions
                    .firstIndex(where: { $0.id == plannedSessionID })
                else {
                    continue
                }

                for exerciseLog in workout.exercises {
                    guard let plannedExerciseID = exerciseLog.plannedExerciseID,
                          let plannedIndex = plan.weeks[weekIndex]
                            .days[dayIndex]
                            .sessions[sessionIndex]
                            .exercises
                            .firstIndex(where: { $0.id == plannedExerciseID })
                    else {
                        continue
                    }

                    var planned = plan.weeks[weekIndex]
                        .days[dayIndex]
                        .sessions[sessionIndex]
                        .exercises[plannedIndex]

                    guard let progression = planned.progression,
                          progression.kind != .none,
                          progression.applyWhenAllSetsCompleted,
                          qualifiesForAutomaticProgression(
                              planned: planned,
                              completed: exerciseLog
                          )
                    else {
                        continue
                    }

                    switch progression.kind {
                    case .none:
                        break

                    case .addWeight:
                        guard let current = planned.targetWeightKilograms else {
                            continue
                        }
                        planned.targetWeightKilograms =
                            current + max(progression.amount, 0)

                    case .addReps:
                        let increment = max(
                            Int(progression.amount.rounded()),
                            1
                        )
                        planned.reps = max(
                            (planned.reps ?? 0) + increment,
                            1
                        )

                    case .percentage:
                        guard let current = planned.targetWeightKilograms else {
                            continue
                        }
                        planned.targetWeightKilograms =
                            current * (
                                1 + max(progression.amount, 0) / 100
                            )

                    case .doubleProgression:
                        let minimum = max(
                            progression.minimumReps ?? planned.reps ?? 1,
                            1
                        )
                        let maximum = max(
                            progression.maximumReps ?? minimum,
                            minimum
                        )

                        let achievedMaximum =
                            exerciseLog.sets
                            .filter(\.isCompleted)
                            .allSatisfy {
                                ($0.completedReps ?? 0) >= maximum
                            }

                        if achievedMaximum,
                           let currentWeight = planned.targetWeightKilograms {
                            planned.targetWeightKilograms =
                                currentWeight + max(progression.amount, 0)
                            planned.reps = minimum
                        } else {
                            planned.reps = min(
                                max((planned.reps ?? minimum) + 1, minimum),
                                maximum
                            )
                        }
                    }

                    plan.weeks[weekIndex]
                        .days[dayIndex]
                        .sessions[sessionIndex]
                        .exercises[plannedIndex] = planned
                    changed = true
                }
            }
        }

        guard changed else { return }

        plan.version += 1
        plan.updatedAt = Date()
        activePlan = plan
    }

    private func qualifiesForAutomaticProgression(
        planned: PlannedExercise,
        completed: StrengthExerciseLog
    ) -> Bool {
        let completedSets = completed.sets.filter(\.isCompleted)

        guard completedSets.count >= max(planned.sets, 1),
              completedSets.allSatisfy({ $0.completedReps != nil })
        else {
            return false
        }

        if let targetReps = planned.reps {
            guard completedSets.allSatisfy({
                ($0.completedReps ?? 0) >= targetReps
            }) else {
                return false
            }
        }

        if let targetWeight = planned.targetWeightKilograms {
            guard completedSets.allSatisfy({
                guard let completedWeight = $0.completedWeightKilograms else {
                    return false
                }

                return completedWeight + 0.01 >= targetWeight
            }) else {
                return false
            }
        }

        return true
    }

    func addImportedRoute(_ route: TrainingRoute) {
        var ownedRoute = route
        ownedRoute.ownerID = profile.userID
        savedRoutes.insert(ownedRoute, at: 0)
    }

    func updateSavedRoute(
        _ routeID: UUID,
        title: String? = nil,
        visibility: ProfileVisibility? = nil
    ) {
        guard let index = savedRoutes.firstIndex(
            where: { $0.id == routeID }
        ) else {
            return
        }

        if let title {
            let clean = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !clean.isEmpty {
                savedRoutes[index].title = clean
            }
        }

        if let visibility {
            savedRoutes[index].visibility = visibility
        }
    }

    func deleteSavedRoute(_ routeID: UUID) {
        savedRoutes.removeAll { $0.id == routeID }

        if var plan = activePlan {
            var changed = false

            for weekIndex in plan.weeks.indices {
                for dayIndex in plan.weeks[weekIndex].days.indices {
                    for sessionIndex in plan.weeks[weekIndex]
                        .days[dayIndex]
                        .sessions.indices {
                        if plan.weeks[weekIndex]
                            .days[dayIndex]
                            .sessions[sessionIndex]
                            .routeID == routeID {
                            plan.weeks[weekIndex]
                                .days[dayIndex]
                                .sessions[sessionIndex]
                                .routeID = nil
                            changed = true
                        }
                    }
                }
            }

            if changed {
                plan.version += 1
                plan.updatedAt = Date()
                activePlan = plan
            }
        }

        for index in savedWorkoutTemplates.indices {
            if savedWorkoutTemplates[index].routeID == routeID {
                savedWorkoutTemplates[index].routeID = nil
            }
        }

        persistSavedWorkoutTemplates()

        for planIndex in planTemplates.indices {
            for weekIndex in planTemplates[planIndex].weeks.indices {
                for dayIndex in planTemplates[planIndex]
                    .weeks[weekIndex]
                    .days.indices {
                    for sessionIndex in planTemplates[planIndex]
                        .weeks[weekIndex]
                        .days[dayIndex]
                        .sessions.indices {
                        if planTemplates[planIndex]
                            .weeks[weekIndex]
                            .days[dayIndex]
                            .sessions[sessionIndex]
                            .routeID == routeID {
                            planTemplates[planIndex]
                                .weeks[weekIndex]
                                .days[dayIndex]
                                .sessions[sessionIndex]
                                .routeID = nil
                        }
                    }
                }
            }
        }

        persistPlanTemplates()
    }

    var trainingPlans: [TrainingPlan] {
        var plans = scheduledPlans

        if let activePlan {
            plans.removeAll { $0.id == activePlan.id }
            plans.append(activePlan)
        }

        var seen = Set<UUID>()
        return plans
            .filter { seen.insert($0.id).inserted }
            .sorted {
                let lhs = $0.startDate ?? $0.createdAt
                let rhs = $1.startDate ?? $1.createdAt
                return lhs < rhs
            }
    }

    var nextTrainingPlan: TrainingPlan? {
        let today = Calendar.current.startOfDay(for: Date())

        return trainingPlans
            .filter {
                guard let startDate = $0.startDate else {
                    return false
                }

                return Calendar.current.startOfDay(for: startDate) > today
            }
            .min {
                ($0.startDate ?? .distantFuture) <
                ($1.startDate ?? .distantFuture)
            }
    }

    func trainingPlan(
        withID planID: UUID
    ) -> TrainingPlan? {
        if activePlan?.id == planID {
            return activePlan
        }

        return scheduledPlans.first { $0.id == planID }
    }

    func trainingPlanEndDate(
        _ plan: TrainingPlan
    ) -> Date? {
        let calendar = Calendar.current

        if let endDate = plan.endDate {
            return calendar.startOfDay(for: endDate)
        }

        guard let startDate = plan.startDate else {
            return nil
        }

        return calendar.date(
            byAdding: .day,
            value: max(plan.weeks.count * 7 - 1, 0),
            to: calendar.startOfDay(for: startDate)
        )
    }

    func trainingPlanStatus(
        _ plan: TrainingPlan,
        referenceDate: Date = Date()
    ) -> TrainingPlanTimingStatus {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        guard let rawStart = plan.startDate,
              let rawEnd = trainingPlanEndDate(plan)
        else {
            return activePlan?.id == plan.id
                ? .active
                : .unscheduled
        }

        let start = calendar.startOfDay(for: rawStart)
        let end = calendar.startOfDay(for: rawEnd)

        if today < start {
            return .upcoming
        }

        if today > end {
            return .completed
        }

        return .active
    }

    func trainingPlanConflict(
        startDate: Date,
        endDate: Date,
        excludingPlanID: UUID? = nil
    ) -> TrainingPlan? {
        let calendar = Calendar.current
        let candidateStart = calendar.startOfDay(for: startDate)
        let candidateEnd = calendar.startOfDay(for: max(endDate, startDate))

        return trainingPlans.first { plan in
            guard plan.id != excludingPlanID,
                  let rawStart = plan.startDate,
                  let rawEnd = trainingPlanEndDate(plan)
            else {
                return false
            }

            let existingStart = calendar.startOfDay(for: rawStart)
            let existingEnd = calendar.startOfDay(for: rawEnd)

            return candidateStart <= existingEnd &&
                candidateEnd >= existingStart
        }
    }

    func trainingPlanConflict(
        startDate: Date,
        weekCount: Int,
        excludingPlanID: UUID? = nil
    ) -> TrainingPlan? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let weeks = min(max(weekCount, 1), 52)
        let end = calendar.date(
            byAdding: .day,
            value: max(weeks * 7 - 1, 0),
            to: start
        ) ?? start

        return trainingPlanConflict(
            startDate: start,
            endDate: end,
            excludingPlanID: excludingPlanID
        )
    }

    @discardableResult
    func addTrainingPlan(
        _ source: TrainingPlan
    ) -> Bool {
        let plan = normalizedTrainingPlan(source)

        if let startDate = plan.startDate,
           let endDate = trainingPlanEndDate(plan),
           trainingPlanConflict(
               startDate: startDate,
               endDate: endDate,
               excludingPlanID: plan.id
           ) != nil {
            return false
        }

        if trainingPlanStatus(plan) == .active {
            guard activePlan == nil || activePlan?.id == plan.id else {
                return false
            }

            activePlan = plan
            scheduledPlans.removeAll { $0.id == plan.id }
        } else {
            scheduledPlans.removeAll { $0.id == plan.id }
            scheduledPlans.append(plan)
        }

        persistScheduledPlans()
        refreshActivePlanForToday()
        return true
    }

    func refreshActivePlanForToday(
        referenceDate: Date = Date()
    ) {
        var plans = trainingPlans.map(normalizedTrainingPlan)
        let activeCandidates = plans.filter {
            trainingPlanStatusWithoutCurrentPlan(
                $0,
                referenceDate: referenceDate
            ) == .active
        }

        let resolvedActive: TrainingPlan?
        if let currentID = activePlan?.id,
           let current = activeCandidates.first(
               where: { $0.id == currentID }
           ) {
            resolvedActive = current
        } else {
            resolvedActive = activeCandidates.max {
                ($0.startDate ?? .distantPast) <
                ($1.startDate ?? .distantPast)
            }
        }

        if let resolvedActive {
            plans.removeAll { $0.id == resolvedActive.id }
        }

        activePlan = resolvedActive
        scheduledPlans = plans.sorted {
            let lhs = $0.startDate ?? $0.createdAt
            let rhs = $1.startDate ?? $1.createdAt
            return lhs < rhs
        }
        persistScheduledPlans()
    }

    func deleteTrainingPlan(
        _ planID: UUID
    ) {
        if activePlan?.id == planID {
            activePlan = nil
        }

        scheduledPlans.removeAll { $0.id == planID }
        persistScheduledPlans()
        refreshActivePlanForToday()
    }

    @discardableResult
    func duplicateTrainingPlan(
        _ planID: UUID
    ) -> TrainingPlan? {
        guard let source = trainingPlan(withID: planID) else {
            return nil
        }

        let calendar = Calendar.current
        let durationDays = max(source.weeks.count * 7 - 1, 0)
        var proposedStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: trainingPlanEndDate(source) ??
                calendar.startOfDay(for: Date())
        ) ?? calendar.startOfDay(for: Date())
        var proposedEnd = calendar.date(
            byAdding: .day,
            value: durationDays,
            to: proposedStart
        ) ?? proposedStart

        while let conflict = trainingPlanConflict(
            startDate: proposedStart,
            endDate: proposedEnd
        ),
        let conflictEnd = trainingPlanEndDate(conflict) {
            proposedStart = calendar.date(
                byAdding: .day,
                value: 1,
                to: conflictEnd
            ) ?? proposedStart
            proposedEnd = calendar.date(
                byAdding: .day,
                value: durationDays,
                to: proposedStart
            ) ?? proposedStart
        }

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
            spotifyAutoplayOnWorkoutStart:
                source.spotifyAutoplayOnWorkoutStart,
            createdAt: Date(),
            updatedAt: Date(),
            startDate: proposedStart,
            endDate: proposedEnd
        )

        guard addTrainingPlan(duplicate) else {
            return nil
        }

        return duplicate
    }

    @discardableResult
    func setTrainingPlanWeekCount(
        planID: UUID,
        weekCount: Int
    ) -> Bool {
        guard var plan = trainingPlan(withID: planID) else {
            return false
        }

        let resolved = min(max(weekCount, 1), 52)
        let current = plan.weeks.count

        if resolved > current {
            for number in (current + 1)...resolved {
                plan.weeks.append(makeEmptyWeek(number: number))
            }
        } else if resolved < current {
            plan.weeks = Array(plan.weeks.prefix(resolved))
        }

        if let startDate = plan.startDate {
            let endDate = Calendar.current.date(
                byAdding: .day,
                value: max(resolved * 7 - 1, 0),
                to: Calendar.current.startOfDay(for: startDate)
            ) ?? startDate

            if trainingPlanConflict(
                startDate: startDate,
                endDate: endDate,
                excludingPlanID: plan.id
            ) != nil {
                return false
            }

            plan.endDate = endDate
        }

        plan.updatedAt = Date()
        plan.version += 1
        replaceTrainingPlan(plan)
        return true
    }

    @discardableResult
    func updateTrainingPlanMetadata(
        planID: UUID,
        title: String,
        summary: String,
        visibility: ProfileVisibility,
        tags: [String],
        startDate: Date
    ) -> Bool {
        guard var plan = trainingPlan(withID: planID) else {
            return false
        }

        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleanTitle.isEmpty else {
            return false
        }

        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(
            byAdding: .day,
            value: max(plan.weeks.count * 7 - 1, 0),
            to: start
        ) ?? start

        if trainingPlanConflict(
            startDate: start,
            endDate: end,
            excludingPlanID: plan.id
        ) != nil {
            return false
        }

        plan.title = cleanTitle
        plan.summary = summary.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        plan.visibility = visibility
        plan.tags = tags
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()
            }
            .filter { !$0.isEmpty }
        plan.startDate = start
        plan.endDate = end
        plan.updatedAt = Date()
        plan.version += 1

        replaceTrainingPlan(plan)
        return true
    }

    private func replaceTrainingPlan(
        _ source: TrainingPlan
    ) {
        let plan = normalizedTrainingPlan(source)

        if activePlan?.id == plan.id {
            activePlan = plan
        } else if let index = scheduledPlans.firstIndex(
            where: { $0.id == plan.id }
        ) {
            scheduledPlans[index] = plan
        } else {
            scheduledPlans.append(plan)
        }

        persistScheduledPlans()
        refreshActivePlanForToday()
    }

    private func normalizedTrainingPlan(
        _ source: TrainingPlan
    ) -> TrainingPlan {
        var plan = source
        let calendar = Calendar.current

        guard let startDate = plan.startDate else {
            plan.endDate = nil
            return plan
        }

        let start = calendar.startOfDay(for: startDate)
        plan.startDate = start

        if let endDate = plan.endDate {
            plan.endDate = max(
                calendar.startOfDay(for: endDate),
                start
            )
        } else {
            plan.endDate = calendar.date(
                byAdding: .day,
                value: max(plan.weeks.count * 7 - 1, 0),
                to: start
            )
        }

        return plan
    }

    private func trainingPlanStatusWithoutCurrentPlan(
        _ plan: TrainingPlan,
        referenceDate: Date
    ) -> TrainingPlanTimingStatus {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        guard let rawStart = plan.startDate,
              let rawEnd = trainingPlanEndDate(plan)
        else {
            return .unscheduled
        }

        let start = calendar.startOfDay(for: rawStart)
        let end = calendar.startOfDay(for: rawEnd)

        if today < start {
            return .upcoming
        }

        if today > end {
            return .completed
        }

        return .active
    }

    private func migrateLegacyTrainingPlanIfNeeded() {
        guard var plan = activePlan else {
            return
        }

        if plan.startDate == nil {
            plan.startDate = Calendar.current.startOfDay(for: Date())
        }

        plan = normalizedTrainingPlan(plan)
        activePlan = plan
        scheduledPlans.removeAll { $0.id == plan.id }
        persistScheduledPlans()
    }

    func createStarterPlan() {
        createTrainingPlan(
            title: "My Training Plan",
            summary: "Flexible training plan",
            weekCount: 1,
            startDate: Calendar.current.startOfDay(for: Date())
        )
    }

    func createTrainingPlan(
        title: String,
        summary: String,
        weekCount: Int,
        startDate: Date?,
        visibility: ProfileVisibility = .privateOnly
    ) {
        let resolvedWeekCount = min(max(weekCount, 1), 52)

        activePlan = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "My Training Plan"
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            visibility: visibility,
            version: 1,
            weeks: (1...resolvedWeekCount).map(makeEmptyWeek),
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            startDate: startDate
        )
    }

    func createSimpleTrainingPlan(
        title: String,
        summary: String,
        weekCount: Int,
        startDate: Date?,
        visibility: ProfileVisibility = .privateOnly,
        sessionsPerWeek: Int,
        workoutPattern: [WorkoutKind]
    ) {
        let resolvedWeekCount = min(max(weekCount, 1), 52)
        let resolvedSessionsPerWeek = min(max(sessionsPerWeek, 2), 6)
        let pattern = workoutPattern.isEmpty
            ? [WorkoutKind.strength, .running]
            : workoutPattern

        let targetDayIndexes: [Int]
        switch resolvedSessionsPerWeek {
        case 2:
            targetDayIndexes = [1, 4]
        case 3:
            targetDayIndexes = [1, 3, 5]
        case 4:
            targetDayIndexes = [1, 2, 4, 6]
        case 5:
            targetDayIndexes = [1, 2, 3, 5, 6]
        default:
            targetDayIndexes = [1, 2, 3, 4, 5, 6]
        }

        func makeSession(for kind: WorkoutKind) -> PlannedSession {
            let title: String
            let duration: Int
            let distance: Double?

            switch kind {
            case .running:
                title = "Run"
                duration = 40
                distance = 5
            case .walking:
                title = "Walk"
                duration = 45
                distance = 4
            case .strength:
                title = "Strength"
                duration = 50
                distance = nil
            case .mobility:
                title = "Mobility"
                duration = 25
                distance = nil
            case .recovery:
                title = "Recovery"
                duration = 30
                distance = nil
            case .custom:
                title = "Workout"
                duration = 45
                distance = nil
            }

            return PlannedSession(
                id: UUID(),
                title: title,
                kind: kind,
                scheduledStart: nil,
                durationMinutes: duration,
                targetDistanceKilometers: distance,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil,
                exercises: [],
                notes: nil,
                runningWorkout: nil
            )
        }

        var weeks = (1...resolvedWeekCount).map(makeEmptyWeek)

        for weekIndex in weeks.indices {
            for (slot, dayIndex) in targetDayIndexes.enumerated() {
                guard let actualDayIndex = weeks[weekIndex].days.firstIndex(
                    where: { $0.dayIndex == dayIndex }
                ) else {
                    continue
                }

                let patternIndex =
                    (weekIndex * resolvedSessionsPerWeek + slot) %
                    pattern.count

                weeks[weekIndex].days[actualDayIndex].sessions = [
                    makeSession(for: pattern[patternIndex])
                ]
            }
        }

        activePlan = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "My Training Plan"
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            visibility: visibility,
            version: 1,
            weeks: weeks,
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            startDate: startDate
        )
    }

    func replaceActivePlan(with plan: TrainingPlan) {
        activePlan = plan
    }

    func fillEmptyDaysFromGeneratedProgram(
        _ generated: TrainingPlan
    ) {
        guard var current = activePlan else {
            activePlan = generated
            return
        }

        let targetWeekCount = max(generated.weeks.count, 1)

        if current.weeks.count < targetWeekCount {
            for number in (current.weeks.count + 1)...targetWeekCount {
                current.weeks.append(makeEmptyWeek(number: number))
            }
        } else if current.weeks.count > targetWeekCount {
            current.weeks = Array(current.weeks.prefix(targetWeekCount))
        }

        for weekIndex in current.weeks.indices {
            guard generated.weeks.indices.contains(weekIndex) else {
                continue
            }

            let generatedWeek = generated.weeks[weekIndex]

            for dayIndex in current.weeks[weekIndex].days.indices {
                guard generatedWeek.days.indices.contains(dayIndex) else {
                    continue
                }

                if current.weeks[weekIndex].days[dayIndex].sessions.isEmpty {
                    current.weeks[weekIndex].days[dayIndex].sessions =
                        generatedWeek.days[dayIndex].sessions
                }
            }
        }

        current.startDate = generated.startDate ?? current.startDate
        current.updatedAt = Date()
        current.version += 1
        activePlan = current
    }

    func setActivePlanWeekCount(_ weekCount: Int) {
        guard var plan = activePlan else { return }

        let resolved = min(max(weekCount, 1), 52)
        let current = plan.weeks.count

        if resolved > current {
            for number in (current + 1)...resolved {
                plan.weeks.append(makeEmptyWeek(number: number))
            }
        } else if resolved < current {
            plan.weeks = Array(plan.weeks.prefix(resolved))
        }

        plan.updatedAt = Date()
        plan.version += 1
        activePlan = plan
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

    func removeWeekFromActivePlan(_ weekID: UUID) {
        guard var plan = activePlan,
              plan.weeks.count > 1,
              let index = plan.weeks.firstIndex(
                where: { $0.id == weekID }
              )
        else {
            return
        }

        plan.weeks.remove(at: index)

        for weekIndex in plan.weeks.indices {
            plan.weeks[weekIndex].weekNumber = weekIndex + 1
            plan.weeks[weekIndex].title = "Week \(weekIndex + 1)"
        }

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

    func updateSession(
        _ updatedSession: PlannedSession,
        inPlan planID: UUID
    ) {
        guard var plan = activePlan,
              plan.id == planID
        else {
            return
        }

        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                guard let sessionIndex =
                    plan.weeks[weekIndex].days[dayIndex].sessions.firstIndex(
                        where: { $0.id == updatedSession.id }
                    )
                else {
                    continue
                }

                plan.weeks[weekIndex].days[dayIndex].sessions[sessionIndex] =
                    updatedSession
                plan.updatedAt = Date()
                plan.version += 1
                activePlan = plan
                return
            }
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

    func updateActivePlanMetadata(
        title: String,
        summary: String,
        visibility: ProfileVisibility,
        tags: [String],
        startDate: Date?
    ) {
        guard var plan = activePlan else { return }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        plan.title = cleanTitle
        plan.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.visibility = visibility
        plan.tags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        plan.startDate = startDate
        plan.updatedAt = Date()
        plan.version += 1
        activePlan = plan
    }

    func saveActivePlanAsTemplate() {
        guard let source = activePlan else { return }

        let template = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: source.title,
            summary: source.summary,
            visibility: .privateOnly,
            version: 1,
            weeks: source.weeks,
            tags: source.tags,
            spotifyPlaylist: source.spotifyPlaylist,
            spotifyAutoplayOnWorkoutStart: source.spotifyAutoplayOnWorkoutStart,
            createdAt: Date(),
            updatedAt: Date(),
            startDate: nil
        )

        planTemplates.insert(template, at: 0)
        persistPlanTemplates()
    }

    func usePlanTemplate(
        _ templateID: UUID,
        startDate: Date? = nil
    ) {
        guard let template = planTemplates.first(where: { $0.id == templateID }) else {
            return
        }

        let resolvedStartDate = Calendar.current.startOfDay(
            for: startDate ?? Date()
        )

        activePlan = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: template.title,
            summary: template.summary,
            visibility: .privateOnly,
            version: 1,
            weeks: template.weeks,
            tags: template.tags,
            spotifyPlaylist: template.spotifyPlaylist,
            spotifyAutoplayOnWorkoutStart: template.spotifyAutoplayOnWorkoutStart,
            createdAt: Date(),
            updatedAt: Date(),
            startDate: resolvedStartDate
        )
    }

    func deletePlanTemplate(_ templateID: UUID) {
        planTemplates.removeAll { $0.id == templateID }
        persistPlanTemplates()
    }

    func saveSharedPlan(
        _ source: TrainingPlan,
        sourceOwnerID: UUID? = nil,
        sourcePlanID: UUID? = nil,
        sourceVersion: Int? = nil
    ) {
        var copy = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: source.title,
            summary: source.summary,
            visibility: .privateOnly,
            version: 1,
            weeks: source.weeks,
            tags: source.tags,
            spotifyPlaylist: source.spotifyPlaylist,
            spotifyAutoplayOnWorkoutStart: source.spotifyAutoplayOnWorkoutStart,
            createdAt: Date(),
            updatedAt: Date(),
            startDate: nil
        )
        copy.sharedSourceOwnerID =
            source.sharedSourceOwnerID ?? sourceOwnerID ?? source.ownerID
        copy.sharedSourcePlanID =
            source.sharedSourcePlanID ?? sourcePlanID ?? source.id
        copy.sharedSourceVersion =
            source.sharedSourceVersion ?? sourceVersion ?? source.version

        planTemplates.insert(copy, at: 0)
        persistPlanTemplates()
    }

    func saveSharedWorkout(
        _ source: PlannedSession,
        sourceOwnerID: UUID? = nil,
        sourceSessionID: UUID? = nil
    ) {
        var copy = PlannedSession(
            id: UUID(),
            title: source.title,
            kind: source.kind,
            scheduledStart: nil,
            durationMinutes: source.durationMinutes,
            targetDistanceKilometers: source.targetDistanceKilometers,
            targetPaceSecondsPerKilometer: source.targetPaceSecondsPerKilometer,
            routeID: source.routeID,
            exercises: source.exercises,
            notes: source.notes,
            runningWorkout: source.runningWorkout
        )
        copy.sharedSourceOwnerID =
            source.sharedSourceOwnerID ?? sourceOwnerID
        copy.sharedSourceSessionID =
            source.sharedSourceSessionID ?? sourceSessionID ?? source.id

        savedWorkoutTemplates.insert(copy, at: 0)
        persistSavedWorkoutTemplates()
    }

    func deleteSavedWorkoutTemplate(_ workoutID: UUID) {
        savedWorkoutTemplates.removeAll { $0.id == workoutID }
        persistSavedWorkoutTemplates()
    }

    func saveSharedRoute(
        _ source: TrainingRoute,
        sourceOwnerID: UUID? = nil,
        sourceRouteID: UUID? = nil
    ) {
        var copy = TrainingRoute(
            id: UUID(),
            ownerID: profile.userID,
            title: source.title,
            visibility: .privateOnly,
            coordinates: source.coordinates,
            distanceKilometers: source.distanceKilometers,
            elevationGainMeters: source.elevationGainMeters,
            importedFilename: source.importedFilename,
            createdAt: Date(),
            startName: source.startName,
            endName: source.endName,
            expectedTravelTimeSeconds: source.expectedTravelTimeSeconds,
            routeSource: "shared"
        )
        copy.sharedSourceOwnerID =
            source.sharedSourceOwnerID ?? sourceOwnerID ?? source.ownerID
        copy.sharedSourceRouteID =
            source.sharedSourceRouteID ?? sourceRouteID ?? source.id

        savedRoutes.insert(copy, at: 0)
    }

    private func persistActivePlan() {
        guard let activePlan,
              let data = try? JSONEncoder().encode(activePlan)
        else {
            defaults.removeObject(forKey: "session.activeTrainingPlan")
            return
        }

        defaults.set(data, forKey: "session.activeTrainingPlan")
    }

    private func persistSavedRoutes() {
        guard let data = try? JSONEncoder().encode(savedRoutes) else {
            return
        }

        defaults.set(data, forKey: "session.savedRoutes")
    }

    private static func loadSavedRoutes(from defaults: UserDefaults) -> [TrainingRoute] {
        guard let data = defaults.data(forKey: "session.savedRoutes"),
              let routes = try? JSONDecoder().decode([TrainingRoute].self, from: data)
        else {
            return []
        }

        return routes.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistPlanTemplates() {
        guard let data = try? JSONEncoder().encode(planTemplates) else {
            return
        }

        defaults.set(data, forKey: "session.trainingPlanTemplates")
    }

    private func persistManuallyCompletedPlanSessions() {
        let values = Array(manuallyCompletedPlanSessions).sorted()

        guard let data = try? JSONEncoder().encode(values) else {
            return
        }

        defaults.set(
            data,
            forKey: "session.manuallyCompletedPlanSessions"
        )
    }

    private static func loadManuallyCompletedPlanSessions(
        from defaults: UserDefaults
    ) -> Set<String> {
        guard let data = defaults.data(
            forKey: "session.manuallyCompletedPlanSessions"
        ),
        let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Set(values)
    }

    private static func manualCompletionKey(
        planID: UUID,
        sessionID: UUID
    ) -> String {
        "\(planID.uuidString.lowercased())|\(sessionID.uuidString.lowercased())"
    }

    private func persistSavedWorkoutTemplates() {
        guard let data = try? JSONEncoder().encode(savedWorkoutTemplates) else {
            return
        }

        defaults.set(data, forKey: "session.savedWorkoutTemplates")
    }

    private static func loadSavedWorkoutTemplates(
        from defaults: UserDefaults
    ) -> [PlannedSession] {
        guard let data = defaults.data(forKey: "session.savedWorkoutTemplates"),
              let workouts = try? JSONDecoder().decode([PlannedSession].self, from: data)
        else {
            return []
        }

        return workouts
    }

    private static func loadActivePlan(from defaults: UserDefaults) -> TrainingPlan? {
        guard let data = defaults.data(forKey: "session.activeTrainingPlan") else {
            return nil
        }

        return try? JSONDecoder().decode(TrainingPlan.self, from: data)
    }

    private static func loadPlanTemplates(from defaults: UserDefaults) -> [TrainingPlan] {
        guard let data = defaults.data(forKey: "session.trainingPlanTemplates"),
              let plans = try? JSONDecoder().decode([TrainingPlan].self, from: data)
        else {
            return []
        }

        return plans
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
