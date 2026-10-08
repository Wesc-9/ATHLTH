import Foundation

enum TrainingPlanTimingStatus: String, CaseIterable, Identifiable {
    case active
    case upcoming
    case completed
    case unscheduled

    var id: String { rawValue }
}

struct TrainingPlanSessionOccurrence: Identifiable {
    let planID: UUID
    let session: PlannedSession
    let date: Date
    let weekNumber: Int

    var id: String {
        "\(planID.uuidString)|\(session.id.uuidString)"
    }
}

struct TrainingPlanProgressSnapshot {
    let totalSessions: Int
    let completedSessions: Int
    let skippedSessions: Int
    let currentWeek: Int
    let totalWeeks: Int
    let missed: [TrainingPlanSessionOccurrence]

    var completionFraction: Double {
        guard totalSessions > 0 else { return 0 }
        return min(
            max(
                Double(completedSessions) /
                Double(totalSessions),
                0
            ),
            1
        )
    }
}


struct AccountTrainingContent: Codable {
    var activePlan: TrainingPlan?
    var scheduledPlans: [TrainingPlan]
    var planTemplates: [TrainingPlan]
    var savedWorkoutTemplates: [PlannedSession]
    var standalonePlannedSessions: [PlannedSession]? = nil
    var manuallyCompletedPlanSessions: Set<String>
    var skippedPlanSessions: Set<String>? = nil
    var savedRoutes: [TrainingRoute]
    var onboardingProfile: OnboardingProfileData?
    var pendingCoachPlanProposal: CoachPlanChangeProposal? = nil
    var coachPlanAdaptationHistory: [CoachPlanAdaptationRecord]? = nil
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
    @Published private(set) var standalonePlannedSessions: [PlannedSession]
    @Published private(set) var manuallyCompletedPlanSessions: Set<String>
    @Published private(set) var skippedPlanSessions: Set<String>
    @Published private(set) var pendingCoachPlanProposal: CoachPlanChangeProposal?
    @Published private(set) var coachPlanAdaptationHistory: [CoachPlanAdaptationRecord]
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
    @Published private(set) var aiHealthDataSharingEnabled: Bool

    private let defaults: UserDefaults
    private var localAccountID: UUID?
    private var loadingAccountContent = false
    private var accountContentSaveTask: Task<Void, Never>?
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
        self.activePlan = activePlan
        self.scheduledPlans = []
        self.planTemplates = []
        self.savedWorkoutTemplates = []
        self.standalonePlannedSessions = []
        self.manuallyCompletedPlanSessions = []
        self.skippedPlanSessions = []
        self.pendingCoachPlanProposal = nil
        self.coachPlanAdaptationHistory = []
        self.savedRoutes = savedRoutes

        // Internal simulator-only compatibility mode. Production launches do
        // not include this argument, so normal authentication remains
        // unchanged. CI uses it to render signed-out product surfaces across
        // the supported iPhone size classes without needing test credentials.
        let compatibilityPreview =
            ProcessInfo.processInfo.arguments
                .contains(
                    "--athlth-compatibility-preview"
                )
        self.previewModeEnabled =
            previewModeEnabled ||
            compatibilityPreview

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

        self.onboardingProfile = nil
        self.aiHealthDataSharingEnabled = false

        if self.signedIn && self.currentRole == .owner {
            self.subscriptionAccess = SubscriptionAccess(
                state: .paid,
                source: .ownerOverride
            )
        }

        // Legacy data stays untouched until its owner is authenticated.
        if defaults.data(forKey: "legacy.onboardingProfile") == nil,
           let legacy = defaults.data(forKey: "session.onboardingProfile") {
            defaults.set(legacy, forKey: "legacy.onboardingProfile")
        }
        if defaults.string(forKey: "legacy.trainingOwner") == nil {
            var owners = Set(Self.loadScheduledPlans(from: defaults).map(\.ownerID))
            owners.formUnion(Self.loadPlanTemplates(from: defaults).map(\.ownerID))
            owners.formUnion(Self.loadSavedRoutes(from: defaults).map(\.ownerID))
            if let plan = Self.loadActivePlan(from: defaults) { owners.insert(plan.ownerID) }
            if owners.count == 1, let owner = owners.first {
                defaults.set(owner.uuidString, forKey: "legacy.trainingOwner")
            }
        }

    }

    private static func makeSignedOutProfile() -> UserProfile {
        UserProfile(
            id: UUID(),
            userID: UUID(),
            username: "",
            displayName: "",
            bio: "",
            avatarURL: nil,
            headerArtworkName: nil,
            headerImageURL: nil,
            headerDimStrength: 0,
            presence: TrainingPresence(
                state: .available,
                workoutTitle: nil,
                startedAt: nil,
                visibility: .friends
            )
        )
    }

    private var hasPermanentOwnerAccess: Bool {
        signedIn && currentRole == .owner
    }

    var hasPaidAccess: Bool {
        hasPermanentOwnerAccess || subscriptionAccess.hasPaidAccess
    }

    var effectiveSubscriptionTier: SubscriptionTier {
        hasPaidAccess ? .paid : .free
    }

    func canAccess(_ feature: ATHLTHFeature) -> Bool {
        !feature.requiresATHLTHPlus || hasPaidAccess
    }

    func applyBackendBootstrap(
        _ bootstrap: BackendUserBootstrap,
        method: SignInMethod? = nil
    ) {
        activateLocalAccount(bootstrap.profile.id)
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
        profile.headerArtworkName =
            bootstrap.profile.headerArtworkName
        profile.headerImageURL =
            bootstrap.profile.headerImageURL.flatMap(URL.init(string:))
        profile.headerDimStrength =
            min(
                max(
                    bootstrap.profile.headerDimStrength ?? 0,
                    0
                ),
                0.45
            )

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
        if hasPermanentOwnerAccess {
            // The product owner must never lose ATHLTH+ because a StoreKit
            // receipt, TestFlight environment, or subscription row changes.
            // The owner role is server-controlled and is therefore safe to
            // use as the permanent first-priority entitlement.
            subscriptionAccess = SubscriptionAccess(
                state: .paid,
                source: .ownerOverride
            )
        } else if backendSubscriptionAccess.lifecycleState == .revoked {
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
        recomputeSubscriptionAccess()
    }

    func resetRoleToUser() {
        currentRole = .user
        defaults.set(AccountRole.user.rawValue, forKey: "session.accountRole")
        recomputeSubscriptionAccess()
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

        persistAccountContent()
    }

    func setAIHealthDataSharingEnabled(
        _ enabled: Bool
    ) {
        guard signedIn else {
            aiHealthDataSharingEnabled = false
            return
        }

        let userID = profile.userID
        aiHealthDataSharingEnabled = enabled
        AccountLocalStorage.write(
            enabled,
            name: "aiHealthDataConsent",
            userID: userID,
            defaults: defaults
        )
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
        let deletedID = localAccountID
        if let deletedID { defaults.set(true, forKey: AccountLocalStorage.key("deleted", userID: deletedID)) }
        clearAfterSignOut()
        if let deletedID {
            defaults.removeObject(forKey: AccountLocalStorage.key("training", userID: deletedID))
            defaults.removeObject(forKey: AccountLocalStorage.key("coach", userID: deletedID))
            for name in ["goals", "strengthHistory", "strengthActive", "phoneHistory", "phoneActive", "coachHistoryConsent", "aiHealthDataConsent", "cloudBackupConsent", "cloudBackupConsentChangedAt"] {
                defaults.removeObject(forKey: AccountLocalStorage.key(name, userID: deletedID))
            }
            AccountLocalStorage.write([RunningWorkoutTemplate](), name: "runningLibrary", userID: deletedID, defaults: defaults)
            AccountLocalStorage.write([Exercise](), name: "exerciseLibrary", userID: deletedID, defaults: defaults)
            defaults.set(true, forKey: AccountLocalStorage.key("legacyMigrated", userID: deletedID))
        }
    }

    func clearAfterSignOut() {
        ATHLTHSurfaceCoordinator.clearAccountSurfaces()
        ATHLTHArtworkImage.clearRemoteCache()
        resetAuthenticationState()
        profile = Self.makeSignedOutProfile()
        previewModeEnabled = false
        usernameSeed = profile.displayName
    }

    func resetAuthenticationState() {
        persistAccountContent(immediate: true)
        localAccountID = nil
        loadingAccountContent = true
        activePlan = nil
        scheduledPlans = []
        savedRoutes = []
        planTemplates = []
        savedWorkoutTemplates = []
        standalonePlannedSessions = []
        manuallyCompletedPlanSessions = []
        skippedPlanSessions = []
        pendingCoachPlanProposal = nil
        coachPlanAdaptationHistory = []
        loadingAccountContent = false
        signedIn = false
        onboardingCompleted = false
        signInMethod = nil
        onboardingProfile = nil
        aiHealthDataSharingEnabled = false
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
            skippedPlanSessions.remove(key)
        } else {
            manuallyCompletedPlanSessions.remove(key)
        }

        persistManuallyCompletedPlanSessions()
    }

    func isPlanSessionSkipped(
        planID: UUID,
        sessionID: UUID
    ) -> Bool {
        skippedPlanSessions.contains(
            Self.manualCompletionKey(
                planID: planID,
                sessionID: sessionID
            )
        )
    }

    func setPlanSessionSkipped(
        planID: UUID,
        sessionID: UUID,
        skipped: Bool
    ) {
        let key = Self.manualCompletionKey(
            planID: planID,
            sessionID: sessionID
        )

        if skipped {
            skippedPlanSessions.insert(key)
            manuallyCompletedPlanSessions.remove(key)
        } else {
            skippedPlanSessions.remove(key)
        }

        persistAccountContent()
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
                                set in

                                if let targetWeight =
                                        planned
                                            .targetWeightKilograms {
                                    return set.completedReps(
                                        atOrAboveWeightKilograms:
                                            targetWeight
                                    ) >= maximum
                                }

                                return
                                    (set.resolvedCompletedReps ?? 0) >=
                                    maximum
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
        // Time- and resistance-based machine work is deliberately excluded
        // from the existing kg/repetition progression engine.
        guard planned.resolvedTargetKind == .reps,
              planned.resolvedLoadKind ==
                .weightKilograms
        else {
            return false
        }

        let completedSets =
            completed.sets.filter(\.isCompleted)

        guard completedSets.count >=
                max(planned.sets, 1)
        else {
            return false
        }

        if let targetWeight =
                planned.targetWeightKilograms,
           let targetReps =
                planned.reps {
            // A split set only qualifies if the planned number of reps was
            // actually completed at or above the planned load. For example,
            // 8 x 10 kg + 2 x 8 kg does not count as 10 x 10 kg.
            return completedSets.allSatisfy {
                $0.completedReps(
                    atOrAboveWeightKilograms:
                        targetWeight
                ) >= targetReps
            }
        }

        if let targetReps = planned.reps {
            guard completedSets.allSatisfy({
                ($0.resolvedCompletedReps ?? 0) >=
                    targetReps
            }) else {
                return false
            }
        }

        if let targetWeight =
                planned.targetWeightKilograms {
            guard completedSets.allSatisfy({
                $0.completedReps(
                    atOrAboveWeightKilograms:
                        targetWeight
                ) > 0
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

        for planIndex in scheduledPlans.indices {
            var changed = false

            for weekIndex in scheduledPlans[planIndex].weeks.indices {
                for dayIndex in scheduledPlans[planIndex]
                    .weeks[weekIndex]
                    .days.indices {
                    for sessionIndex in scheduledPlans[planIndex]
                        .weeks[weekIndex]
                        .days[dayIndex]
                        .sessions.indices {
                        if scheduledPlans[planIndex]
                            .weeks[weekIndex]
                            .days[dayIndex]
                            .sessions[sessionIndex]
                            .routeID == routeID {
                            scheduledPlans[planIndex]
                                .weeks[weekIndex]
                                .days[dayIndex]
                                .sessions[sessionIndex]
                                .routeID = nil
                            changed = true
                        }
                    }
                }
            }

            if changed {
                scheduledPlans[planIndex].version += 1
                scheduledPlans[planIndex].updatedAt = Date()
            }
        }

        persistScheduledPlans()

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

    var suggestedTrainingPlanStartDate: Date {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: Date())

        let datedPlans = trainingPlans
            .compactMap { plan -> (Date, Date)? in
                guard let startDate = plan.startDate,
                      let endDate = trainingPlanEndDate(plan)
                else {
                    return nil
                }

                return (
                    calendar.startOfDay(for: startDate),
                    calendar.startOfDay(for: endDate)
                )
            }
            .sorted { $0.0 < $1.0 }

        for (start, end) in datedPlans {
            if end < cursor {
                continue
            }

            if start > cursor {
                break
            }

            cursor = calendar.date(
                byAdding: .day,
                value: 1,
                to: end
            ) ?? cursor
        }

        return cursor
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

    func trainingPlan(
        containingSessionID sessionID: UUID
    ) -> TrainingPlan? {
        trainingPlans.first { plan in
            plan.weeks.contains { week in
                week.days.contains { day in
                    day.sessions.contains { $0.id == sessionID }
                }
            }
        }
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

    func trainingPlanProgress(
        _ plan: TrainingPlan,
        healthWorkouts: [WorkoutSummary],
        strengthHistory: [StrengthWorkoutLog],
        referenceDate: Date = Date()
    ) -> TrainingPlanProgressSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let start = plan.startDate.map {
            calendar.startOfDay(for: $0)
        }

        var occurrences: [TrainingPlanSessionOccurrence] = []

        for (weekIndex, week) in plan.weeks.enumerated() {
            for day in week.days {
                for plannedSession in day.sessions {
                    let fallbackDate: Date
                    if let start {
                        fallbackDate =
                            calendar.date(
                                byAdding: .day,
                                value:
                                    weekIndex * 7 +
                                    max(day.dayIndex - 1, 0),
                                to: start
                            ) ?? start
                    } else {
                        fallbackDate = plannedSession.scheduledStart
                            ?? plan.createdAt
                    }

                    occurrences.append(
                        TrainingPlanSessionOccurrence(
                            planID: plan.id,
                            session: plannedSession,
                            date:
                                plannedSession.scheduledStart
                                    .map {
                                        calendar.startOfDay(for: $0)
                                    }
                                    ?? fallbackDate,
                            weekNumber: weekIndex + 1
                        )
                    )
                }
            }
        }

        var unusedHealth = healthWorkouts.sorted {
            $0.startDate < $1.startDate
        }
        var completedIDs = Set<UUID>()
        var skippedIDs = Set<UUID>()

        for occurrence in occurrences {
            let planned = occurrence.session

            if isPlanSessionSkipped(
                planID: plan.id,
                sessionID: planned.id
            ) {
                skippedIDs.insert(planned.id)
                continue
            }

            if isPlanSessionManuallyCompleted(
                planID: plan.id,
                sessionID: planned.id
            ) {
                completedIDs.insert(planned.id)
                continue
            }

            if strengthHistory.contains(
                where: {
                    $0.isFinished &&
                    $0.plannedSessionID == planned.id
                }
            ) {
                completedIDs.insert(planned.id)
                continue
            }

            if let matchIndex = unusedHealth.firstIndex(
                where: { workout in
                    calendar.isDate(
                        workout.startDate,
                        inSameDayAs: occurrence.date
                    ) &&
                    Self.healthWorkout(
                        workout,
                        matches: planned
                    )
                }
            ) {
                completedIDs.insert(planned.id)
                unusedHealth.remove(at: matchIndex)
            }
        }

        let missed = occurrences
            .filter {
                calendar.startOfDay(for: $0.date) < today &&
                !completedIDs.contains($0.session.id) &&
                !skippedIDs.contains($0.session.id)
            }
            .sorted { $0.date < $1.date }

        let currentWeek: Int
        if let start {
            let dayOffset =
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: today
                ).day ?? 0

            if dayOffset < 0 {
                currentWeek = 0
            } else {
                currentWeek = min(
                    max(dayOffset / 7 + 1, 1),
                    max(plan.weeks.count, 1)
                )
            }
        } else {
            currentWeek = 0
        }

        return TrainingPlanProgressSnapshot(
            totalSessions: occurrences.count,
            completedSessions: completedIDs.count,
            skippedSessions: skippedIDs.count,
            currentWeek: currentWeek,
            totalWeeks: plan.weeks.count,
            missed: missed
        )
    }

    private static func healthWorkout(
        _ workout: WorkoutSummary,
        matches session: PlannedSession
    ) -> Bool {
        switch session.kind {
        case .running:
            return workout.activity == .running
        case .walking:
            return workout.activity == .walking ||
                workout.activity == .hiking
        case .strength:
            return workout.activity == .strength
        case .mobility:
            return workout.activity == .yoga ||
                workout.activity == .coreTraining
        case .recovery:
            return false
        case .custom:
            return workout.activity == .hiit ||
                workout.activity == .rowing ||
                workout.activity == .cycling ||
                workout.activity == .stairClimbing ||
                workout.activity == .other
        }
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

        let prefix =
            planID.uuidString.lowercased() + "|"
        manuallyCompletedPlanSessions =
            Set(
                manuallyCompletedPlanSessions.filter {
                    !$0.hasPrefix(prefix)
                }
            )
        skippedPlanSessions =
            Set(
                skippedPlanSessions.filter {
                    !$0.hasPrefix(prefix)
                }
            )

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
    func movePlanSession(
        planID: UUID,
        sessionID: UUID,
        to targetDate: Date
    ) -> Bool {
        guard var plan = trainingPlan(withID: planID),
              let startDate = plan.startDate
        else {
            return false
        }

        var movedSession: PlannedSession?
        var sourceWeekIndex: Int?
        var sourceDayIndex: Int?

        outerLoop:
        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                if let sessionIndex =
                    plan.weeks[weekIndex]
                        .days[dayIndex]
                        .sessions
                        .firstIndex(
                            where: { $0.id == sessionID }
                        ) {
                    movedSession =
                        plan.weeks[weekIndex]
                            .days[dayIndex]
                            .sessions[sessionIndex]
                    sourceWeekIndex = weekIndex
                    sourceDayIndex = dayIndex
                    break outerLoop
                }
            }
        }

        guard var movedSession,
              let sourceWeekIndex,
              let sourceDayIndex
        else {
            return false
        }

        let calendar = Calendar.current
        let start =
            calendar.startOfDay(for: startDate)
        let target =
            calendar.startOfDay(for: targetDate)
        let dayOffset =
            calendar.dateComponents(
                [.day],
                from: start,
                to: target
            ).day ?? -1

        guard dayOffset >= 0 else {
            return false
        }

        let targetWeekIndex = dayOffset / 7
        guard plan.weeks.indices.contains(targetWeekIndex)
        else {
            return false
        }

        let weekday = calendar.component(
            .weekday,
            from: target
        )
        let targetDayNumber =
            ((weekday + 5) % 7) + 1
        guard let targetDayIndex =
                plan.weeks[targetWeekIndex]
                    .days
                    .firstIndex(
                        where: {
                            $0.dayIndex == targetDayNumber
                        }
                    )
        else {
            return false
        }

        plan.weeks[sourceWeekIndex]
            .days[sourceDayIndex]
            .sessions
            .removeAll { $0.id == sessionID }

        movedSession.scheduledStart = target
        plan.weeks[targetWeekIndex]
            .days[targetDayIndex]
            .sessions
            .append(movedSession)

        setPlanSessionSkipped(
            planID: planID,
            sessionID: sessionID,
            skipped: false
        )

        plan.version += 1
        plan.updatedAt = Date()
        replaceTrainingPlan(plan)
        return true
    }

    @discardableResult
    func updateTrainingPlan(
        planID: UUID,
        title: String,
        summary: String,
        visibility: ProfileVisibility,
        tags: [String],
        startDate: Date,
        weekCount: Int
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

        let resolvedWeekCount = min(max(weekCount, 1), 52)
        let currentWeekCount = plan.weeks.count

        if resolvedWeekCount > currentWeekCount {
            for number in (currentWeekCount + 1)...resolvedWeekCount {
                plan.weeks.append(makeEmptyWeek(number: number))
            }
        } else if resolvedWeekCount < currentWeekCount {
            plan.weeks = Array(
                plan.weeks.prefix(resolvedWeekCount)
            )
        }

        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(
            byAdding: .day,
            value: max(resolvedWeekCount * 7 - 1, 0),
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

    @discardableResult
    func setTrainingPlanWeekCount(
        planID: UUID,
        weekCount: Int
    ) -> Bool {
        guard let plan = trainingPlan(withID: planID) else {
            return false
        }

        return updateTrainingPlan(
            planID: planID,
            title: plan.title,
            summary: plan.summary,
            visibility: plan.visibility,
            tags: plan.tags,
            startDate:
                plan.startDate ??
                Calendar.current.startOfDay(for: Date()),
            weekCount: weekCount
        )
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
        guard let plan = trainingPlan(withID: planID) else {
            return false
        }

        return updateTrainingPlan(
            planID: planID,
            title: title,
            summary: summary,
            visibility: visibility,
            tags: tags,
            startDate: startDate,
            weekCount: plan.weeks.count
        )
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

    @discardableResult
    func createTrainingPlan(
        title: String,
        summary: String,
        weekCount: Int,
        startDate: Date?,
        endDate: Date? = nil,
        visibility: ProfileVisibility = .privateOnly
    ) -> TrainingPlan? {
        let resolvedWeekCount = min(max(weekCount, 1), 52)
        let resolvedStart = Calendar.current.startOfDay(
            for: startDate ?? Date()
        )
        let resolvedEnd = endDate.map {
            Calendar.current.startOfDay(for: max($0, resolvedStart))
        } ?? Calendar.current.date(
            byAdding: .day,
            value: max(resolvedWeekCount * 7 - 1, 0),
            to: resolvedStart
        )

        let plan = TrainingPlan(
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
            startDate: resolvedStart,
            endDate: resolvedEnd
        )

        guard addTrainingPlan(plan) else {
            return nil
        }

        return plan
    }

    @discardableResult
    func createSimpleTrainingPlan(
        title: String,
        summary: String,
        weekCount: Int,
        startDate: Date?,
        visibility: ProfileVisibility = .privateOnly,
        sessionsPerWeek: Int,
        workoutPattern: [WorkoutKind]
    ) -> TrainingPlan? {
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

        let resolvedStart = Calendar.current.startOfDay(
            for: startDate ?? Date()
        )
        let resolvedEnd = Calendar.current.date(
            byAdding: .day,
            value: max(resolvedWeekCount * 7 - 1, 0),
            to: resolvedStart
        )

        let plan = TrainingPlan(
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
            startDate: resolvedStart,
            endDate: resolvedEnd
        )

        guard addTrainingPlan(plan) else {
            return nil
        }

        return plan
    }

    @discardableResult
    func createConfiguredTrainingPlan(
        title: String,
        summary: String,
        weekCount: Int,
        startDate: Date?,
        endDate: Date? = nil,
        visibility: ProfileVisibility = .privateOnly,
        builderProfile: TrainingPlanBuilderProfile,
        seedSuggestedWeek: Bool
    ) -> TrainingPlan? {
        let resolvedWeekCount =
            min(max(weekCount, 1), 52)
        let resolvedStart =
            Calendar.current.startOfDay(
                for: startDate ?? Date()
            )
        let resolvedEnd =
            endDate.map {
                Calendar.current.startOfDay(
                    for: max($0, resolvedStart)
                )
            } ??
            Calendar.current.date(
                byAdding: .day,
                value:
                    max(
                        resolvedWeekCount * 7 - 1,
                        0
                    ),
                to: resolvedStart
            )

        let normalizedDays =
            Array(
                Set(
                    builderProfile
                        .preferredDayIndexes
                        .filter {
                            (1...7).contains($0)
                        }
                )
            )
            .sorted()
        let targetDays =
            normalizedDays.isEmpty
                ? [1, 3, 5]
                : normalizedDays
        let pattern =
            builderProfile
                .primaryFocus?
                .suggestedWorkoutPattern ??
            [.strength, .running]

        func suggestedTitle(
            kind: WorkoutKind,
            slot: Int
        ) -> String {
            switch kind {
            case .strength:
                if builderProfile.primaryFocus ==
                    .hypertrophy {
                    let names = [
                        ATHLTHLocalization.choose(
                            english: "Upper body",
                            norwegian: "Overkropp"
                        ),
                        ATHLTHLocalization.choose(
                            english: "Lower body",
                            norwegian: "Underkropp"
                        ),
                        ATHLTHLocalization.choose(
                            english: "Full body",
                            norwegian: "Helkropp"
                        )
                    ]
                    return names[
                        slot % names.count
                    ]
                }

                return ATHLTHLocalization.choose(
                    english:
                        "Strength \(Character(UnicodeScalar(65 + (slot % 4))!))",
                    norwegian:
                        "Styrke \(Character(UnicodeScalar(65 + (slot % 4))!))"
                )

            case .running:
                let names = [
                    ATHLTHLocalization.choose(
                        english: "Easy run",
                        norwegian: "Rolig løp"
                    ),
                    ATHLTHLocalization.choose(
                        english: "Intervals",
                        norwegian: "Intervaller"
                    ),
                    ATHLTHLocalization.choose(
                        english: "Long run",
                        norwegian: "Langtur"
                    )
                ]
                return names[
                    slot % names.count
                ]

            case .walking:
                return ATHLTHLocalization.choose(
                    english: "Walk",
                    norwegian: "Gåtur"
                )

            case .mobility:
                return ATHLTHLocalization.choose(
                    english: "Mobility",
                    norwegian: "Mobilitet"
                )

            case .recovery:
                return ATHLTHLocalization.choose(
                    english: "Active recovery",
                    norwegian: "Aktiv restitusjon"
                )

            case .custom:
                return ATHLTHLocalization.choose(
                    english: "Workout",
                    norwegian: "Treningsøkt"
                )
            }
        }

        func makeSession(
            kind: WorkoutKind,
            slot: Int
        ) -> PlannedSession {
            let duration: Int
            let distance: Double?
            // Only add editable suggestions when the user requested a muscle
            // priority and explicitly chose the suggested week structure.
            let suggestedExercises: [PlannedExercise]
            if kind == .strength,
               let primaryMuscle = builderProfile.priorityMuscles.first {
                suggestedExercises = FocusedMuscleExerciseSuggestions.makeExercises(
                    for: primaryMuscle,
                    sessionIndex: slot
                )
            } else {
                suggestedExercises = []
            }

            switch kind {
            case .running:
                duration = 45
                distance = nil
            case .walking:
                duration = 45
                distance = nil
            case .strength:
                duration = 55
                distance = nil
            case .mobility:
                duration = 25
                distance = nil
            case .recovery:
                duration = 30
                distance = nil
            case .custom:
                duration = 45
                distance = nil
            }

            return PlannedSession(
                id: UUID(),
                title:
                    suggestedTitle(
                        kind: kind,
                        slot: slot
                    ),
                kind: kind,
                scheduledStart: nil,
                durationMinutes: duration,
                targetDistanceKilometers:
                    distance,
                targetPaceSecondsPerKilometer:
                    nil,
                routeID: nil,
                exercises: suggestedExercises,
                notes: nil,
                runningWorkout: nil
            )
        }

        var weeks =
            (1...resolvedWeekCount)
                .map(makeEmptyWeek)

        if seedSuggestedWeek {
            for weekIndex in weeks.indices {
                for (
                    slot,
                    dayIndex
                ) in targetDays.enumerated() {
                    guard
                        let actualDayIndex =
                            weeks[weekIndex]
                                .days
                                .firstIndex(
                                    where: {
                                        $0.dayIndex ==
                                        dayIndex
                                    }
                                )
                    else {
                        continue
                    }

                    let kind =
                        builderProfile
                            .preferredWorkoutKindsByDay?[
                                dayIndex
                            ] ??
                        pattern[
                            slot %
                            max(
                                pattern.count,
                                1
                            )
                        ]

                    weeks[weekIndex]
                        .days[actualDayIndex]
                        .sessions = [
                            makeSession(
                                kind: kind,
                                slot: slot
                            )
                        ]
                }
            }
        }

        let trimmedSummary =
            summary
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        let fallbackSummary =
            [
                builderProfile.primaryFocus?.title,
                builderProfile.goal?.title
            ]
            .compactMap { $0 }
            .joined(separator: " · ")

        let plan = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title:
                title
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
                    ? ATHLTHLocalization.choose(
                        english: "My Training Plan",
                        norwegian: "Min treningsplan"
                    )
                    : title
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ),
            summary:
                trimmedSummary.isEmpty
                    ? fallbackSummary
                    : trimmedSummary,
            visibility: visibility,
            version: 1,
            weeks: weeks,
            tags: [],
            createdAt: Date(),
            updatedAt: Date(),
            startDate: resolvedStart,
            endDate: resolvedEnd,
            builderProfile: builderProfile
        )

        guard addTrainingPlan(plan) else {
            return nil
        }

        return plan
    }

    func replaceActivePlan(with plan: TrainingPlan) {
        var replacement = plan

        if let current = activePlan {
            replacement.startDate =
                current.startDate ??
                Calendar.current.startOfDay(for: Date())
            replacement.endDate =
                current.endDate ??
                trainingPlanEndDate(current)
        } else if replacement.startDate == nil {
            replacement.startDate =
                Calendar.current.startOfDay(for: Date())
        }

        replacement = normalizedTrainingPlan(replacement)
        activePlan = replacement
        scheduledPlans.removeAll { $0.id == replacement.id }
        persistScheduledPlans()
    }

    @discardableResult
    func fillEmptyDaysFromGeneratedProgram(
        _ generated: TrainingPlan,
        expectedPlanID: UUID? = nil,
        expectedVersion: Int? = nil
    ) -> Bool {
        guard var current = activePlan,
              expectedPlanID == nil || current.id == expectedPlanID,
              expectedVersion == nil || current.version == expectedVersion
        else { return false }

        // Complete is strictly additive inside the original plan window.
        // Match explicit week/day numbers; never truncate, extend or shift it.
        for weekIndex in current.weeks.indices {
            guard let generatedWeek = generated.weeks.first(where: {
                $0.weekNumber == current.weeks[weekIndex].weekNumber
            }) else { continue }
            for dayIndex in current.weeks[weekIndex].days.indices {
                guard current.weeks[weekIndex].days[dayIndex].sessions.isEmpty,
                      let generatedDay = generatedWeek.days.first(where: {
                          $0.dayIndex == current.weeks[weekIndex].days[dayIndex].dayIndex
                      })
                else { continue }
                current.weeks[weekIndex].days[dayIndex].sessions = generatedDay.sessions
            }
        }
        current.updatedAt = Date()
        current.version += 1
        activePlan = current
        return true
    }

    @discardableResult
    func stageCoachPlanProposal(
        _ proposal: CoachPlanChangeProposal
    ) -> Bool {
        guard let plan = trainingPlan(withID: proposal.planID),
              proposal.status == .proposed,
              proposal.isStillValid(for: plan)
        else {
            return false
        }

        pendingCoachPlanProposal = proposal
        persistAccountContent()
        return true
    }

    func dismissCoachPlanProposal() {
        pendingCoachPlanProposal = nil
        persistAccountContent()
    }

    @discardableResult
    func applyCoachPlanProposal(
        _ proposal: CoachPlanChangeProposal
    ) -> Bool {
        guard var plan = trainingPlan(withID: proposal.planID),
              proposal.status == .proposed,
              proposal.isStillValid(for: plan)
        else {
            return false
        }

        let before = plan
        var didChange = false

        func dayLocation(for date: Date) -> (week: Int, day: Int)? {
            guard let startDate = plan.startDate else { return nil }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: startDate)
            let target = calendar.startOfDay(for: date)
            guard let offset = calendar.dateComponents(
                [.day],
                from: start,
                to: target
            ).day,
            offset >= 0,
            offset < plan.weeks.count * 7
            else {
                return nil
            }

            let weekNumber = (offset / 7) + 1
            let dayIndex = (offset % 7) + 1
            guard let weekIndex = plan.weeks.firstIndex(
                where: { $0.weekNumber == weekNumber }
            ),
            let resolvedDayIndex = plan.weeks[weekIndex].days.firstIndex(
                where: { $0.dayIndex == dayIndex }
            )
            else {
                return nil
            }

            return (weekIndex, resolvedDayIndex)
        }

        func sessionLocation(
            _ sessionID: UUID
        ) -> (week: Int, day: Int, session: Int)? {
            for weekIndex in plan.weeks.indices {
                for dayIndex in plan.weeks[weekIndex].days.indices {
                    if let sessionIndex = plan.weeks[weekIndex]
                        .days[dayIndex]
                        .sessions
                        .firstIndex(where: { $0.id == sessionID }) {
                        return (weekIndex, dayIndex, sessionIndex)
                    }
                }
            }
            return nil
        }

        for change in proposal.changes {
            switch change.kind {
            case .moveWorkout:
                guard let sessionID = change.sessionID,
                      let targetDate = change.targetDate,
                      let source = sessionLocation(sessionID),
                      let target = dayLocation(for: targetDate)
                else { continue }

                var session = plan.weeks[source.week]
                    .days[source.day]
                    .sessions.remove(at: source.session)

                if let scheduledStart = session.scheduledStart {
                    let calendar = Calendar.current
                    let components = calendar.dateComponents(
                        [.hour, .minute, .second],
                        from: scheduledStart
                    )
                    session.scheduledStart = calendar.date(
                        bySettingHour: components.hour ?? 8,
                        minute: components.minute ?? 0,
                        second: components.second ?? 0,
                        of: targetDate
                    )
                }

                plan.weeks[target.week]
                    .days[target.day]
                    .sessions.append(session)
                didChange = true

            case .replaceWorkout:
                guard let sessionID = change.sessionID,
                      let location = sessionLocation(sessionID)
                else { continue }

                if let replacementTitle = change.replacementTitle?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !replacementTitle.isEmpty {
                    plan.weeks[location.week]
                        .days[location.day]
                        .sessions[location.session]
                        .title = replacementTitle
                }
                if let duration = change.durationMinutes {
                    plan.weeks[location.week]
                        .days[location.day]
                        .sessions[location.session]
                        .durationMinutes = min(max(duration, 10), 240)
                }
                if let note = change.intensityNote?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    plan.weeks[location.week]
                        .days[location.day]
                        .sessions[location.session]
                        .notes = note
                }
                didChange = true

            case .adjustDuration:
                guard let sessionID = change.sessionID,
                      let duration = change.durationMinutes,
                      let location = sessionLocation(sessionID)
                else { continue }

                plan.weeks[location.week]
                    .days[location.day]
                    .sessions[location.session]
                    .durationMinutes = min(max(duration, 10), 240)
                didChange = true

            case .adjustIntensity:
                guard let sessionID = change.sessionID,
                      let note = change.intensityNote?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !note.isEmpty,
                      let location = sessionLocation(sessionID)
                else { continue }

                let existing = plan.weeks[location.week]
                    .days[location.day]
                    .sessions[location.session]
                    .notes?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                plan.weeks[location.week]
                    .days[location.day]
                    .sessions[location.session]
                    .notes = [existing, "Coach: \(note)"]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                didChange = true

            case .addRecovery:
                guard let targetDate = change.targetDate,
                      let target = dayLocation(for: targetDate)
                else { continue }

                let session = PlannedSession(
                    id: UUID(),
                    title: {
                        let value = change.replacementTitle?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return (value?.isEmpty == false) ? value! : "Recovery"
                    }(),
                    kind: .recovery,
                    scheduledStart: nil,
                    durationMinutes: min(
                        max(change.durationMinutes ?? 25, 10),
                        90
                    ),
                    targetDistanceKilometers: nil,
                    targetPaceSecondsPerKilometer: nil,
                    routeID: nil,
                    exercises: [],
                    notes: change.intensityNote ?? change.reason
                )
                plan.weeks[target.week]
                    .days[target.day]
                    .sessions.append(session)
                didChange = true

            case .removeWorkout:
                guard let sessionID = change.sessionID,
                      let location = sessionLocation(sessionID)
                else { continue }

                plan.weeks[location.week]
                    .days[location.day]
                    .sessions.remove(at: location.session)
                didChange = true
            }
        }

        guard didChange else {
            return false
        }

        plan.updatedAt = Date()
        plan.version += 1

        var acceptedProposal = proposal
        acceptedProposal.status = .accepted
        let record = CoachPlanAdaptationRecord(
            proposal: acceptedProposal,
            planBefore: before,
            planAfter: plan
        )

        replaceTrainingPlan(plan)
        pendingCoachPlanProposal = nil
        coachPlanAdaptationHistory.insert(record, at: 0)
        coachPlanAdaptationHistory = Array(
            coachPlanAdaptationHistory.prefix(12)
        )
        persistAccountContent()
        return true
    }

    @discardableResult
    func revertCoachPlanAdaptation(
        _ recordID: UUID
    ) -> Bool {
        guard let index = coachPlanAdaptationHistory.firstIndex(
            where: { $0.id == recordID }
        ),
        coachPlanAdaptationHistory[index].revertedAt == nil
        else {
            return false
        }

        let record = coachPlanAdaptationHistory[index]
        guard let current = trainingPlan(withID: record.planAfter.id),
              current.version == record.planAfter.version
        else {
            return false
        }

        var restored = record.planBefore
        restored.updatedAt = Date()
        restored.version = current.version + 1

        var revertedProposal = record.proposal
        revertedProposal.status = .reverted
        coachPlanAdaptationHistory[index].proposal = revertedProposal
        coachPlanAdaptationHistory[index].revertedAt = Date()

        replaceTrainingPlan(restored)
        persistAccountContent()
        return true
    }

    func setActivePlanWeekCount(_ weekCount: Int) {
        guard let planID = activePlan?.id else {
            return
        }

        _ = setTrainingPlanWeekCount(
            planID: planID,
            weekCount: weekCount
        )
    }

    func addWeekToActivePlan() {
        guard let planID = activePlan?.id else {
            createStarterPlan()
            return
        }

        addWeekToTrainingPlan(planID: planID)
    }

    func addWeekToTrainingPlan(
        planID: UUID
    ) {
        guard let plan = trainingPlan(withID: planID) else {
            return
        }

        _ = setTrainingPlanWeekCount(
            planID: planID,
            weekCount: min(plan.weeks.count + 1, 52)
        )
    }

    func removeWeekFromActivePlan(_ weekID: UUID) {
        guard let planID = activePlan?.id else {
            return
        }

        removeWeekFromTrainingPlan(
            planID: planID,
            weekID: weekID
        )
    }

    func removeWeekFromTrainingPlan(
        planID: UUID,
        weekID: UUID
    ) {
        guard var plan = trainingPlan(withID: planID),
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

        if let startDate = plan.startDate {
            plan.endDate = Calendar.current.date(
                byAdding: .day,
                value: max(plan.weeks.count * 7 - 1, 0),
                to: Calendar.current.startOfDay(for: startDate)
            )
        }

        plan.updatedAt = Date()
        plan.version += 1
        replaceTrainingPlan(plan)
    }

    func addStandalonePlannedSession(
        _ session: PlannedSession
    ) {
        guard session.scheduledStart != nil else {
            return
        }

        standalonePlannedSessions.removeAll {
            $0.id == session.id
        }
        standalonePlannedSessions.append(session)
        standalonePlannedSessions.sort {
            ($0.scheduledStart ?? .distantFuture) <
            ($1.scheduledStart ?? .distantFuture)
        }
        persistAccountContent()
    }

    func updateStandalonePlannedSession(
        _ session: PlannedSession
    ) {
        guard let index =
                standalonePlannedSessions
                    .firstIndex(
                        where: {
                            $0.id == session.id
                        }
                    )
        else {
            addStandalonePlannedSession(
                session
            )
            return
        }

        standalonePlannedSessions[index] =
            session
        standalonePlannedSessions.sort {
            ($0.scheduledStart ?? .distantFuture) <
            ($1.scheduledStart ?? .distantFuture)
        }
        persistAccountContent()
    }

    func removeStandalonePlannedSession(
        _ sessionID: UUID
    ) {
        standalonePlannedSessions
            .removeAll {
                $0.id == sessionID
            }
        persistAccountContent()
    }

    func standalonePlannedSessions(
        on date: Date
    ) -> [PlannedSession] {
        let calendar = Calendar.current
        return standalonePlannedSessions
            .filter {
                guard let scheduled =
                        $0.scheduledStart
                else {
                    return false
                }

                return calendar.isDate(
                    scheduled,
                    inSameDayAs: date
                )
            }
            .sorted {
                ($0.scheduledStart ?? .distantFuture) <
                ($1.scheduledStart ?? .distantFuture)
            }
    }

    func addSession(
        _ session: PlannedSession,
        toDay dayID: UUID
    ) {
        guard let planID = activePlan?.id else {
            return
        }

        addSession(
            session,
            toDay: dayID,
            inPlan: planID
        )
    }

    func addSession(
        _ session: PlannedSession,
        toDay dayID: UUID,
        inPlan planID: UUID
    ) {
        guard var plan = trainingPlan(withID: planID) else {
            return
        }

        for weekIndex in plan.weeks.indices {
            guard let dayIndex = plan.weeks[weekIndex].days.firstIndex(
                where: { $0.id == dayID }
            ) else {
                continue
            }

            plan.weeks[weekIndex]
                .days[dayIndex]
                .sessions
                .append(session)
            plan.updatedAt = Date()
            plan.version += 1
            replaceTrainingPlan(plan)
            return
        }
    }

    func updateSession(
        _ updatedSession: PlannedSession,
        inPlan planID: UUID
    ) {
        guard var plan = trainingPlan(withID: planID) else {
            return
        }

        for weekIndex in plan.weeks.indices {
            for dayIndex in plan.weeks[weekIndex].days.indices {
                guard let sessionIndex =
                    plan.weeks[weekIndex]
                        .days[dayIndex]
                        .sessions
                        .firstIndex(
                            where: {
                                $0.id == updatedSession.id
                            }
                        )
                else {
                    continue
                }

                plan.weeks[weekIndex]
                    .days[dayIndex]
                    .sessions[sessionIndex] = updatedSession
                plan.updatedAt = Date()
                plan.version += 1
                replaceTrainingPlan(plan)
                return
            }
        }
    }

    func removeSession(
        _ sessionID: UUID,
        fromDay dayID: UUID
    ) {
        guard let planID = activePlan?.id else {
            return
        }

        removeSession(
            sessionID,
            fromDay: dayID,
            inPlan: planID
        )
    }

    func removeSession(
        _ sessionID: UUID,
        fromDay dayID: UUID,
        inPlan planID: UUID
    ) {
        guard var plan = trainingPlan(withID: planID) else {
            return
        }

        for weekIndex in plan.weeks.indices {
            guard let dayIndex = plan.weeks[weekIndex].days.firstIndex(
                where: { $0.id == dayID }
            ) else {
                continue
            }

            plan.weeks[weekIndex]
                .days[dayIndex]
                .sessions
                .removeAll { $0.id == sessionID }
            plan.updatedAt = Date()
            plan.version += 1
            replaceTrainingPlan(plan)
            return
        }
    }

    func duplicateActivePlan() {
        guard let planID = activePlan?.id else {
            return
        }

        _ = duplicateTrainingPlan(planID)
    }

    @discardableResult
    func setTrainingPlanSpotify(
        planID: UUID,
        playlist: SpotifyPlaylistReference?,
        autoplay: Bool
    ) -> Bool {
        guard var plan = trainingPlan(withID: planID) else {
            return false
        }

        plan.spotifyPlaylist = playlist
        plan.spotifyAutoplayOnWorkoutStart = autoplay
        plan.updatedAt = Date()
        plan.version += 1
        replaceTrainingPlan(plan)
        return true
    }

    func setActivePlanSpotifyPlaylist(_ playlist: SpotifyPlaylistReference?) {
        guard let planID = activePlan?.id else { return }
        _ = setTrainingPlanSpotify(
            planID: planID,
            playlist: playlist,
            autoplay:
                activePlan?.spotifyAutoplayOnWorkoutStart
                ?? true
        )
    }

    func setActivePlanSpotifyAutoplay(_ enabled: Bool) {
        guard let activePlan else { return }
        _ = setTrainingPlanSpotify(
            planID: activePlan.id,
            playlist: activePlan.spotifyPlaylist,
            autoplay: enabled
        )
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
        guard let planID = activePlan?.id else {
            return
        }

        _ = updateTrainingPlanMetadata(
            planID: planID,
            title: title,
            summary: summary,
            visibility: visibility,
            tags: tags,
            startDate: startDate ?? Date()
        )
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

    @discardableResult
    func usePlanTemplate(
        _ templateID: UUID,
        startDate: Date? = nil
    ) -> TrainingPlan? {
        guard let template = planTemplates.first(
            where: { $0.id == templateID }
        ) else {
            return nil
        }

        let requestedStart =
            Calendar.current.startOfDay(
                for: startDate ?? Date()
            )
        let isCatalogTemplate =
            template.tags.contains {
                $0.hasPrefix("catalog:")
            }
        let resolvedStartDate =
            isCatalogTemplate
                ? Self.catalogWeekStart(
                    onOrAfter: requestedStart
                )
                : requestedStart
        let resolvedEndDate = Calendar.current.date(
            byAdding: .day,
            value: max(template.weeks.count * 7 - 1, 0),
            to: resolvedStartDate
        )

        let plan = TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: template.title,
            summary: template.summary,
            visibility: .privateOnly,
            version: 1,
            weeks: template.weeks,
            tags: template.tags,
            spotifyPlaylist: template.spotifyPlaylist,
            spotifyAutoplayOnWorkoutStart:
                template.spotifyAutoplayOnWorkoutStart,
            createdAt: Date(),
            updatedAt: Date(),
            startDate: resolvedStartDate,
            endDate: resolvedEndDate
        )

        guard addTrainingPlan(plan) else {
            return nil
        }

        return plan
    }

    func deletePlanTemplate(_ templateID: UUID) {
        planTemplates.removeAll { $0.id == templateID }
        persistPlanTemplates()
    }

    @discardableResult
    func saveCatalogPlanTemplate(
        _ entry: TrainingPlanCatalogEntry,
        preferredDayIndexes: [Int]? = nil
    ) -> TrainingPlan? {
        let catalogTag = "catalog:\(entry.slug)"
        let versionTag =
            "catalog-version:\(entry.catalogVersion)"

        if preferredDayIndexes == nil,
           let existing = planTemplates.first(
            where: {
                $0.tags.contains(catalogTag) &&
                $0.tags.contains(versionTag)
            }
           ) {
            return existing
        }

        var template = makeCatalogPlan(
            entry,
            startDate: nil,
            preferredDayIndexes: preferredDayIndexes
        )

        if preferredDayIndexes != nil {
            template.title = "\(entry.title) · Custom"
            template.updatedAt = Date()
        }

        planTemplates.insert(template, at: 0)
        persistPlanTemplates()
        return template
    }

    func existingScheduledCatalogPlan(
        _ entry: TrainingPlanCatalogEntry,
        startDate: Date
    ) -> TrainingPlan? {
        let calendar = Calendar.current
        let resolvedStart =
            Self.catalogWeekStart(
                onOrAfter: startDate
            )
        let catalogTag =
            "catalog:\(entry.slug)"
        let versionTag =
            "catalog-version:\(entry.catalogVersion)"

        return trainingPlans.first { plan in
            guard
                plan.tags.contains(catalogTag),
                plan.tags.contains(versionTag),
                let planStart = plan.startDate
            else {
                return false
            }

            return calendar.isDate(
                calendar.startOfDay(
                    for: planStart
                ),
                inSameDayAs:
                    resolvedStart
            )
        }
    }

    @discardableResult
    func scheduleCatalogPlan(
        _ entry: TrainingPlanCatalogEntry,
        startDate: Date,
        preferredDayIndexes: [Int]
    ) -> TrainingPlan? {
        let start = Self.catalogWeekStart(
            onOrAfter: startDate
        )

        // Scheduling the exact same catalog plan for the same start
        // date is idempotent. This prevents a successfully created
        // upcoming plan from turning into an apparent duplicate/error
        // if the user opens the Library flow again.
        if let existing =
            existingScheduledCatalogPlan(
                entry,
                startDate: start
            ) {
            return existing
        }

        let plan = makeCatalogPlan(
            entry,
            startDate: start,
            preferredDayIndexes: preferredDayIndexes
        )

        guard addTrainingPlan(plan) else {
            return nil
        }

        return plan
    }

    private func makeCatalogPlan(
        _ entry: TrainingPlanCatalogEntry,
        startDate: Date?,
        preferredDayIndexes: [Int]?
    ) -> TrainingPlan {
        let weekCount = min(
            max(entry.durationWeeks, 1),
            52
        )
        let sessionsPerWeek = min(
            max(entry.sessionsPerWeek, 2),
            6
        )
        let blueprints =
            entry.sessionBlueprints.isEmpty
                ? [
                    TrainingPlanCatalogSessionBlueprint.easyRun,
                    .strength
                ]
                : entry.sessionBlueprints
        let targetDayIndexes =
            resolvedCatalogDayIndexes(
                preferredDayIndexes,
                sessionsPerWeek: sessionsPerWeek
            )

        func makeCatalogSession(
            _ blueprint: TrainingPlanCatalogSessionBlueprint,
            weekNumber: Int
        ) -> PlannedSession {
            let blueprintNote = blueprint.note(
                week: weekNumber,
                totalWeeks: weekCount
            )
            let noteParts = [
                "From ATHLTH Plan Library · \(entry.title)",
                blueprintNote
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

            return PlannedSession(
                id: UUID(),
                title: blueprint.title,
                kind: blueprint.kind,
                scheduledStart: nil,
                durationMinutes:
                    blueprint.durationMinutes(
                        week: weekNumber,
                        totalWeeks: weekCount
                    ),
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil,
                exercises: [],
                notes: noteParts.joined(separator: "\n"),
                runningWorkout: nil
            )
        }

        var weeks = (1...weekCount).map(makeEmptyWeek)

        for weekIndex in weeks.indices {
            for (slot, dayIndex) in
                targetDayIndexes.enumerated() {
                guard let actualDayIndex =
                        weeks[weekIndex]
                            .days
                            .firstIndex(
                                where: {
                                    $0.dayIndex == dayIndex
                                }
                            )
                else {
                    continue
                }

                let blueprint =
                    blueprints[slot % blueprints.count]

                weeks[weekIndex]
                    .days[actualDayIndex]
                    .sessions = [
                        makeCatalogSession(
                            blueprint,
                            weekNumber: weekIndex + 1
                        )
                    ]
            }
        }

        let catalogTag = "catalog:\(entry.slug)"
        let versionTag =
            "catalog-version:\(entry.catalogVersion)"
        let resolvedStart = startDate.map {
            Calendar.current.startOfDay(for: $0)
        }
        let resolvedEnd = resolvedStart.flatMap {
            Calendar.current.date(
                byAdding: .day,
                value: max(weekCount * 7 - 1, 0),
                to: $0
            )
        }

        return TrainingPlan(
            id: UUID(),
            ownerID: profile.userID,
            title: entry.title,
            summary: entry.summary,
            visibility: .privateOnly,
            version: 1,
            weeks: weeks,
            tags:
                Array(
                    Set(
                        entry.tags +
                        [
                            catalogTag,
                            versionTag,
                            entry.category,
                            entry.level.lowercased()
                        ]
                    )
                ),
            createdAt: Date(),
            updatedAt: Date(),
            startDate: resolvedStart,
            endDate: resolvedEnd
        )
    }

    nonisolated static func catalogWeekStart(
        onOrAfter date: Date
    ) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(
            .weekday,
            from: day
        )
        let daysToMonday =
            (9 - weekday) % 7

        return calendar.date(
            byAdding: .day,
            value: daysToMonday,
            to: day
        ) ?? day
    }

    private func resolvedCatalogDayIndexes(
        _ preferred: [Int]?,
        sessionsPerWeek: Int
    ) -> [Int] {
        if let preferred {
            let normalized =
                Array(
                    Set(
                        preferred.filter {
                            (1...7).contains($0)
                        }
                    )
                )
                .sorted()

            if normalized.count == sessionsPerWeek {
                return normalized
            }
        }

        switch sessionsPerWeek {
        case 2:
            return [2, 5]
        case 3:
            return [2, 4, 6]
        case 4:
            return [1, 3, 5, 7]
        case 5:
            return [1, 2, 4, 5, 7]
        default:
            return [1, 2, 3, 4, 5, 6]
        }
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
            runningWorkout: source.runningWorkout,
            runningWorkouts: source.runningWorkouts,
            gearIDs: source.gearIDs,
            audioCoachConfiguration:
                source.audioCoachConfiguration,
            spotifyPlaylist:
                source.spotifyPlaylist,
            spotifyAutoplayOnStart:
                source.spotifyAutoplayOnStart,
            targetAlertConfiguration:
                source.targetAlertConfiguration,
            routeAlertConfiguration:
                source.routeAlertConfiguration,
            ghostTargetDurationSeconds:
                source.ghostTargetDurationSeconds,
            ghostUpdates:
                source.ghostUpdates,
            workoutTemplateID:
                source.workoutTemplateID,
            workoutBlocks:
                source.workoutBlocks,
            workoutCategory:
                source.workoutCategory
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

    private func persistAccountContent(
        immediate: Bool = false
    ) {
        guard !loadingAccountContent,
              let userID = localAccountID
        else {
            return
        }

        let content = AccountTrainingContent(
            activePlan: activePlan,
            scheduledPlans: scheduledPlans,
            planTemplates: planTemplates,
            savedWorkoutTemplates: savedWorkoutTemplates,
            standalonePlannedSessions: standalonePlannedSessions,
            manuallyCompletedPlanSessions: manuallyCompletedPlanSessions,
            skippedPlanSessions: skippedPlanSessions,
            savedRoutes: savedRoutes,
            onboardingProfile: onboardingProfile,
            pendingCoachPlanProposal: pendingCoachPlanProposal,
            coachPlanAdaptationHistory: coachPlanAdaptationHistory
        )

        accountContentSaveTask?.cancel()
        accountContentSaveTask = nil

        if immediate {
            writeAccountContent(
                content,
                userID: userID
            )
            return
        }

        accountContentSaveTask =
            Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .milliseconds(400)
                )

                guard !Task.isCancelled,
                      let self,
                      !self.loadingAccountContent,
                      self.localAccountID == userID
                else {
                    return
                }

                self.writeAccountContent(
                    content,
                    userID: userID
                )
                self.accountContentSaveTask = nil
            }
    }

    private func writeAccountContent(
        _ content: AccountTrainingContent,
        userID: UUID
    ) {
        AccountLocalStorage.write(
            content,
            name: "training",
            userID: userID,
            defaults: defaults
        )
        ATHLTHTrainingDataChangeSignal.post(
            userID: userID
        )
    }

    func reloadTrainingContent() {
        guard signedIn else { return }
        localAccountID = nil
        activateLocalAccount(profile.userID)
    }

    func checkpointTrainingContent() {
        persistAccountContent(immediate: true)
    }

    private func activateLocalAccount(_ userID: UUID) {
        guard localAccountID != userID else { return }
        persistAccountContent(immediate: true)
        loadingAccountContent = true
        localAccountID = userID
        aiHealthDataSharingEnabled =
            AccountLocalStorage.read(
                Bool.self,
                name: "aiHealthDataConsent",
                userID: userID,
                defaults: defaults
            ) ?? false
        let stored = AccountLocalStorage.read(AccountTrainingContent.self, name: "training", userID: userID, defaults: defaults)
        let mayMigrate = !defaults.bool(forKey: AccountLocalStorage.key("legacyMigrated", userID: userID))
        let ownsUnlabelledLegacy = defaults.string(forKey: "legacy.trainingOwner") == userID.uuidString
        let legacyPlan = mayMigrate ? Self.loadActivePlan(from: defaults) : nil
        activePlan = stored?.activePlan ?? (legacyPlan?.ownerID == userID ? legacyPlan : nil)
        scheduledPlans = stored?.scheduledPlans ?? (mayMigrate ? Self.loadScheduledPlans(from: defaults).filter { $0.ownerID == userID } : [])
        planTemplates = stored?.planTemplates ?? (mayMigrate ? Self.loadPlanTemplates(from: defaults).filter { $0.ownerID == userID } : [])
        savedRoutes = stored?.savedRoutes ?? (mayMigrate ? Self.loadSavedRoutes(from: defaults).filter { $0.ownerID == userID } : [])
        savedWorkoutTemplates = stored?.savedWorkoutTemplates ?? (mayMigrate && ownsUnlabelledLegacy ? Self.loadSavedWorkoutTemplates(from: defaults) : [])
        standalonePlannedSessions =
            (stored?.standalonePlannedSessions ?? [])
                .sorted {
                    ($0.scheduledStart ?? .distantFuture) <
                    ($1.scheduledStart ?? .distantFuture)
                }
        manuallyCompletedPlanSessions = stored?.manuallyCompletedPlanSessions ?? (mayMigrate && ownsUnlabelledLegacy ? Self.loadManuallyCompletedPlanSessions(from: defaults) : [])
        skippedPlanSessions = stored?.skippedPlanSessions ?? []
        pendingCoachPlanProposal = stored?.pendingCoachPlanProposal
        coachPlanAdaptationHistory = stored?.coachPlanAdaptationHistory ?? []
        onboardingProfile = stored?.onboardingProfile
        if stored == nil && mayMigrate && ownsUnlabelledLegacy,
           let data = defaults.data(forKey: "legacy.onboardingProfile") {
            onboardingProfile = try? JSONDecoder().decode(OnboardingProfileData.self, from: data)
        }
        defaults.set(true, forKey: AccountLocalStorage.key("legacyMigrated", userID: userID))
        loadingAccountContent = false
        migrateLegacyTrainingPlanIfNeeded()
        refreshActivePlanForToday()
        persistAccountContent()
    }

    private func persistActivePlan() {
        persistAccountContent()
    }

    private func persistScheduledPlans() {
        persistAccountContent()
    }

    private func persistSavedRoutes() {
        persistAccountContent()
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
        persistAccountContent()
    }

    private func persistManuallyCompletedPlanSessions() {
        persistAccountContent()
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
        persistAccountContent()
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

    private static func loadScheduledPlans(
        from defaults: UserDefaults
    ) -> [TrainingPlan] {
        guard let data = defaults.data(
            forKey: "session.scheduledTrainingPlans"
        ),
        let plans = try? JSONDecoder().decode(
            [TrainingPlan].self,
            from: data
        )
        else {
            return []
        }

        return plans
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
