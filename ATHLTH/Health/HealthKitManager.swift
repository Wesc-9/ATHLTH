import Combine
import CoreLocation
import Foundation
@preconcurrency import HealthKit

private final class HealthObserverCompletion: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func call() {
        handler()
    }
}

private final class HealthRouteQueryAccumulator:
    @unchecked Sendable {

    private let lock = NSLock()
    private var locations: [CLLocation] = []
    private var completed = false

    func consume(
        batch: [CLLocation]?,
        done: Bool,
        error: Error?
    ) -> Result<[CLLocation], Error>? {
        lock.lock()
        defer { lock.unlock() }

        guard !completed else {
            return nil
        }

        if let error {
            completed = true
            return .failure(error)
        }

        locations.append(
            contentsOf: batch ?? []
        )

        guard done else {
            return nil
        }

        completed = true
        return .success(locations)
    }
}


@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published private(set) var workouts: [WorkoutSummary] = []
    @Published private(set) var pendingWorkoutImports: [PendingWorkoutImport] = []
    @Published private(set) var sleep: SleepSummary = .empty
    @Published private(set) var heart: HeartSummary = .empty
    @Published private(set) var training: TrainingHealthSummary = .empty
    @Published private(set) var recovery: RecoveryReadinessSummary = .buildingBaseline
    @Published private(set) var personalDetails: HealthProfileBasics = .empty
    @Published private(set) var isRefreshing = false
    @Published var authorizationError: String?
    @Published private(set) var backgroundDeliveryTestResult: String?
    @Published private(set) var routeCapabilityTestResult: String?
    @Published private(set) var lastSuccessfulRefreshAt: Date?
    @Published private(set) var backgroundSyncError: String?
    @Published private(set) var automaticRefreshSuspended = false
    @Published private(set) var deferFullRefreshUntilNextLaunch = false
    @Published private(set) var authorizationReviewNeeded = false

    var hasTrainingHealthData: Bool {
        !workouts.isEmpty ||
        sleep.totalAsleep > 0 ||
        heart.latestHeartRate != nil ||
        heart.restingHeartRate != nil ||
        heart.hrvMilliseconds != nil ||
        training.stepsToday != nil ||
        training.activeEnergyKilocaloriesToday != nil ||
        training.exerciseMinutesToday != nil ||
        training.distanceWalkingRunningMetersToday != nil
    }

    var hasReadableHealthData: Bool {
        hasTrainingHealthData || personalDetails.hasAnyValue
    }

    private let healthStore = HKHealthStore()
    private var workoutObjects: [UUID: HKWorkout] = [:]
    private var observerQueries: [HKObserverQuery] = []
    private var backgroundRefreshTask: Task<Void, Never>?
    private var backgroundRefreshNeedsFull = false
    private var allWorkoutsCache: (workouts: [HKWorkout], generatedAt: Date)?
    private var workoutRouteCache:
        [UUID: (route: [CLLocation], generatedAt: Date)] = [:]
    private var profilePerformanceCache: (stats: ProfilePerformanceStats, generatedAt: Date)?
    private var runningRoutePerformanceCache:
        [UUID: RunningRoutePerformanceEntry] = [:]
    private var runningRoutePerformanceCacheLoaded = false
    private let runningRoutePerformanceDiskKey =
        "athlth.health.runningRoutePerformance.v1"
    private var recoveryTrendCache:
        [Int: (snapshot: RecoveryTrendSnapshot, generatedAt: Date)] = [:]
    private var personalRecordsCache: (records: [HealthPersonalRecord], generatedAt: Date)?
    private var trophySnapshotCache: (snapshot: TrophyHealthSnapshot, generatedAt: Date)?
    private var trophyCacheLatestWorkoutID: UUID?
    private var trophyCacheLatestWorkoutEnd: Date?
    private var trophyCacheLatestSleepDuration: TimeInterval?
    private let trophySnapshotDiskKey = "athlth.health.trophySnapshotCache.v2"
    private let legacyAuthorizationFlagKey = "athlth.healthAuthorizationRequested"
    private let authorizationVersionKey = "athlth.healthAuthorizationVersion"
    // Tracks the newest permission set ATHLTH has explicitly requested.
    // Never use this value alone as the connection state: an app update or
    // a newly added Health type must not disconnect an existing Health setup.
    private let currentAuthorizationVersion = 2

    static func hasPersistedAuthorizationMarker(
        legacyRequested: Bool,
        authorizationVersion: Int
    ) -> Bool {
        legacyRequested || authorizationVersion > 0
    }

    private let refreshInProgressKey = "athlth.healthRefreshInProgress"
    private let safeRefreshVersionKey = "athlth.healthSafeRefreshVersion"
    private let currentSafeRefreshVersion = 2
    private let lastSuccessfulRefreshKey = "athlth.healthLastSuccessfulRefreshAt"
    private let workoutImportCutoverKey = "athlth.health.workoutImport.cutover.v1"
    private let workoutImportAnchorKey = "athlth.health.workoutImport.anchor.v1"
    private let workoutImportPendingIDsKey = "athlth.health.workoutImport.pendingIDs.v1"
    private let workoutImportImportedIDsKey = "athlth.health.workoutImport.importedIDs.v1"
    private let workoutImportIgnoredIDsKey = "athlth.health.workoutImport.ignoredIDs.v1"
    private var workoutImportCutoverDate = Date()
    private var workoutImportAnchor: HKQueryAnchor?
    private var pendingExternalWorkoutIDs: Set<UUID> = []
    private var importedExternalWorkoutIDs: Set<UUID> = []
    private var ignoredExternalWorkoutIDs: Set<UUID> = []

    init() {
        let defaults = UserDefaults.standard

        if let storedCutover = defaults.object(
            forKey: workoutImportCutoverKey
        ) as? Date {
            workoutImportCutoverDate = storedCutover
        } else {
            // Grandfather existing Health history while still catching a
            // workout that may have triggered the first post-update launch.
            let cutover = Date().addingTimeInterval(-15 * 60)
            workoutImportCutoverDate = cutover
            defaults.set(cutover, forKey: workoutImportCutoverKey)
        }

        pendingExternalWorkoutIDs = Self.loadWorkoutImportUUIDSet(
            key: workoutImportPendingIDsKey,
            defaults: defaults
        )
        importedExternalWorkoutIDs = Self.loadWorkoutImportUUIDSet(
            key: workoutImportImportedIDsKey,
            defaults: defaults
        )
        ignoredExternalWorkoutIDs = Self.loadWorkoutImportUUIDSet(
            key: workoutImportIgnoredIDsKey,
            defaults: defaults
        )

        if let anchorData = defaults.data(forKey: workoutImportAnchorKey) {
            workoutImportAnchor = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: HKQueryAnchor.self,
                from: anchorData
            )
        }

        if let data = defaults.data(forKey: trophySnapshotDiskKey),
           let cached = try? JSONDecoder().decode(
               TrophySnapshotDiskCache.self,
               from: data
           ),
           Date().timeIntervalSince(cached.generatedAt) < 900 {
            trophySnapshotCache = (
                cached.snapshot,
                cached.generatedAt
            )
            trophyCacheLatestWorkoutID =
                cached.latestWorkoutID
            trophyCacheLatestWorkoutEnd =
                cached.latestWorkoutEnd
            trophyCacheLatestSleepDuration =
                cached.latestSleepDuration
        }

        lastSuccessfulRefreshAt = defaults.object(
            forKey: lastSuccessfulRefreshKey
        ) as? Date

        let interruptedRefresh = defaults.bool(forKey: refreshInProgressKey)
        let hasExistingHealthAuthorization =
            Self.hasPersistedAuthorizationMarker(
                legacyRequested:
                    defaults.bool(forKey: legacyAuthorizationFlagKey),
                authorizationVersion:
                    defaults.integer(forKey: authorizationVersionKey)
            )
        let needsSafeLaunchMigration =
            hasExistingHealthAuthorization &&
            defaults.integer(forKey: safeRefreshVersionKey) <
            currentSafeRefreshVersion

        let shouldUseSafeLaunch =
            interruptedRefresh || needsSafeLaunchMigration

        automaticRefreshSuspended = shouldUseSafeLaunch
        deferFullRefreshUntilNextLaunch = shouldUseSafeLaunch

        // A process termination during a Health refresh must never create an
        // endless crash loop. The next launch starts with automatic Health
        // work suspended and lets the product UI become usable first.
        defaults.set(false, forKey: refreshInProgressKey)
        defaults.set(
            currentSafeRefreshVersion,
            forKey: safeRefreshVersionKey
        )
    }

    var hasRequestedAuthorization: Bool {
        let defaults = UserDefaults.standard
        return Self.hasPersistedAuthorizationMarker(
            legacyRequested:
                defaults.bool(forKey: legacyAuthorizationFlagKey),
            authorizationVersion:
                defaults.integer(forKey: authorizationVersionKey)
        )
    }

    var pendingWorkoutImportCount: Int {
        pendingExternalWorkoutIDs.count
    }

    @discardableResult
    func refreshWorkoutImportInbox() async -> Bool {
        guard healthDataAvailable,
              hasRequestedAuthorization,
              !shouldDeferAutomaticHealthWork
        else {
            return false
        }

        var acceptedWorkoutChanged = false

        do {
            if pendingWorkoutImports.isEmpty,
               !pendingExternalWorkoutIDs.isEmpty {
                await rehydratePendingWorkoutImports()
            }

            let changes = try await fetchWorkoutImportChanges()

            if let newAnchor = changes.anchor {
                workoutImportAnchor = newAnchor
                persistWorkoutImportAnchor(newAnchor)
            }

            let deletedIDs = Set(changes.deleted.map(\.uuid))
            if !deletedIDs.isEmpty {
                if workouts.contains(where: { deletedIDs.contains($0.id) }) {
                    acceptedWorkoutChanged = true
                }

                pendingExternalWorkoutIDs.subtract(deletedIDs)
                importedExternalWorkoutIDs.subtract(deletedIDs)
                ignoredExternalWorkoutIDs.subtract(deletedIDs)
                pendingWorkoutImports.removeAll {
                    deletedIDs.contains($0.id)
                }
                workouts.removeAll {
                    deletedIDs.contains($0.id)
                }

                for id in deletedIDs {
                    workoutObjects[id] = nil
                }
            }

            let mode = externalWorkoutImportMode

            for workout in changes.workouts {
                workoutObjects[workout.uuid] = workout

                if isATHLTHWorkout(workout) {
                    if !workouts.contains(where: { $0.id == workout.uuid }) {
                        acceptedWorkoutChanged = true
                    }
                    continue
                }

                if workout.endDate < workoutImportCutoverDate {
                    continue
                }

                if importedExternalWorkoutIDs.contains(workout.uuid) ||
                    ignoredExternalWorkoutIDs.contains(workout.uuid) {
                    continue
                }

                switch mode {
                case .ask:
                    pendingExternalWorkoutIDs.insert(workout.uuid)

                    if !pendingWorkoutImports.contains(
                        where: { $0.id == workout.uuid }
                    ) {
                        pendingWorkoutImports.append(
                            makePendingWorkoutImport(workout)
                        )
                    }

                case .automatic:
                    importedExternalWorkoutIDs.insert(workout.uuid)
                    pendingExternalWorkoutIDs.remove(workout.uuid)
                    pendingWorkoutImports.removeAll {
                        $0.id == workout.uuid
                    }
                    acceptedWorkoutChanged = true

                case .never:
                    ignoredExternalWorkoutIDs.insert(workout.uuid)
                    pendingExternalWorkoutIDs.remove(workout.uuid)
                    pendingWorkoutImports.removeAll {
                        $0.id == workout.uuid
                    }
                }
            }

            pendingWorkoutImports.sort {
                $0.summary.endDate > $1.summary.endDate
            }
            persistWorkoutImportState()

            if acceptedWorkoutChanged {
                invalidateWorkoutDerivedCaches()
            }

            return acceptedWorkoutChanged
        } catch {
            // Import discovery is deliberately non-blocking. A failed
            // incremental read must never make the rest of ATHLTH unusable;
            // the next foreground/background Health refresh retries it.
            return false
        }
    }

    func importPendingWorkout(_ id: UUID) {
        importPendingWorkouts([id])
    }

    func importPendingWorkouts(_ ids: Set<UUID>) {
        let resolved = ids.intersection(pendingExternalWorkoutIDs)
        guard !resolved.isEmpty else { return }

        let importedSummaries = pendingWorkoutImports
            .filter { resolved.contains($0.id) }
            .map(\.summary)

        pendingExternalWorkoutIDs.subtract(resolved)
        ignoredExternalWorkoutIDs.subtract(resolved)
        importedExternalWorkoutIDs.formUnion(resolved)
        pendingWorkoutImports.removeAll {
            resolved.contains($0.id)
        }

        for summary in importedSummaries
        where !workouts.contains(where: { $0.id == summary.id }) {
            workouts.append(summary)
        }

        workouts.sort { $0.startDate > $1.startDate }
        persistWorkoutImportState()
        invalidateWorkoutDerivedCaches()
    }

    func importAllPendingWorkouts() {
        importPendingWorkouts(pendingExternalWorkoutIDs)
    }

    func ignorePendingWorkout(_ id: UUID) {
        ignorePendingWorkouts([id])
    }

    func ignorePendingWorkouts(_ ids: Set<UUID>) {
        let resolved = ids.intersection(pendingExternalWorkoutIDs)
        guard !resolved.isEmpty else { return }

        pendingExternalWorkoutIDs.subtract(resolved)
        importedExternalWorkoutIDs.subtract(resolved)
        ignoredExternalWorkoutIDs.formUnion(resolved)
        pendingWorkoutImports.removeAll {
            resolved.contains($0.id)
        }
        workouts.removeAll {
            resolved.contains($0.id)
        }

        persistWorkoutImportState()
        invalidateWorkoutDerivedCaches()
    }

    func ignoreAllPendingWorkouts() {
        ignorePendingWorkouts(pendingExternalWorkoutIDs)
    }

    func applyExternalWorkoutImportMode(
        _ mode: ExternalWorkoutImportMode
    ) async {
        switch mode {
        case .ask:
            break
        case .automatic:
            importAllPendingWorkouts()
        case .never:
            ignoreAllPendingWorkouts()
        }

        _ = await refreshWorkoutImportInbox()
    }

    func prepareBackgroundObserversAtLaunch() {
        let defaults = UserDefaults.standard
        let backgroundSyncEnabled =
            defaults.object(forKey: "settings.backgroundHealthSyncEnabled") as? Bool ?? true

        guard healthDataAvailable,
              hasRequestedAuthorization,
              backgroundSyncEnabled
        else {
            return
        }

        // HealthKit may relaunch the app in the background. Observer queries
        // need to exist as early as possible in the launch lifecycle so the
        // pending delivery has a listener ready.
        startBackgroundObservers()
    }

    var healthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var trainingQuantityIdentifiers: [HKQuantityTypeIdentifier] {
        [
            .heartRate,
            .restingHeartRate,
            .walkingHeartRateAverage,
            .heartRateVariabilitySDNN,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .stepCount,
            .flightsClimbed,
            .appleExerciseTime,
            .appleStandTime,
            .vo2Max,
            .oxygenSaturation,
            .respiratoryRate,
            .walkingSpeed,
            .walkingStepLength,
            .runningSpeed,
            .runningPower,
            .runningStrideLength,
            .runningVerticalOscillation,
            .runningGroundContactTime,
            .cyclingSpeed,
            .cyclingPower,
            .swimmingStrokeCount,
            .height,
            .bodyMass
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        if let distance =
                HKObjectType.quantityType(
                    forIdentifier:
                        .distanceWalkingRunning
                ) {
            types.insert(distance)
        }

        return types
    }

    var canWriteWorkouts: Bool {
        healthStore.authorizationStatus(
            for: HKObjectType.workoutType()
        ) == .sharingAuthorized
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKObjectType.activitySummaryType()
        ]

        for identifier in trainingQuantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }

        let characteristicIdentifiers: [HKCharacteristicTypeIdentifier] = [
            .dateOfBirth,
            .biologicalSex
        ]

        for identifier in characteristicIdentifiers {
            if let type = HKObjectType.characteristicType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        return types
    }

    @discardableResult
    func restoreAuthorizationStateFromSystem() async -> Bool {
        guard healthDataAvailable else {
            authorizationReviewNeeded = false
            return false
        }

        let hadLocalSetup = hasRequestedAuthorization

        do {
            let requestStatus =
                try await healthStore.statusForAuthorizationRequest(
                    toShare: shareTypes,
                    read: readTypes
                )

            switch requestStatus {
            case .unnecessary:
                authorizationReviewNeeded = false

                // HealthKit already has a decision for this permission set.
                // Recover the local marker when a TestFlight/app update has
                // lost or migrated app-local defaults, without showing the
                // permission sheet again.
                if !hadLocalSetup {
                    let defaults = UserDefaults.standard
                    defaults.set(true, forKey: legacyAuthorizationFlagKey)
                    defaults.set(
                        currentAuthorizationVersion,
                        forKey: authorizationVersionKey
                    )
                    defaults.set(
                        currentSafeRefreshVersion,
                        forKey: safeRefreshVersionKey
                    )
                    objectWillChange.send()
                }

                return true

            case .shouldRequest:
                // Existing access remains usable. New Health types can be
                // reviewed explicitly from the Apple Health connection row,
                // but they must never make an existing setup look disconnected.
                authorizationReviewNeeded = hadLocalSetup
                return hadLocalSetup

            case .unknown:
                authorizationReviewNeeded = false
                return hadLocalSetup

            @unknown default:
                authorizationReviewNeeded = false
                return hadLocalSetup
            }
        } catch {
            // A request-status lookup is advisory. Never invalidate an
            // existing local connection because this lightweight check failed.
            authorizationReviewNeeded = false
            return hadLocalSetup
        }
    }

    func requestAuthorization() async {
        authorizationError = nil

        guard healthDataAvailable else {
            authorizationError = "Apple Health data isn't available on this device."
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: shareTypes,
                read: readTypes
            )
            UserDefaults.standard.set(true, forKey: legacyAuthorizationFlagKey)
            UserDefaults.standard.set(currentAuthorizationVersion, forKey: authorizationVersionKey)
            UserDefaults.standard.set(
                currentSafeRefreshVersion,
                forKey: safeRefreshVersionKey
            )
            authorizationReviewNeeded = false
            automaticRefreshSuspended = false
            deferFullRefreshUntilNextLaunch = true
            objectWillChange.send()

            // Keep the permission-sheet callback lightweight. A full Health
            // import is intentionally not started while iOS is dismissing
            // the authorization sheet.
            await refreshPersonalDetails()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    func configureBackgroundSync(allowed: Bool) async {
        guard healthDataAvailable,
              !shouldDeferAutomaticHealthWork
        else {
            return
        }

        backgroundSyncError = nil

        guard allowed else {
            await disableBackgroundSync()
            return
        }

        startBackgroundObservers()

        var registrations: [(HKObjectType, HKUpdateFrequency)] = [
            (HKObjectType.workoutType(), .immediate)
        ]

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            registrations.append((sleepType, .hourly))
        }

        let quantityTypes: [(HKQuantityTypeIdentifier, HKUpdateFrequency)] = [
            // ATHLTH does not show continuous background heart rate outside
            // an active Watch workout, so hourly delivery avoids waking the
            // iPhone for every sensor sample.
            (.heartRate, .hourly),
            (.restingHeartRate, .hourly),
            (.walkingHeartRateAverage, .hourly),
            (.heartRateVariabilitySDNN, .hourly),
            (.activeEnergyBurned, .hourly),
            (.basalEnergyBurned, .hourly),
            (.distanceWalkingRunning, .hourly),
            (.distanceCycling, .hourly),
            (.distanceSwimming, .hourly),
            (.stepCount, .hourly),
            (.flightsClimbed, .hourly),
            (.appleExerciseTime, .hourly),
            (.vo2Max, .daily),
            (.bodyMass, .hourly),
            (.height, .daily)
        ]

        for (identifier, frequency) in quantityTypes {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                registrations.append((type, frequency))
            }
        }

        var failures: [String] = []
        var successfulRegistrations = 0

        for (type, frequency) in registrations {
            let result: (Bool, String?) = await withCheckedContinuation { continuation in
                healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
                    continuation.resume(
                        returning: (success, error?.localizedDescription)
                    )
                }
            }

            if result.0 {
                successfulRegistrations += 1
            } else {
                failures.append(
                    result.1 ?? "HealthKit rejected background delivery for \(type.identifier)."
                )
            }
        }

        // A user can intentionally deny individual Health types. Treat that as
        // partial availability rather than a global sync failure. Surface an
        // issue only when HealthKit could not enable any background delivery.
        if successfulRegistrations == 0, !failures.isEmpty {
            backgroundSyncError = failures.joined(separator: "\n")
        }
    }

    func disableBackgroundSync() async {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()

        _ = await withCheckedContinuation { continuation in
            healthStore.disableAllBackgroundDelivery { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    private func startBackgroundObservers() {
        guard observerQueries.isEmpty else { return }

        let sampleTypes = readTypes.compactMap { $0 as? HKSampleType }

        for type in sampleTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) {
                [weak self] _, completionHandler, error in

                guard error == nil else {
                    completionHandler()
                    return
                }

                let completion = HealthObserverCompletion(completionHandler)

                Task { @MainActor [weak self] in
                    guard let self else {
                        completion.call()
                        return
                    }

                    let isWorkoutEvent =
                        type.identifier ==
                        HKObjectType.workoutType().identifier

                    if isWorkoutEvent {
                        _ = await self.refreshWorkoutImportInbox()
                    }

                    await self.coalescedBackgroundRefresh(
                        requireFullRefresh: isWorkoutEvent
                    )
                    completion.call()
                }
            }

            observerQueries.append(query)
            healthStore.execute(query)
        }
    }

    func refreshIfStale(
        maxAge: TimeInterval = 60
    ) async {
        guard !isRefreshing else {
            return
        }

        if let lastSuccessfulRefreshAt,
           Date().timeIntervalSince(lastSuccessfulRefreshAt) < maxAge,
           hasReadableHealthData {
            return
        }

        await refreshAll()
    }

    private func coalescedBackgroundRefresh(
        requireFullRefresh: Bool
    ) async {
        if requireFullRefresh {
            backgroundRefreshNeedsFull = true
        }

        if let existing = backgroundRefreshTask {
            await existing.value
            return
        }

        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: .milliseconds(650)
            )

            guard let self,
                  !Task.isCancelled
            else {
                return
            }

            let fullRefresh = self.backgroundRefreshNeedsFull
            self.backgroundRefreshNeedsFull = false

            if fullRefresh {
                await self.refreshAll()
            } else {
                await self.refreshHealthSignals()
            }
        }

        backgroundRefreshTask = task
        await task.value
        backgroundRefreshTask = nil
    }

    private func refreshHealthSignals() async {
        guard healthDataAvailable,
              !shouldDeferAutomaticHealthWork,
              !isRefreshing
        else {
            return
        }

        isRefreshing = true
        recoveryTrendCache.removeAll()
        defer { isRefreshing = false }

        let previousSleepDuration = sleep.totalAsleep

        async let sleepTask = fetchLatestSleep()
        async let heartTask = fetchHeartSummary()
        async let trainingTask = fetchTrainingSummary()

        var sleepReadSucceeded = false
        var heartReadSucceeded = false

        if let fetchedSleep = try? await sleepTask {
            sleep = fetchedSleep
            sleepReadSucceeded = true

            if fetchedSleep.totalAsleep != previousSleepDuration {
                invalidateTrophySnapshotCache()
            }
        }

        if let fetchedHeart = try? await heartTask {
            heart = fetchedHeart
            heartReadSucceeded = true
        }

        if let fetchedTraining = try? await trainingTask {
            training = fetchedTraining
        }

        if sleepReadSucceeded,
           heartReadSucceeded,
           let refreshedRecovery = try? await fetchRecoveryReadiness(
                currentSleep: sleep,
                currentHeart: heart
           ) {
            recovery = refreshedRecovery
        }

        await refreshPersonalDetails()
    }

    func refreshAll() async {
        let performanceID =
            ATHLTHPerformance.begin("HealthRefresh")
        defer {
            ATHLTHPerformance.end(
                "HealthRefresh",
                id: performanceID
            )
        }

        guard healthDataAvailable,
              !shouldDeferAutomaticHealthWork
        else {
            return
        }

        guard !isRefreshing else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: refreshInProgressKey)

        isRefreshing = true
        authorizationError = nil
        recoveryTrendCache.removeAll()
        defer {
            isRefreshing = false
            defaults.set(
                false,
                forKey:
                    refreshInProgressKey
            )
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .month, value: -3, to: end)
            ?? end.addingTimeInterval(-7_776_000)

        let previousWorkoutIDs = Set(workouts.map(\.id))
        let previousSleepDuration = sleep.totalAsleep

        // These HealthKit reads are independent. Starting them together keeps
        // launch/tab refresh latency close to the slowest query instead of
        // adding every query's latency together.
        async let workoutsTask = fetchWorkouts(
            startDate: start,
            endDate: end,
            limit: 100
        )
        async let sleepTask = fetchLatestSleep()
        async let heartTask = fetchHeartSummary()
        async let trainingTask = fetchTrainingSummary()

        var completedRead = false
        var sleepReadSucceeded = false
        var heartReadSucceeded = false
        var failures: [String] = []

        do {
            let fetched = try await workoutsTask
            let summaries = fetched.map(WorkoutSummary.init)
            workouts = summaries
            workoutObjects = fetched.reduce(into: [:]) { result, workout in
                result[workout.uuid] = workout
            }

            let latestFetchedWorkout = fetched.max {
                $0.endDate < $1.endDate
            }

            let recentWorkoutsChanged: Bool
            if previousWorkoutIDs.isEmpty,
               trophySnapshotCache != nil {
                recentWorkoutsChanged =
                    latestFetchedWorkout?.uuid !=
                        trophyCacheLatestWorkoutID ||
                    latestFetchedWorkout?.endDate !=
                        trophyCacheLatestWorkoutEnd
            } else {
                recentWorkoutsChanged =
                    Set(summaries.map(\.id)) !=
                        previousWorkoutIDs
            }

            if recentWorkoutsChanged {
                invalidateWorkoutDerivedCaches()
            }

            completedRead = true
        } catch {
            failures.append("Workouts: \(error.localizedDescription)")
        }

        do {
            let fetchedSleep = try await sleepTask
            sleep = fetchedSleep

            let sleepChanged: Bool
            if previousSleepDuration == 0,
               let cachedDuration =
                    trophyCacheLatestSleepDuration {
                sleepChanged =
                    fetchedSleep.totalAsleep !=
                    cachedDuration
            } else {
                sleepChanged =
                    fetchedSleep.totalAsleep !=
                    previousSleepDuration
            }

            if sleepChanged {
                invalidateTrophySnapshotCache()
            }
            sleepReadSucceeded = true
            completedRead = true
        } catch {
            failures.append("Sleep: \(error.localizedDescription)")
        }

        do {
            heart = try await heartTask
            heartReadSucceeded = true
            completedRead = true
        } catch {
            failures.append("Heart: \(error.localizedDescription)")
        }

        do {
            training = try await trainingTask
            completedRead = true
        } catch {
            failures.append("Activity: \(error.localizedDescription)")
        }

        if sleepReadSucceeded &&
            heartReadSucceeded {
            do {
                recovery = try await fetchRecoveryReadiness(
                    currentSleep: sleep,
                    currentHeart: heart
                )
                completedRead = true
            } catch {
                failures.append(
                    "Recovery: \(error.localizedDescription)"
                )
            }
        }

        await refreshPersonalDetails()

        if completedRead || personalDetails.hasAnyValue {
            let refreshedAt = Date()
            lastSuccessfulRefreshAt = refreshedAt
            defaults.set(refreshedAt, forKey: lastSuccessfulRefreshKey)
        }

        if let firstFailure = failures.first {
            authorizationError = failures.count == 1
                ? firstFailure
                : "\(firstFailure) (+\(failures.count - 1) more)"
        }
    }

    func resumeAutomaticRefresh() {
        automaticRefreshSuspended = false
        UserDefaults.standard.set(false, forKey: refreshInProgressKey)
    }

    func resumeUserInitiatedHealthSync() {
        automaticRefreshSuspended = false
        deferFullRefreshUntilNextLaunch = false
        UserDefaults.standard.set(false, forKey: refreshInProgressKey)
        UserDefaults.standard.set(
            currentSafeRefreshVersion,
            forKey: safeRefreshVersionKey
        )
    }

    func completeAuthorizationSetup() async {
        // Give iOS a short moment to finish dismissing the Health permission
        // sheet before ATHLTH starts the first full read.
        try? await Task.sleep(nanoseconds: 650_000_000)
        resumeUserInitiatedHealthSync()
    }

    var needsHealthRefreshRecovery: Bool {
        automaticRefreshSuspended
    }

    var shouldDeferAutomaticHealthWork: Bool {
        automaticRefreshSuspended ||
            deferFullRefreshUntilNextLaunch ||
            ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive
    }

    func saveManualStrengthWorkout(
        startDate: Date,
        endDate: Date,
        externalID: UUID
    ) async -> UUID? {
        guard healthDataAvailable,
              canWriteWorkouts,
              endDate > startDate
        else {
            return nil
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: nil
        )

        do {
            try await builder.beginCollection(at: startDate)
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: externalID.uuidString,
                HKMetadataKeySyncIdentifier: "athlth-strength-" + externalID.uuidString,
                HKMetadataKeySyncVersion: 1
            ])
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()

            if let workout {
                workoutObjects[workout.uuid] = workout

                let summary = WorkoutSummary(workout: workout)
                workouts.removeAll { $0.id == summary.id }
                workouts.append(summary)
                workouts.sort { $0.startDate > $1.startDate }
                invalidateWorkoutDerivedCaches()
            }

            return workout?.uuid
        } catch {
            authorizationError =
                "Could not save the ATHLTH strength workout to Apple Health: \(error.localizedDescription)"
            return nil
        }
    }

    func workoutHistory() async throws -> [WorkoutSummary] {
        let fetched = try await fetchAllWorkoutsCached()

        for workout in fetched {
            workoutObjects[workout.uuid] = workout
        }

        return fetched
            .map(WorkoutSummary.init)
            .sorted { $0.startDate > $1.startDate }
    }

    func activeWorkoutDays(
        startDate: Date,
        endDate: Date
    ) async throws -> [Date] {
        guard startDate <= endDate else {
            return []
        }

        let workouts = try await fetchWorkouts(
            startDate: startDate,
            endDate: endDate
        )
        let calendar = Calendar.current

        return Array(
            Set(
                workouts.map {
                    calendar.startOfDay(for: $0.startDate)
                }
            )
        )
        .sorted()
    }

    func progressSnapshot(
        startDate: Date,
        endDate: Date,
        previousStartDate: Date,
        previousEndDate: Date,
        grouping: HealthProgressGrouping
    ) async throws -> HealthProgressSnapshot {
        let current = try await progressMetrics(
            startDate: startDate,
            endDate: endDate,
            grouping: grouping
        )
        let previous = try await progressMetrics(
            startDate: previousStartDate,
            endDate: previousEndDate,
            grouping: grouping
        )

        return HealthProgressSnapshot(
            startDate: startDate,
            endDate: endDate,
            workoutCount: current.workoutCount,
            totalSteps: current.totalSteps,
            averageDailySteps: current.averageDailySteps,
            averageSleepDuration: current.averageSleepDuration,
            trainingDuration: current.trainingDuration,
            workoutDistanceMeters: current.workoutDistanceMeters,
            activeWorkoutDays: current.activeWorkoutDays,
            buckets: current.buckets,
            previousWorkoutCount: previous.workoutCount,
            previousTotalSteps: previous.totalSteps,
            previousAverageDailySteps: previous.averageDailySteps,
            previousAverageSleepDuration: previous.averageSleepDuration,
            previousTrainingDuration: previous.trainingDuration,
            previousWorkoutDistanceMeters:
                previous.workoutDistanceMeters
        )
    }

    func recoveryTrendSnapshot(
        days: Int = 14
    ) async -> RecoveryTrendSnapshot {
        let resolvedDays = min(max(days, 7), 90)

        if let cached = recoveryTrendCache[resolvedDays],
           Date().timeIntervalSince(cached.generatedAt) < 120 {
            return cached.snapshot
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let trendStart = calendar.date(
            byAdding: .day,
            value: -(resolvedDays - 1),
            to: today
        ) ?? today.addingTimeInterval(
            -Double(resolvedDays - 1) * 86_400
        )
        let now = Date()

        let chronicStart = calendar.date(
            byAdding: .day,
            value: -27,
            to: today
        ) ?? today.addingTimeInterval(-27 * 86_400)

        async let sleepTask = sleepDurationsByWakeDay(
            startDate: trendStart,
            endDate: now
        )
        async let hrvTask = dailyAverageQuantities(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            startDate: trendStart,
            endDate: now
        )
        async let restingTask = dailyAverageQuantities(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate: trendStart,
            endDate: now
        )
        async let respiratoryTask = dailyAverageQuantities(
            identifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate: trendStart,
            endDate: now
        )
        async let trendWorkoutsTask = fetchWorkouts(
            startDate: trendStart,
            endDate: now
        )
        async let chronicWorkoutsTask = fetchWorkouts(
            startDate: chronicStart,
            endDate: now
        )

        let sleepByDay = (try? await sleepTask) ?? [:]
        let hrvByDay = (try? await hrvTask) ?? [:]
        let restingByDay = (try? await restingTask) ?? [:]
        let respiratoryByDay = (try? await respiratoryTask) ?? [:]
        let trendWorkouts = (try? await trendWorkoutsTask) ?? []
        let chronicWorkouts = (try? await chronicWorkoutsTask) ?? []

        var trainingMinutesByDay: [Date: Double] = [:]

        for workout in trendWorkouts {
            let day = calendar.startOfDay(
                for: workout.startDate
            )
            trainingMinutesByDay[day, default: 0] +=
                workout.duration / 60
        }

        let trendDays: [RecoveryTrendDay] =
            (0..<resolvedDays).compactMap { offset in
                guard let day = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: trendStart
                ) else {
                    return nil
                }

                let normalizedDay = calendar.startOfDay(for: day)

                return RecoveryTrendDay(
                    date: normalizedDay,
                    sleepDuration: sleepByDay[normalizedDay],
                    hrvMilliseconds: hrvByDay[normalizedDay],
                    restingHeartRate:
                        restingByDay[normalizedDay],
                    respiratoryRate:
                        respiratoryByDay[normalizedDay],
                    trainingMinutes:
                        trainingMinutesByDay[normalizedDay] ?? 0
                )
            }

        let acuteStart = calendar.date(
            byAdding: .day,
            value: -6,
            to: today
        ) ?? today.addingTimeInterval(-6 * 86_400)

        let acuteWorkouts = chronicWorkouts
            .filter { $0.startDate >= acuteStart }

        let acuteMinutes = acuteWorkouts.reduce(0) {
            $0 + ($1.duration / 60)
        }

        var strengthMinutes = 0.0
        var runningMinutes = 0.0
        var walkingMinutes = 0.0
        var otherMinutes = 0.0
        var latestStrengthAt: Date?
        var latestRunningAt: Date?
        var latestWalkingAt: Date?

        for workout in acuteWorkouts {
            let minutes = max(workout.duration / 60, 0)
            let activityDate = workout.endDate

            switch workout.workoutActivityType {
            case .running:
                runningMinutes += minutes
                if latestRunningAt.map({ activityDate > $0 }) ?? true {
                    latestRunningAt = activityDate
                }

            case .walking, .hiking:
                walkingMinutes += minutes
                if latestWalkingAt.map({ activityDate > $0 }) ?? true {
                    latestWalkingAt = activityDate
                }

            case .traditionalStrengthTraining,
                 .functionalStrengthTraining:
                strengthMinutes += minutes
                if latestStrengthAt.map({ activityDate > $0 }) ?? true {
                    latestStrengthAt = activityDate
                }

            default:
                otherMinutes += minutes
            }
        }

        let chronicMinutes = chronicWorkouts.reduce(0) {
            $0 + ($1.duration / 60)
        }

        let chronicWeeklyAverage =
            chronicMinutes > 0
                ? chronicMinutes / 4
                : nil

        let snapshot = RecoveryTrendSnapshot(
            days: trendDays,
            trainingLoad: RecoveryTrainingLoadSummary(
                acuteMinutes: acuteMinutes,
                chronicWeeklyAverageMinutes:
                    chronicWeeklyAverage,
                strengthMinutes: strengthMinutes,
                runningMinutes: runningMinutes,
                walkingMinutes: walkingMinutes,
                otherMinutes: otherMinutes,
                latestStrengthAt: latestStrengthAt,
                latestRunningAt: latestRunningAt,
                latestWalkingAt: latestWalkingAt
            )
        )

        recoveryTrendCache[resolvedDays] = (
            snapshot,
            Date()
        )
        return snapshot
    }

    func trophySnapshot() async throws -> TrophyHealthSnapshot {
        if let cached = trophySnapshotCache,
           Date().timeIntervalSince(cached.generatedAt) < 900 {
            return cached.snapshot
        }

        let workouts = try await fetchAllWorkoutsCached()
            .sorted { $0.startDate < $1.startDate }

        let workoutThresholds = [10, 50, 100, 500, 1_000]
        var workoutCountReachedAt: [Int: Date] = [:]

        for (index, workout) in workouts.enumerated() {
            let count = index + 1
            if workoutThresholds.contains(count) {
                workoutCountReachedAt[count] = workout.endDate
            }
        }

        let calendar = Calendar.current
        let dayDensityThresholds = [2, 3, 4]
        let weekDensityThresholds = [5, 7, 10]
        var workoutsByDay: [Date: Int] = [:]
        var workoutsByWeek: [String: Int] = [:]
        var workoutDayDensityReachedAt: [Int: Date] = [:]
        var workoutWeekDensityReachedAt: [Int: Date] = [:]
        var maxWorkoutsInDay = 0
        var maxWorkoutsInWeek = 0

        for workout in workouts {
            let day =
                calendar.startOfDay(
                    for: workout.startDate
                )
            let dayCount =
                (workoutsByDay[day] ?? 0) + 1
            workoutsByDay[day] = dayCount
            maxWorkoutsInDay =
                max(
                    maxWorkoutsInDay,
                    dayCount
                )

            for threshold in dayDensityThresholds
            where workoutDayDensityReachedAt[threshold] == nil &&
                    dayCount >= threshold {
                workoutDayDensityReachedAt[threshold] =
                    workout.endDate
            }

            let weekYear =
                calendar.component(
                    .yearForWeekOfYear,
                    from: workout.startDate
                )
            let week =
                calendar.component(
                    .weekOfYear,
                    from: workout.startDate
                )
            let weekKey =
                "\(weekYear)-\(week)"
            let weekCount =
                (workoutsByWeek[weekKey] ?? 0) + 1
            workoutsByWeek[weekKey] =
                weekCount
            maxWorkoutsInWeek =
                max(
                    maxWorkoutsInWeek,
                    weekCount
                )

            for threshold in weekDensityThresholds
            where workoutWeekDensityReachedAt[threshold] == nil &&
                    weekCount >= threshold {
                workoutWeekDensityReachedAt[threshold] =
                    workout.endDate
            }
        }

        let runThresholds = [
            25_000,
            100_000,
            500_000,
            1_000_000,
            2_500_000,
            5_000_000,
            10_000_000
        ]
        var runningDistanceReachedAt: [Int: Date] = [:]
        var cumulativeRunDistance = 0.0
        var runningWorkoutCount = 0
        var runningWorkoutCountReachedAt: [Int: Date] = [:]
        let runningWorkoutThresholds = [250, 500]
        var longestRunMeters = 0.0
        var firstFiveKDate: Date?
        var firstTenKDate: Date?
        var firstHalfMarathonDate: Date?
        var firstMarathonDate: Date?
        var firstHalfMarathonEvidence:
            PrestigeRunEvidence?
        var firstMarathonEvidence:
            PrestigeRunEvidence?
        var firstThirtyKRunEvidence:
            PrestigeRunEvidence?
        var firstFiftyKRunEvidence:
            PrestigeRunEvidence?

        for workout in workouts where workout.workoutActivityType == .running {
            runningWorkoutCount += 1

            for threshold in runningWorkoutThresholds
            where runningWorkoutCountReachedAt[threshold] == nil &&
                    runningWorkoutCount >= threshold {
                runningWorkoutCountReachedAt[threshold] =
                    workout.endDate
            }

            let distance = workout.athlthDistanceMeters ?? 0
            guard distance > 0 else { continue }

            longestRunMeters = max(longestRunMeters, distance)
            cumulativeRunDistance += distance

            if firstFiveKDate == nil, distance >= 5_000 {
                firstFiveKDate = workout.endDate
            }

            if firstTenKDate == nil, distance >= 10_000 {
                firstTenKDate = workout.endDate
            }

            let wasUserEntered: Bool = {
                guard let value =
                        workout.metadata?[
                            HKMetadataKeyWasUserEntered
                        ]
                else {
                    return false
                }

                if let number =
                    value as? NSNumber {
                    return number.boolValue
                }

                if let bool =
                    value as? Bool {
                    return bool
                }

                return false
            }()

            let sourceBundleIdentifier =
                workout
                    .sourceRevision
                    .source
                    .bundleIdentifier
            let sourceName =
                workout
                    .sourceRevision
                    .source
                    .name

            let locationType =
                workout
                    .workoutActivities
                    .first?
                    .workoutConfiguration
                    .locationType
            let isIndoor: Bool?
            switch locationType {
            case .indoor:
                isIndoor = true
            case .outdoor:
                isIndoor = false
            default:
                isIndoor = nil
            }

            let prestigeEvidence =
                PrestigeRunEvidence(
                    workoutID:
                        workout.uuid,
                    distanceMeters:
                        distance,
                    durationSeconds:
                        workout.duration,
                    startedAt:
                        workout.startDate,
                    endedAt:
                        workout.endDate,
                    sourceBundleIdentifier:
                        sourceBundleIdentifier,
                    sourceName:
                        sourceName,
                    isIndoor:
                        isIndoor,
                    wasUserEntered:
                        wasUserEntered
                )

            let prestigeAverageSpeed =
                workout.duration > 0
                    ? distance /
                        workout.duration
                    : .infinity
            let prestigeEligible =
                !wasUserEntered &&
                workout.duration >= 20 * 60 &&
                prestigeAverageSpeed >= 0.4 &&
                prestigeAverageSpeed <= 8.0 &&
                !sourceBundleIdentifier
                    .isEmpty &&
                workout.endDate <=
                    Date().addingTimeInterval(
                        5 * 60
                    )

            // Gold running trophies require one real HealthKit workout.
            // Manually entered or implausible workout records are excluded.
            if firstHalfMarathonDate == nil,
               distance >= 21_097.5,
               prestigeEligible {
                firstHalfMarathonDate =
                    workout.endDate
                firstHalfMarathonEvidence =
                    prestigeEvidence
            }

            if firstThirtyKRunEvidence == nil,
               distance >= 30_000,
               prestigeEligible {
                firstThirtyKRunEvidence =
                    prestigeEvidence
            }

            if firstMarathonDate == nil,
               distance >= 42_195,
               prestigeEligible {
                firstMarathonDate =
                    workout.endDate
                firstMarathonEvidence =
                    prestigeEvidence
            }

            if firstFiftyKRunEvidence == nil,
               distance >= 50_000,
               prestigeEligible {
                firstFiftyKRunEvidence =
                    prestigeEvidence
            }

            for threshold in runThresholds
            where runningDistanceReachedAt[threshold] == nil &&
                    cumulativeRunDistance >= Double(threshold) {
                runningDistanceReachedAt[threshold] = workout.endDate
            }
        }

        let walkDistanceThresholds = [
            10_000,
            50_000,
            250_000,
            2_500_000
        ]
        let walkSessionThresholds = [
            10,
            50,
            150,
            1_000
        ]
        var walkingDistanceReachedAt: [Int: Date] = [:]
        var walkingWorkoutCountReachedAt: [Int: Date] = [:]
        var cumulativeWalkDistance = 0.0
        var walkingWorkoutCount = 0
        var longestWalkMeters = 0.0
        var firstFiveKWalkDate: Date?
        var firstTenKWalkDate: Date?

        for workout in workouts where workout.workoutActivityType == .walking {
            walkingWorkoutCount += 1

            for threshold in walkSessionThresholds
            where walkingWorkoutCountReachedAt[threshold] == nil &&
                    walkingWorkoutCount >= threshold {
                walkingWorkoutCountReachedAt[threshold] =
                    workout.endDate
            }

            let distance =
                workout.athlthDistanceMeters ?? 0
            guard distance > 0 else {
                continue
            }

            longestWalkMeters =
                max(
                    longestWalkMeters,
                    distance
                )
            cumulativeWalkDistance +=
                distance

            if firstFiveKWalkDate == nil,
               distance >= 5_000 {
                firstFiveKWalkDate =
                    workout.endDate
            }

            if firstTenKWalkDate == nil,
               distance >= 10_000 {
                firstTenKWalkDate =
                    workout.endDate
            }

            for threshold in walkDistanceThresholds
            where walkingDistanceReachedAt[threshold] == nil &&
                    cumulativeWalkDistance >= Double(threshold) {
                walkingDistanceReachedAt[threshold] =
                    workout.endDate
            }
        }

        let workoutDays = Array(
            Set(workouts.map { calendar.startOfDay(for: $0.startDate) })
        )
        .sorted()

        let streakThresholds = [3, 7, 14, 90]
        var workoutStreakReachedAt: [Int: Date] = [:]
        var longestStreak = 0
        var currentStreak = 0
        var previousDay: Date?

        for day in workoutDays {
            if let previousDay,
               calendar.dateComponents([.day], from: previousDay, to: day).day == 1 {
                currentStreak += 1
            } else {
                currentStreak = 1
            }

            longestStreak = max(longestStreak, currentStreak)

            for threshold in streakThresholds
            where workoutStreakReachedAt[threshold] == nil &&
                    currentStreak >= threshold {
                workoutStreakReachedAt[threshold] = day
            }

            previousDay = day
        }

        let historicalStart = calendar.date(
            from: DateComponents(year: 2000, month: 1, day: 1)
        ) ?? Date(timeIntervalSince1970: 946_684_800)
        let sleepByDay = try await sleepDurationsByWakeDay(
            startDate: historicalStart,
            endDate: Date()
        )
        let qualifyingSleepDays = sleepByDay
            .filter { $0.value >= 7 * 3_600 }
            .map(\.key)
            .sorted()

        let sleepThresholds = [
            7,
            30,
            100,
            730
        ]
        var qualifyingSleepNightsReachedAt: [Int: Date] = [:]

        for (index, day) in qualifyingSleepDays.enumerated() {
            let count = index + 1
            if sleepThresholds.contains(count) {
                qualifyingSleepNightsReachedAt[count] = day
            }
        }

        let snapshot = TrophyHealthSnapshot(
            workoutCount: workouts.count,
            workoutCountReachedAt: workoutCountReachedAt,
            totalRunningDistanceMeters: cumulativeRunDistance,
            runningDistanceReachedAt: runningDistanceReachedAt,
            runningWorkoutCount:
                runningWorkoutCount,
            runningWorkoutCountReachedAt:
                runningWorkoutCountReachedAt,
            maxWorkoutsInDay:
                maxWorkoutsInDay,
            workoutDayDensityReachedAt:
                workoutDayDensityReachedAt,
            maxWorkoutsInWeek:
                maxWorkoutsInWeek,
            workoutWeekDensityReachedAt:
                workoutWeekDensityReachedAt,
            longestRunMeters: longestRunMeters,
            firstFiveKDate: firstFiveKDate,
            firstTenKDate: firstTenKDate,
            firstHalfMarathonDate: firstHalfMarathonDate,
            firstMarathonDate: firstMarathonDate,
            firstHalfMarathonEvidence:
                firstHalfMarathonEvidence,
            firstMarathonEvidence:
                firstMarathonEvidence,
            firstThirtyKRunEvidence:
                firstThirtyKRunEvidence,
            firstFiftyKRunEvidence:
                firstFiftyKRunEvidence,
            walkingWorkoutCount: walkingWorkoutCount,
            walkingWorkoutCountReachedAt:
                walkingWorkoutCountReachedAt,
            totalWalkingDistanceMeters:
                cumulativeWalkDistance,
            walkingDistanceReachedAt:
                walkingDistanceReachedAt,
            longestWalkMeters:
                longestWalkMeters,
            firstFiveKWalkDate:
                firstFiveKWalkDate,
            firstTenKWalkDate:
                firstTenKWalkDate,
            longestWorkoutStreakDays: longestStreak,
            workoutStreakReachedAt: workoutStreakReachedAt,
            qualifyingSleepNights: qualifyingSleepDays.count,
            qualifyingSleepNightsReachedAt: qualifyingSleepNightsReachedAt
        )

        let generatedAt = Date()
        trophySnapshotCache = (
            snapshot,
            generatedAt
        )

        let latestWorkout = workouts.last
        trophyCacheLatestWorkoutID =
            latestWorkout?.uuid
        trophyCacheLatestWorkoutEnd =
            latestWorkout?.endDate
        trophyCacheLatestSleepDuration =
            sleep.totalAsleep

        let diskCache = TrophySnapshotDiskCache(
            snapshot: snapshot,
            generatedAt: generatedAt,
            latestWorkoutID: latestWorkout?.uuid,
            latestWorkoutEnd: latestWorkout?.endDate,
            latestSleepDuration: sleep.totalAsleep
        )

        if let data = try? JSONEncoder().encode(
            diskCache
        ) {
            UserDefaults.standard.set(
                data,
                forKey: trophySnapshotDiskKey
            )
        }

        return snapshot
    }

    func challengeRunningEvidence(
        for result: WatchWorkoutResult,
        rules: ATHLTHChallengeRules
    ) async -> ChallengeRunningEvidence {
        let elapsedDuration = max(
            result.endedAt.timeIntervalSince(
                result.startedAt
            ),
            0
        )
        let movingDuration = max(result.duration, 0)
        let selectedDuration =
            rules.timeBasis == .elapsed
                ? elapsedDuration
                : movingDuration

        var route: [CLLocation] = []
        var workout: HKWorkout?

        if let workoutUUID =
                result.healthKitWorkoutUUID,
           let resolvedWorkout =
                try? await workoutForChallenge(
                    uuid: workoutUUID
                ) {
            workout = resolvedWorkout
            route =
                (try? await fetchRoute(
                    for: resolvedWorkout
                )) ?? []
        }

        let isIndoor =
            workout?.workoutActivities.first?
                .workoutConfiguration
                .locationType == .indoor
        let treadmillAllowed =
            rules.allowTreadmill ?? false

        if isIndoor &&
            !treadmillAllowed {
            return challengeEvidenceFailure(
                result: result,
                duration: selectedDuration,
                routeMatch: nil,
                reason:
                    "Indoor treadmill runs are not allowed for this challenge."
            )
        }

        if isIndoor &&
            rules.gpsRequired {
            return challengeEvidenceFailure(
                result: result,
                duration: selectedDuration,
                routeMatch: nil,
                reason:
                    "GPS verification is required, so an indoor treadmill run cannot qualify."
            )
        }

        let routeNeeded =
            rules.gpsRequired ||
            rules.route != nil ||
            rules.scoring == .farthestInTime

        if routeNeeded &&
            route.count < 2 {
            return challengeEvidenceFailure(
                result: result,
                duration: selectedDuration,
                routeMatch: nil,
                reason:
                    "No qualifying GPS route was available for this attempt."
            )
        }

        var routeMatch: Double?

        if let requiredRoute = rules.route {
            routeMatch = routeMatchPercent(
                actualLocations: route,
                referenceCoordinates:
                    requiredRoute.coordinates
            )

            let requiredMatch =
                rules.minimumRouteMatchPercent ??
                90

            if (routeMatch ?? 0) <
                requiredMatch {
                return ChallengeRunningEvidence(
                    startedAt: result.startedAt,
                    endedAt: result.endedAt,
                    durationSeconds:
                        selectedDuration,
                    distanceMeters:
                        result.distanceMeters,
                    routeMatchPercent:
                        routeMatch,
                    score: 0,
                    detail: String(
                        format:
                            "%.0f%% route match",
                        routeMatch ?? 0
                    ),
                    isEligible: false,
                    ineligibilityReason: String(
                        format:
                            "Route match %.0f%% · required %.0f%%.",
                        routeMatch ?? 0,
                        requiredMatch
                    )
                )
            }

            if let tolerance =
                    rules.startFinishToleranceMeters,
               tolerance > 0,
               !challengeEndpointsMatch(
                   actualLocations: route,
                   referenceCoordinates:
                       requiredRoute.coordinates,
                   toleranceMeters: tolerance,
                   direction:
                       rules.routeDirection ??
                       .sameDirection
               ) {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason:
                        "Start or finish was outside the allowed \(Int(tolerance)) m tolerance."
                )
            }
        }

        switch rules.scoring {
        case .fastestDistance:
            guard let target =
                    rules.targetDistanceMeters,
                  target > 0
            else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason:
                        "This challenge has no valid target distance."
                )
            }

            if let tolerancePercent =
                    rules.distanceTolerancePercent {
                let tolerance =
                    target *
                    max(
                        min(
                            tolerancePercent,
                            25
                        ),
                        0
                    ) /
                    100
                let lower =
                    max(target - tolerance, 0)
                let upper =
                    target + tolerance

                guard
                    result.distanceMeters >= lower &&
                    result.distanceMeters <= upper
                else {
                    return challengeEvidenceFailure(
                        result: result,
                        duration:
                            selectedDuration,
                        routeMatch:
                            routeMatch,
                        reason: String(
                            format:
                                "%.2f km completed · allowed %.2f–%.2f km.",
                            result.distanceMeters /
                                1_000,
                            lower / 1_000,
                            upper / 1_000
                        )
                    )
                }
            } else {
                // Legacy challenges keep the original minimum-distance
                // behaviour unless they were created with tolerance rules.
                guard result.distanceMeters >=
                        target
                else {
                    return challengeEvidenceFailure(
                        result: result,
                        duration:
                            selectedDuration,
                        routeMatch:
                            routeMatch,
                        reason: String(
                            format:
                                "%.2f km completed · %.2f km required.",
                            result.distanceMeters /
                                1_000,
                            target / 1_000
                        )
                    )
                }
            }

            let qualifyingDuration:
                TimeInterval

            if route.count >= 2 {
                guard let segmentDuration =
                        fastestSegmentDuration(
                            in: route,
                            targetDistance: target
                        )
                else {
                    return challengeEvidenceFailure(
                        result: result,
                        duration:
                            selectedDuration,
                        routeMatch:
                            routeMatch,
                        reason:
                            "ATHLTH could not verify the target distance from the GPS track."
                    )
                }

                qualifyingDuration =
                    segmentDuration
            } else if
                !rules.gpsRequired {
                // Apple Health/Watch distance can qualify without a route
                // when GPS is optional. This is what enables treadmill use.
                qualifyingDuration =
                    selectedDuration
            } else {
                return challengeEvidenceFailure(
                    result: result,
                    duration:
                        selectedDuration,
                    routeMatch:
                        routeMatch,
                    reason:
                        "GPS verification is required for this attempt."
                )
            }

            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds:
                    qualifyingDuration,
                distanceMeters: target,
                routeMatchPercent:
                    routeMatch,
                score: qualifyingDuration,
                detail:
                    "\(challengeClock(qualifyingDuration)) · \(String(format: "%.2f", target / 1_000)) km",
                isEligible: true,
                ineligibilityReason: nil
            )

        case .fastestRoute:
            guard rules.route != nil else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason:
                        "A specific route is required for this challenge."
                )
            }

            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds:
                    selectedDuration,
                distanceMeters:
                    result.distanceMeters,
                routeMatchPercent:
                    routeMatch,
                score: selectedDuration,
                detail:
                    "\(challengeClock(selectedDuration)) · \(String(format: "%.0f%%", routeMatch ?? 0)) route match",
                isEligible: true,
                ineligibilityReason: nil
            )

        case .farthestInTime:
            guard let targetDuration =
                    rules.targetDurationSeconds,
                  targetDuration > 0
            else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason:
                        "This challenge has no valid time target."
                )
            }

            guard let distance =
                    maximumRouteDistance(
                        in: route,
                        within: targetDuration
                    )
            else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason:
                        "ATHLTH could not verify distance inside the required time window."
                )
            }

            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds:
                    targetDuration,
                distanceMeters: distance,
                routeMatchPercent:
                    routeMatch,
                score: distance,
                detail:
                    "\(String(format: "%.2f km", distance / 1_000)) in \(challengeClock(targetDuration))",
                isEligible: true,
                ineligibilityReason: nil
            )

        case .mostDistance:
            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds:
                    selectedDuration,
                distanceMeters:
                    result.distanceMeters,
                routeMatchPercent:
                    routeMatch,
                score:
                    result.distanceMeters,
                detail: String(
                    format:
                        "%.2f km",
                    result.distanceMeters /
                        1_000
                ),
                isEligible: true,
                ineligibilityReason: nil
            )

        case .heaviestWeight,
                .mostReps,
                .exerciseVolume,
                .workoutVolume,
                .heartRateZoneTime:
            return challengeEvidenceFailure(
                result: result,
                duration: selectedDuration,
                routeMatch: routeMatch,
                reason:
                    "This is not a running scoring rule."
            )
        }
    }

    func challengeHeartRateEvidence(
        workoutID: UUID,
        rules: ATHLTHChallengeRules,
        maximumHeartRateBPM: Int
    ) async -> ChallengeHeartRateEvidence? {
        guard maximumHeartRateBPM >= 80,
              maximumHeartRateBPM <= 250,
              let workout =
                try? await workoutForChallenge(
                    uuid: workoutID
                ),
              let type =
                HKObjectType.quantityType(
                    forIdentifier: .heartRate
                )
        else {
            return nil
        }

        let predicate =
            HKQuery.predicateForObjects(from: workout)
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        let samples: [HKQuantitySample]

        do {
            samples =
                try await withCheckedThrowingContinuation {
                    (
                        continuation:
                            CheckedContinuation<
                                [HKQuantitySample],
                                Error
                            >
                    ) in
                    let query = HKSampleQuery(
                        sampleType: type,
                        predicate: predicate,
                        limit: HKObjectQueryNoLimit,
                        sortDescriptors: [sort]
                    ) { _, values, error in
                        if let error {
                            continuation.resume(
                                throwing: error
                            )
                        } else {
                            continuation.resume(
                                returning:
                                    values
                                        as? [HKQuantitySample]
                                        ?? []
                            )
                        }
                    }

                    healthStore.execute(query)
                }
        } catch {
            return nil
        }

        guard samples.count >= 2 else {
            return nil
        }

        let unit =
            HKUnit.count()
                .unitDivided(by: .minute())
        let zone = min(
            max(rules.heartRateZone ?? 5, 1),
            5
        )

        let lowerFraction: Double
        let upperFraction: Double?

        switch zone {
        case 1:
            lowerFraction = 0.50
            upperFraction = 0.60
        case 2:
            lowerFraction = 0.60
            upperFraction = 0.70
        case 3:
            lowerFraction = 0.70
            upperFraction = 0.80
        case 4:
            lowerFraction = 0.80
            upperFraction = 0.90
        default:
            lowerFraction = 0.90
            upperFraction = nil
        }

        let minimumBPM =
            Double(maximumHeartRateBPM) *
            lowerFraction
        let maximumBPM =
            upperFraction.map {
                Double(maximumHeartRateBPM) * $0
            }

        let values = samples.compactMap { sample -> Double? in
            guard let value =
                    Self.safeDoubleValue(
                        sample.quantity,
                        unit: unit
                    ),
                  value.isFinite,
                  value >= 30,
                  value <= 260
            else {
                return nil
            }

            return value
        }

        guard !values.isEmpty else {
            return nil
        }

        var zoneSeconds: TimeInterval = 0
        var coveredSeconds: TimeInterval = 0

        for index in samples.indices {
            guard let bpm =
                    Self.safeDoubleValue(
                        samples[index].quantity,
                        unit: unit
                    ),
                  bpm.isFinite,
                  bpm >= 30,
                  bpm <= 260
            else {
                continue
            }

            let sampleDate =
                samples[index].startDate
            let nextDate: Date

            if index + 1 < samples.count {
                nextDate =
                    samples[index + 1].startDate
            } else {
                nextDate = min(
                    workout.endDate,
                    sampleDate.addingTimeInterval(5)
                )
            }

            // Cap every sample interval so sensor dropouts cannot
            // artificially add long blocks of zone time.
            let interval = min(
                max(
                    nextDate.timeIntervalSince(
                        sampleDate
                    ),
                    0
                ),
                15
            )

            guard interval > 0 else {
                continue
            }

            coveredSeconds += interval

            let isInZone =
                bpm >= minimumBPM &&
                (
                    maximumBPM == nil ||
                    bpm < maximumBPM!
                )

            if isInZone {
                zoneSeconds += interval
            }
        }

        // Require enough real HR coverage to treat the workout as
        // verified rather than extrapolating from a handful of samples.
        guard coveredSeconds >= 30 else {
            return nil
        }

        let average =
            values.reduce(0, +) /
            Double(values.count)
        let peak = values.max()

        var detail =
            "\(challengeClock(zoneSeconds)) in Zone \(zone)"

        if let peak {
            detail +=
                " · peak \(Int(peak.rounded())) bpm"
        }

        return ChallengeHeartRateEvidence(
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            zone: zone,
            zoneTimeSeconds: zoneSeconds,
            averageHeartRateBPM: average,
            peakHeartRateBPM: peak,
            score: zoneSeconds,
            detail: detail,
            isEligible: true,
            ineligibilityReason: nil
        )
    }

    func groupChallengeRouteMatchPercent(
        workoutID: UUID,
        referenceCoordinates: [RouteCoordinate],
        toleranceMeters: Double
    ) async -> Double? {
        guard referenceCoordinates.count >= 2,
              let workout = try? await workoutForChallenge(
                uuid: workoutID
              ),
              let route = try? await fetchRoute(
                for: workout
              ),
              route.count >= 2
        else {
            return nil
        }

        let actual = route.filter {
            $0.horizontalAccuracy >= 0 &&
            $0.horizontalAccuracy <= 65
        }

        guard actual.count >= 2 else {
            return nil
        }

        let references = referenceCoordinates.map {
            CLLocation(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }

        let sampleStep = max(
            references.count / 100,
            1
        )
        let samples = stride(
            from: 0,
            to: references.count,
            by: sampleStep
        ).map { references[$0] }

        guard !samples.isEmpty else {
            return nil
        }

        let tolerance = min(
            max(toleranceMeters, 25),
            1_000
        )
        let matched = samples.reduce(0) {
            count,
            reference in

            let nearest = actual.lazy
                .map {
                    $0.distance(from: reference)
                }
                .min()
                ?? .greatestFiniteMagnitude

            return count +
                (nearest <= tolerance ? 1 : 0)
        }

        return Double(matched) /
            Double(samples.count) *
            100
    }

    func groupChallengeFastestSegmentDuration(
        workoutID: UUID,
        targetDistanceMeters: Double
    ) async -> TimeInterval? {
        guard targetDistanceMeters > 0,
              let workout = try? await workoutForChallenge(
                uuid: workoutID
              ),
              let route = try? await fetchRoute(
                for: workout
              ),
              route.count >= 2
        else {
            return nil
        }

        return fastestSegmentDuration(
            in: route,
            targetDistance: targetDistanceMeters
        )
    }

    func profilePerformanceStats(
        forceRefresh: Bool = false
    ) async throws -> ProfilePerformanceStats {
        if !forceRefresh,
           let cached = profilePerformanceCache,
           Date().timeIntervalSince(cached.generatedAt) < 600 {
            return cached.stats
        }

        let allWorkouts = try await fetchAllWorkoutsCached(
            forceRefresh: forceRefresh
        )
        let workoutsByDate = allWorkouts.sorted { $0.startDate < $1.startDate }

        let longestWorkout = allWorkouts.max { lhs, rhs in
            lhs.duration < rhs.duration
        }

        let longestDistanceWorkout = allWorkouts
            .filter { ($0.athlthDistanceMeters ?? 0) > 0 }
            .max { lhs, rhs in
                (lhs.athlthDistanceMeters ?? 0) <
                (rhs.athlthDistanceMeters ?? 0)
            }

        let runningWorkouts = workoutsByDate.filter {
            $0.workoutActivityType == .running &&
            ($0.athlthDistanceMeters ?? 0) > 0
        }

        let longestRun = runningWorkouts.max { lhs, rhs in
            (lhs.athlthDistanceMeters ?? 0) <
            (rhs.athlthDistanceMeters ?? 0)
        }

        let totalRunningDistance = runningWorkouts.reduce(0.0) { partial, workout in
            partial + (workout.athlthDistanceMeters ?? 0)
        }

        let runningPerformance =
            await runningRoutePerformanceEntries(
                for: runningWorkouts
            )

        func bestRecord(
            distanceMeters: Double,
            duration: (RunningRoutePerformanceEntry) -> TimeInterval?
        ) -> TimedDistancePerformanceRecord? {
            runningPerformance
                .compactMap { entry -> TimedDistancePerformanceRecord? in
                    guard let value = duration(entry) else {
                        return nil
                    }

                    return TimedDistancePerformanceRecord(
                        distanceMeters: distanceMeters,
                        duration: value,
                        date: entry.startDate,
                        workoutID: entry.workoutID
                    )
                }
                .min { $0.duration < $1.duration }
        }

        let fastestOneK = bestRecord(
            distanceMeters: 1_000,
            duration: { $0.fastestOneK }
        )
        let fastestFiveK = bestRecord(
            distanceMeters: 5_000,
            duration: { $0.fastestFiveK }
        )
        let fastestMarathon = bestRecord(
            distanceMeters: 42_195,
            duration: { $0.fastestMarathon }
        )

        let stats = ProfilePerformanceStats(
            fastestOneKilometer: fastestOneK,
            fastestFiveKilometers: fastestFiveK,
            fastestMarathon: fastestMarathon,
            longestWorkoutDuration: longestWorkout?.duration,
            longestWorkoutDate: longestWorkout?.startDate,
            longestWorkoutActivity: longestWorkout.map {
                WorkoutActivity(healthKitType: $0.workoutActivityType)
            },
            longestWorkoutDistanceMeters: longestDistanceWorkout?.athlthDistanceMeters,
            longestWorkoutDistanceDate: longestDistanceWorkout?.startDate,
            longestWorkoutDistanceActivity: longestDistanceWorkout.map {
                WorkoutActivity(healthKitType: $0.workoutActivityType)
            },
            longestRunMeters: longestRun?.athlthDistanceMeters,
            longestRunDate: longestRun?.startDate,
            totalWorkoutCount: allWorkouts.count,
            totalTrainingDuration: allWorkouts.reduce(0) { $0 + $1.duration },
            totalRunningDistanceMeters: totalRunningDistance
        )

        profilePerformanceCache = (stats, Date())
        return stats
    }

    func performanceWorkoutHistory(
        forceRefresh: Bool = false
    ) async throws -> [WorkoutSummary] {
        let workouts =
            try await fetchAllWorkoutsCached(
                forceRefresh:
                    forceRefresh
            )

        return workouts.map(
            WorkoutSummary.init
        )
    }

    func personalRecords(
        forceRefresh: Bool = false
    ) async throws -> [HealthPersonalRecord] {
        if !forceRefresh,
           let cached = personalRecordsCache,
           Date().timeIntervalSince(cached.generatedAt) < 600 {
            return cached.records
        }

        let workouts = try await fetchAllWorkoutsCached(
            forceRefresh: forceRefresh
        )
        var records: [HealthPersonalRecord] = []

        if let workout = workouts
            .filter({ $0.workoutActivityType == .running && $0.athlthDistanceMeters != nil })
            .max(by: {
                ($0.athlthDistanceMeters ?? 0) <
                ($1.athlthDistanceMeters ?? 0)
            }),
           let distance = workout.athlthDistanceMeters,
           distance > 0 {
            records.append(
                HealthPersonalRecord(
                    kind: .longestRun,
                    value: distance,
                    date: workout.startDate
                )
            )
        }

        let timedRunningTargets: [(HealthPersonalRecordKind, Double)] = [
            (.fastest1K, 1_000),
            (.fastestMile, 1_609.344),
            (.fastest5K, 5_000),
            (.fastest10K, 10_000),
            (.fastestHalfMarathon, 21_097.5),
            (.fastestMarathon, 42_195)
        ]

        var fastestRunningRecords:
            [HealthPersonalRecordKind: (duration: TimeInterval, date: Date)] = [:]

        let runningWorkouts = workouts.filter {
            $0.workoutActivityType == .running &&
            ($0.athlthDistanceMeters ?? 0) >= 1_000
        }

        let runningPerformance =
            await runningRoutePerformanceEntries(
                for: runningWorkouts
            )

        for entry in runningPerformance {
            for (kind, _) in timedRunningTargets {
                guard let duration =
                        entry.duration(for: kind)
                else {
                    continue
                }

                if let existing =
                        fastestRunningRecords[kind] {
                    if duration < existing.duration {
                        fastestRunningRecords[kind] = (
                            duration,
                            entry.startDate
                        )
                    }
                } else {
                    fastestRunningRecords[kind] = (
                        duration,
                        entry.startDate
                    )
                }
            }
        }

        for (kind, _) in timedRunningTargets {
            guard let record = fastestRunningRecords[kind] else {
                continue
            }

            records.append(
                HealthPersonalRecord(
                    kind: kind,
                    value: record.duration,
                    date: record.date
                )
            )
        }

        if let workout = workouts
            .filter({ $0.workoutActivityType == .cycling && $0.athlthDistanceMeters != nil })
            .max(by: {
                ($0.athlthDistanceMeters ?? 0) <
                ($1.athlthDistanceMeters ?? 0)
            }),
           let distance = workout.athlthDistanceMeters,
           distance > 0 {
            records.append(
                HealthPersonalRecord(
                    kind: .longestRide,
                    value: distance,
                    date: workout.startDate
                )
            )
        }

        if let workout = workouts
            .filter({
                ($0.workoutActivityType == .walking || $0.workoutActivityType == .hiking) &&
                $0.athlthDistanceMeters != nil
            })
            .max(by: {
                ($0.athlthDistanceMeters ?? 0) <
                ($1.athlthDistanceMeters ?? 0)
            }),
           let distance = workout.athlthDistanceMeters,
           distance > 0 {
            records.append(
                HealthPersonalRecord(
                    kind: .longestWalkOrHike,
                    value: distance,
                    date: workout.startDate
                )
            )
        }

        if let workout = workouts.max(by: { $0.duration < $1.duration }),
           workout.duration > 0 {
            records.append(
                HealthPersonalRecord(
                    kind: .longestWorkout,
                    value: workout.duration,
                    date: workout.startDate
                )
            )
        }

        if let activeEnergyType =
                HKObjectType.quantityType(
                    forIdentifier:
                        .activeEnergyBurned
                ),
           let record = workouts.compactMap({
                workout ->
                    (
                        workout: HKWorkout,
                        calories: Double
                    )? in

                guard let quantity =
                        workout.statistics(
                            for: activeEnergyType
                        )?.sumQuantity(),
                      let calories =
                        Self.safeDoubleValue(
                            quantity,
                            unit: .kilocalorie()
                        )
                else {
                    return nil
                }

                return (
                    workout: workout,
                    calories: calories
                )
           }).max(by: {
                $0.calories < $1.calories
           }),
           record.calories > 0 {
            records.append(
                HealthPersonalRecord(
                    kind: .mostActiveCalories,
                    value: record.calories,
                    date: record.workout.startDate
                )
            )
        }

        personalRecordsCache = (records, Date())
        return records
    }

    func goalEvidence(
        for rule: GoalAutomationRule,
        since startDate: Date
    ) async throws -> GoalAutomationEvidence? {
        let endDate = Date()

        switch rule.metric {
        case .bodyWeightKilograms, .bodyWeightChangeKilograms:
            guard let sample = try await latestQuantity(
                identifier: .bodyMass,
                unit: HKUnit.gramUnit(with: .kilo),
                startDate: startDate
            ) else {
                return nil
            }

            return GoalAutomationEvidence(
                currentValue: sample.0,
                evidenceDate: sample.1,
                description: String(format: "Apple Health weight: %.1f kg", sample.0)
            )

        case .singleWorkoutDistanceMeters:
            let workouts = try await fetchWorkouts(
                startDate: startDate,
                endDate: endDate
            )
            let candidates = workouts.filter { workoutMatchesGoalActivity($0, filter: rule.activity) }

            guard let workout = candidates
                .filter({ $0.athlthDistanceMeters != nil })
                .max(by: {
                    ($0.athlthDistanceMeters ?? 0) <
                    ($1.athlthDistanceMeters ?? 0)
                }),
                let distance = workout.athlthDistanceMeters
            else {
                return nil
            }

            return GoalAutomationEvidence(
                currentValue: distance,
                evidenceDate: workout.endDate,
                description: String(
                    format: "%@ workout: %.2f km",
                    rule.activity?.title ?? "Tracked",
                    distance / 1_000
                )
            )

        case .workoutCount:
            let workouts = try await fetchWorkouts(
                startDate: startDate,
                endDate: endDate
            )
            let candidates = workouts.filter { workoutMatchesGoalActivity($0, filter: rule.activity) }

            guard !candidates.isEmpty else { return nil }

            return GoalAutomationEvidence(
                currentValue: Double(candidates.count),
                evidenceDate: candidates.map(\.endDate).max() ?? endDate,
                description: "\(candidates.count) qualifying workouts since this goal started"
            )

        case .dailySteps:
            let values = try await dailyCumulativeQuantities(
                identifier: .stepCount,
                unit: .count(),
                startDate: startDate,
                endDate: endDate
            )

            guard let best = values.max(by: { $0.value < $1.value }) else {
                return nil
            }

            return GoalAutomationEvidence(
                currentValue: best.value,
                evidenceDate: best.key,
                description: "\(Int(best.value.rounded())) steps in one day"
            )

        case .sleepDurationSeconds:
            let values = try await sleepDurationsByWakeDay(
                startDate: startDate,
                endDate: endDate
            )

            guard let best = values.max(by: { $0.value < $1.value }) else {
                return nil
            }

            return GoalAutomationEvidence(
                currentValue: best.value,
                evidenceDate: best.key,
                description: best.value.shortDuration + " sleep"
            )

        case .strengthWeightKilograms, .manualProgress:
            return nil
        }
    }

    func refreshPersonalDetails() async {
        guard healthDataAvailable else {
            personalDetails = .empty
            return
        }

        var details = HealthProfileBasics.empty

        if let components = try? healthStore.dateOfBirthComponents() {
            details.dateOfBirth = Calendar.current.date(from: components)
        }

        if let biologicalSex = try? healthStore.biologicalSex().biologicalSex {
            switch biologicalSex {
            case .female:
                details.healthSex = .female
            case .male:
                details.healthSex = .male
            case .other:
                details.healthSex = .other
            case .notSet:
                details.healthSex = nil
            @unknown default:
                details.healthSex = nil
            }
        }

        details.heightCentimeters = try? await latestQuantity(
            identifier: .height,
            unit: HKUnit.meterUnit(with: .centi)
        )?.0

        details.weightKilograms = try? await latestQuantity(
            identifier: .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo)
        )?.0

        personalDetails = details
    }

    func authorizationRequestStatusDescription() async -> String {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: shareTypes,
                read: readTypes
            ) { status, error in
                if let error {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                    return
                }

                switch status {
                case .shouldRequest:
                    continuation.resume(returning: "Apple Health permission sheet should be shown.")
                case .unnecessary:
                    continuation.resume(returning: "Authorization has already been requested for this data set.")
                case .unknown:
                    continuation.resume(returning: "Authorization status is unknown.")
                @unknown default:
                    continuation.resume(returning: "Authorization returned a newer status.")
                }
            }
        }
    }

    func testBackgroundDelivery() async {
        backgroundDeliveryTestResult = "Testing…"

        let type = HKObjectType.workoutType()
        let result: String = await withCheckedContinuation { continuation in
            healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
                if success {
                    continuation.resume(returning: "Success: HealthKit accepted background delivery for workouts.")
                } else if let error {
                    continuation.resume(returning: "Not available in this signed build: \(error.localizedDescription)")
                } else {
                    continuation.resume(returning: "Background delivery was not enabled.")
                }
            }
        }

        backgroundDeliveryTestResult = result
    }

    func testWorkoutRouteCapability() async {
        routeCapabilityTestResult = "Searching recent run/walk workouts…"

        let candidates = workouts
            .filter { $0.activity == .running || $0.activity == .walking }
            .prefix(10)

        guard !candidates.isEmpty else {
            routeCapabilityTestResult = "No recent running or walking workout is loaded yet."
            return
        }

        for workout in candidates {
            let detail = await workoutDetail(for: workout)
            if !detail.route.isEmpty {
                routeCapabilityTestResult = "Route read succeeded: \(detail.route.count) GPS points found."
                return
            }
        }

        routeCapabilityTestResult = "HealthKit access works, but no GPS route was found in the recent run/walk workouts checked."
    }

    func workoutDetail(for summary: WorkoutSummary) async -> WorkoutDetail {
        await workoutDetail(for: summary.id)
    }

    func routePerformance(
        for summary: WorkoutSummary,
        against route: TrainingRoute
    ) async -> RoutePerformanceAnalysis? {
        guard summary.activity == .running ||
                summary.activity == .walking,
              route.coordinates.count >= 2
        else {
            return nil
        }

        let detail = await workoutDetail(for: summary)

        let actual = detail.route
            .filter {
                $0.horizontalAccuracy >= 0 &&
                $0.horizontalAccuracy <= 65
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard actual.count >= 2 else {
            return nil
        }

        let reference = route.coordinates.map {
            CLLocation(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }

        guard reference.count >= 2 else {
            return nil
        }

        let sampleStep = max(reference.count / 120, 1)
        let referenceSamples = stride(
            from: 0,
            to: reference.count,
            by: sampleStep
        )
        .map { reference[$0] }

        guard !referenceSamples.isEmpty else {
            return nil
        }

        let nearestDistances = referenceSamples.map { point in
            actual.lazy
                .map { $0.distance(from: point) }
                .min() ?? .greatestFiniteMagnitude
        }

        let toleranceMeters = 80.0
        let matchedCount = nearestDistances.filter {
            $0 <= toleranceMeters
        }.count

        let routeMatchPercent =
            Double(matchedCount) /
            Double(referenceSamples.count) *
            100

        let finiteDeviations = nearestDistances.filter(\.isFinite)
        guard !finiteDeviations.isEmpty else {
            return nil
        }

        let averageDeviation =
            finiteDeviations.reduce(0, +) /
            Double(finiteDeviations.count)
        let maxDeviation =
            finiteDeviations.max() ?? 0

        let actualStart = actual.first!
        let actualEnd = actual.last!
        let referenceStart = reference.first!
        let referenceEnd = reference.last!

        let forwardStart = actualStart.distance(from: referenceStart)
        let forwardEnd = actualEnd.distance(from: referenceEnd)
        let reverseStart = actualStart.distance(from: referenceEnd)
        let reverseEnd = actualEnd.distance(from: referenceStart)

        let useReverse =
            (reverseStart + reverseEnd) <
            (forwardStart + forwardEnd)

        return RoutePerformanceAnalysis(
            workoutID: summary.id,
            activity: summary.activity,
            startedAt: summary.startDate,
            durationSeconds: summary.duration,
            distanceMeters: summary.distanceMeters ?? 0,
            routeMatchPercent: min(max(routeMatchPercent, 0), 100),
            averageDeviationMeters: max(averageDeviation, 0),
            maxDeviationMeters: max(maxDeviation, 0),
            startDistanceMeters:
                useReverse ? reverseStart : forwardStart,
            endDistanceMeters:
                useReverse ? reverseEnd : forwardEnd
        )
    }

    func workoutRoute(for workoutID: UUID) async -> [CLLocation] {
        if let cached = workoutRouteCache[workoutID],
           Date().timeIntervalSince(cached.generatedAt) < 600 {
            return cached.route
        }

        let workout: HKWorkout?
        if let cachedWorkout = workoutObjects[workoutID] {
            workout = cachedWorkout
        } else {
            workout = try? await workoutForChallenge(uuid: workoutID)
            if let workout {
                workoutObjects[workout.uuid] = workout
            }
        }

        guard let workout else { return [] }
        let route = (try? await fetchRoute(for: workout)) ?? []
        workoutRouteCache[workoutID] = (route, Date())
        return route
    }

    func workoutDetail(for workoutID: UUID) async -> WorkoutDetail {
        let workout: HKWorkout?

        if let cached = workoutObjects[workoutID] {
            workout = cached
        } else {
            workout = try? await workoutForChallenge(uuid: workoutID)
            if let workout {
                workoutObjects[workout.uuid] = workout
            }
        }

        guard let workout else { return WorkoutDetail() }
        return await workoutDetail(for: workout)
    }

    private func workoutDetail(for workout: HKWorkout) async -> WorkoutDetail {
        async let routeTask = workoutRoute(
            for: workout.uuid
        )
        async let heartTask = fetchHeartRateStats(for: workout)
        async let stepsTask = workoutQuantity(
            identifier: .stepCount,
            unit: .count(),
            option: .cumulativeSum,
            workout: workout
        )
        async let runningSpeedTask = workoutQuantity(
            identifier: .runningSpeed,
            unit: .meter().unitDivided(by: .second()),
            option: .discreteAverage,
            workout: workout
        )
        async let runningPowerTask = workoutQuantity(
            identifier: .runningPower,
            unit: .watt(),
            option: .discreteAverage,
            workout: workout
        )
        async let strideTask = workoutQuantity(
            identifier: .runningStrideLength,
            unit: .meter(),
            option: .discreteAverage,
            workout: workout
        )
        async let verticalOscillationTask = workoutQuantity(
            identifier: .runningVerticalOscillation,
            unit: .meterUnit(with: .centi),
            option: .discreteAverage,
            workout: workout
        )
        async let groundContactTask = workoutQuantity(
            identifier: .runningGroundContactTime,
            unit: .secondUnit(with: .milli),
            option: .discreteAverage,
            workout: workout
        )
        async let cyclingSpeedTask = workoutQuantity(
            identifier: .cyclingSpeed,
            unit: .meter().unitDivided(by: .second()),
            option: .discreteAverage,
            workout: workout
        )
        async let cyclingPowerTask = workoutQuantity(
            identifier: .cyclingPower,
            unit: .watt(),
            option: .discreteAverage,
            workout: workout
        )
        async let swimmingStrokeTask = workoutQuantity(
            identifier: .swimmingStrokeCount,
            unit: .count(),
            option: .cumulativeSum,
            workout: workout
        )

        let route = await routeTask
        let heartStats = (try? await heartTask) ?? (nil, nil)
        let workoutLocation = storedWorkoutLocation(for: workout)

        return WorkoutDetail(
            route: route,
            workoutLocation: workoutLocation,
            averageHeartRate: heartStats.0,
            maxHeartRate: heartStats.1,
            stepCount: (try? await stepsTask) ?? nil,
            averageRunningSpeedMetersPerSecond: (try? await runningSpeedTask) ?? nil,
            averageRunningPowerWatts: (try? await runningPowerTask) ?? nil,
            averageRunningStrideLengthMeters: (try? await strideTask) ?? nil,
            averageRunningVerticalOscillationCentimeters: (try? await verticalOscillationTask) ?? nil,
            averageRunningGroundContactTimeMilliseconds: (try? await groundContactTask) ?? nil,
            averageCyclingSpeedMetersPerSecond: (try? await cyclingSpeedTask) ?? nil,
            averageCyclingPowerWatts: (try? await cyclingPowerTask) ?? nil,
            swimmingStrokeCount: (try? await swimmingStrokeTask) ?? nil
        )
    }

    func workoutAIInsightContext(
        for summary: WorkoutSummary,
        detail existingDetail: WorkoutDetail? = nil,
        maximumHeartRateBPM: Int?
    ) async -> WorkoutAIInsightContext {
        let detail: WorkoutDetail
        if let existingDetail {
            detail = existingDetail
        } else {
            detail =
                await workoutDetail(
                    for: summary
                )
        }

        let workout: HKWorkout?
        if let cached = workoutObjects[summary.id] {
            workout = cached
        } else {
            workout = try? await workoutForChallenge(
                uuid: summary.id
            )
            if let workout {
                workoutObjects[workout.uuid] = workout
            }
        }

        let heartSamples: [HKQuantitySample]
        if let workout {
            heartSamples =
                (try? await fetchHeartRateSamplesForInsight(
                    for: workout
                )) ?? []
        } else {
            heartSamples = []
        }

        let route = detail.route
            .filter {
                $0.horizontalAccuracy >= 0 &&
                $0.horizontalAccuracy <= 65
            }
            .sorted { $0.timestamp < $1.timestamp }

        let elevationGain =
            workoutInsightElevationGain(route)

        let pace: Double?
        if let distance = summary.distanceMeters,
           distance > 0 {
            pace = summary.duration /
                (distance / 1_000)
        } else {
            pace = nil
        }

        return WorkoutAIInsightContext(
            activity: summary.activity.rawValue,
            durationSeconds: summary.duration,
            distanceMeters: summary.distanceMeters,
            activeEnergyKilocalories:
                summary.activeEnergyKilocalories,
            averageHeartRateBPM:
                detail.averageHeartRate,
            maxHeartRateBPM:
                detail.maxHeartRate,
            personalMaximumHeartRateBPM:
                maximumHeartRateBPM,
            elevationGainMeters:
                elevationGain > 0
                    ? elevationGain
                    : nil,
            routePointCount: route.count,
            averagePaceSecondsPerKilometer:
                pace,
            averageRunningPowerWatts:
                detail.averageRunningPowerWatts,
            averageRunningStrideLengthMeters:
                detail.averageRunningStrideLengthMeters,
            averageRunningVerticalOscillationCentimeters:
                detail.averageRunningVerticalOscillationCentimeters,
            averageRunningGroundContactTimeMilliseconds:
                detail.averageRunningGroundContactTimeMilliseconds,
            segments:
                workoutInsightSegments(
                    route: route,
                    heartSamples: heartSamples,
                    startDate: summary.startDate,
                    endDate: summary.endDate
                )
        )
    }

    private func fetchHeartRateSamplesForInsight(
        for workout: HKWorkout
    ) async throws -> [HKQuantitySample] {
        guard let type =
                HKObjectType.quantityType(
                    forIdentifier: .heartRate
                )
        else {
            return []
        }

        let predicate =
            HKQuery.predicateForObjects(
                from: workout
            )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        return try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<
                        [HKQuantitySample],
                        Error
                    >
            ) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else {
                    continuation.resume(
                        returning:
                            samples
                                as? [HKQuantitySample]
                                ?? []
                    )
                }
            }

            healthStore.execute(query)
        }
    }

    private func workoutInsightSegments(
        route: [CLLocation],
        heartSamples: [HKQuantitySample],
        startDate: Date,
        endDate: Date
    ) -> [WorkoutRouteHealthSegment] {
        let duration =
            max(
                endDate.timeIntervalSince(
                    startDate
                ),
                1
            )
        let labels = [
            "Opening quarter",
            "Second quarter",
            "Third quarter",
            "Final quarter"
        ]
        let heartUnit =
            HKUnit.count()
                .unitDivided(by: .minute())

        return (0..<4).map { index in
            let segmentStart =
                startDate.addingTimeInterval(
                    duration *
                    Double(index) / 4
                )
            let segmentEnd =
                index == 3
                    ? endDate
                    : startDate
                        .addingTimeInterval(
                            duration *
                            Double(index + 1) /
                            4
                        )

            let points = route.filter {
                $0.timestamp >= segmentStart &&
                $0.timestamp <= segmentEnd
            }

            var segmentDistance = 0.0
            var gain = 0.0
            var loss = 0.0

            if points.count >= 2 {
                for pointIndex in 1..<points.count {
                    let previous =
                        points[pointIndex - 1]
                    let current =
                        points[pointIndex]
                    let elapsed =
                        current.timestamp
                            .timeIntervalSince(
                                previous.timestamp
                            )

                    if elapsed > 0 {
                        let distance =
                            current.distance(
                                from: previous
                            )
                        let speed =
                            distance / elapsed

                        if distance >= 0 &&
                            speed <= 12.5 {
                            segmentDistance +=
                                distance
                        }
                    }

                    let altitudeDelta =
                        current.altitude -
                        previous.altitude

                    if altitudeDelta > 0 &&
                        altitudeDelta < 50 {
                        gain += altitudeDelta
                    } else if
                        altitudeDelta < 0 &&
                        altitudeDelta > -50 {
                        loss +=
                            abs(altitudeDelta)
                    }
                }
            }

            let heartValues =
                heartSamples.compactMap {
                    sample -> Double? in
                    guard
                        sample.startDate >=
                            segmentStart,
                        sample.startDate <
                            segmentEnd
                    else {
                        return nil
                    }

                    guard let value =
                            Self.safeDoubleValue(
                                sample.quantity,
                                unit: heartUnit
                            ),
                          value >= 30,
                          value <= 260
                    else {
                        return nil
                    }

                    return value
                }

            let averageHR =
                heartValues.isEmpty
                    ? nil
                    : heartValues.reduce(0, +) /
                        Double(
                            heartValues.count
                        )
            let maxHR =
                heartValues.max()
            let segmentDuration =
                segmentEnd.timeIntervalSince(
                    segmentStart
                )
            let segmentPace =
                segmentDistance >= 50
                    ? segmentDuration /
                        (
                            segmentDistance /
                            1_000
                        )
                    : nil

            return WorkoutRouteHealthSegment(
                label: labels[index],
                durationSeconds:
                    segmentDuration,
                distanceMeters:
                    segmentDistance,
                elevationGainMeters: gain,
                elevationLossMeters: loss,
                averageHeartRateBPM:
                    averageHR,
                maxHeartRateBPM: maxHR,
                paceSecondsPerKilometer:
                    segmentPace
            )
        }
    }

    private func workoutInsightElevationGain(
        _ route: [CLLocation]
    ) -> Double {
        guard route.count >= 2 else {
            return 0
        }

        var gain = 0.0

        for index in 1..<route.count {
            let delta =
                route[index].altitude -
                route[index - 1].altitude

            if delta > 0 && delta < 50 {
                gain += delta
            }
        }

        return gain
    }

    private func storedWorkoutLocation(
        for workout: HKWorkout
    ) -> CLLocation? {
        guard let metadata = workout.metadata,
              let latitude = metadataNumber(
                metadata[ATHLTHWorkoutMetadataKey.locationLatitude]
              ),
              let longitude = metadataNumber(
                metadata[ATHLTHWorkoutMetadataKey.locationLongitude]
              ),
              CLLocationCoordinate2DIsValid(
                CLLocationCoordinate2D(
                    latitude: latitude,
                    longitude: longitude
                )
              )
        else {
            return nil
        }

        let accuracy = metadataNumber(
            metadata[
                ATHLTHWorkoutMetadataKey.locationHorizontalAccuracy
            ]
        ) ?? 50

        return CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            altitude: 0,
            horizontalAccuracy: max(accuracy, 0),
            verticalAccuracy: -1,
            timestamp: workout.startDate
        )
    }

    private func metadataNumber(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let value = value as? Double {
            return value
        }

        if let value = value as? String {
            return Double(value)
        }

        return nil
    }

    private func workoutMatchesGoalActivity(
        _ workout: HKWorkout,
        filter: GoalActivityFilter?
    ) -> Bool {
        switch filter ?? .any {
        case .any:
            return true
        case .running:
            return workout.workoutActivityType == .running
        case .walking:
            return workout.workoutActivityType == .walking
        case .cycling:
            return workout.workoutActivityType == .cycling
        case .hiking:
            return workout.workoutActivityType == .hiking
        }
    }

    private struct TrophySnapshotDiskCache: Codable {
        let snapshot: TrophyHealthSnapshot
        let generatedAt: Date
        let latestWorkoutID: UUID?
        let latestWorkoutEnd: Date?
        let latestSleepDuration: TimeInterval
    }

    private var externalWorkoutImportMode: ExternalWorkoutImportMode {
        ExternalWorkoutImportMode(
            rawValue: UserDefaults.standard.string(
                forKey: "settings.externalWorkoutImportMode"
            ) ?? ""
        ) ?? .ask
    }

    private func isATHLTHWorkout(_ workout: HKWorkout) -> Bool {
        let bundleIdentifier =
            workout.sourceRevision.source.bundleIdentifier.lowercased()

        if bundleIdentifier.hasPrefix("com.wesc9.athlth") {
            return true
        }

        if let syncIdentifier =
                workout.metadata?[HKMetadataKeySyncIdentifier] as? String,
           syncIdentifier.lowercased().hasPrefix("athlth-") {
            return true
        }

        return false
    }

    private func isWorkoutAcceptedForATHLTH(
        _ workout: HKWorkout
    ) -> Bool {
        if ignoredExternalWorkoutIDs.contains(workout.uuid) {
            return false
        }

        if isATHLTHWorkout(workout) {
            return true
        }

        if workout.endDate < workoutImportCutoverDate {
            return true
        }

        return importedExternalWorkoutIDs.contains(workout.uuid)
    }

    private func makePendingWorkoutImport(
        _ workout: HKWorkout
    ) -> PendingWorkoutImport {
        PendingWorkoutImport(
            summary: WorkoutSummary(workout: workout),
            sourceName: workout.sourceRevision.source.name,
            deviceName: workout.device?.name
        )
    }

    private func fetchWorkoutImportChanges() async throws -> (
        workouts: [HKWorkout],
        deleted: [HKDeletedObject],
        anchor: HKQueryAnchor?
    ) {
        let predicate = HKQuery.predicateForSamples(
            withStart: workoutImportCutoverDate,
            end: nil,
            options: []
        )
        let anchor = workoutImportAnchor

        return try await withCheckedThrowingContinuation {
            continuation in

            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(
                    returning: (
                        (samples as? [HKWorkout]) ?? [],
                        deleted ?? [],
                        newAnchor
                    )
                )
            }

            healthStore.execute(query)
        }
    }

    private func rehydratePendingWorkoutImports() async {
        guard !pendingExternalWorkoutIDs.isEmpty else {
            pendingWorkoutImports = []
            return
        }

        let start = min(
            workoutImportCutoverDate,
            Date().addingTimeInterval(-90 * 24 * 60 * 60)
        )

        guard let fetched = try? await fetchRawWorkouts(
            startDate: start,
            endDate: Date(),
            limit: 250
        ) else {
            return
        }

        let matching = fetched.filter {
            pendingExternalWorkoutIDs.contains($0.uuid) &&
                !importedExternalWorkoutIDs.contains($0.uuid) &&
                !ignoredExternalWorkoutIDs.contains($0.uuid)
        }

        for workout in matching {
            workoutObjects[workout.uuid] = workout
        }

        pendingWorkoutImports = matching
            .map(makePendingWorkoutImport)
            .sorted {
                $0.summary.endDate > $1.summary.endDate
            }

        let foundIDs = Set(matching.map(\.uuid))
        let missingIDs = pendingExternalWorkoutIDs.subtracting(foundIDs)

        if !missingIDs.isEmpty {
            pendingExternalWorkoutIDs.subtract(missingIDs)
            persistWorkoutImportState()
        }
    }

    private static func loadWorkoutImportUUIDSet(
        key: String,
        defaults: UserDefaults
    ) -> Set<UUID> {
        Set(
            (defaults.stringArray(forKey: key) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    private func persistWorkoutImportState() {
        let defaults = UserDefaults.standard
        defaults.set(
            pendingExternalWorkoutIDs.map(\.uuidString),
            forKey: workoutImportPendingIDsKey
        )
        defaults.set(
            importedExternalWorkoutIDs.map(\.uuidString),
            forKey: workoutImportImportedIDsKey
        )
        defaults.set(
            ignoredExternalWorkoutIDs.map(\.uuidString),
            forKey: workoutImportIgnoredIDsKey
        )
    }

    private func persistWorkoutImportAnchor(
        _ anchor: HKQueryAnchor
    ) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        ) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: workoutImportAnchorKey
        )
    }

    private func invalidateWorkoutDerivedCaches() {
        allWorkoutsCache = nil
        workoutRouteCache.removeAll(keepingCapacity: true)
        profilePerformanceCache = nil
        personalRecordsCache = nil
        invalidateTrophySnapshotCache()
    }

    private func invalidateTrophySnapshotCache() {
        trophySnapshotCache = nil
        trophyCacheLatestWorkoutID = nil
        trophyCacheLatestWorkoutEnd = nil
        trophyCacheLatestSleepDuration = nil
        UserDefaults.standard.removeObject(
            forKey: trophySnapshotDiskKey
        )
    }

    private struct RunningRoutePerformanceEntry: Codable {
        let workoutID: UUID
        let startDate: Date
        let endDate: Date
        let reportedDistanceMeters: Double
        let analyzedAt: Date
        let routeAvailable: Bool
        let fastestOneK: TimeInterval?
        let fastestMile: TimeInterval?
        let fastestFiveK: TimeInterval?
        let fastestTenK: TimeInterval?
        let fastestHalfMarathon: TimeInterval?
        let fastestMarathon: TimeInterval?

        func duration(
            for kind: HealthPersonalRecordKind
        ) -> TimeInterval? {
            switch kind {
            case .fastest1K:
                return fastestOneK
            case .fastestMile:
                return fastestMile
            case .fastest5K:
                return fastestFiveK
            case .fastest10K:
                return fastestTenK
            case .fastestHalfMarathon:
                return fastestHalfMarathon
            case .fastestMarathon:
                return fastestMarathon
            default:
                return nil
            }
        }
    }

    private struct RunningRoutePerformanceDiskCache: Codable {
        let entries: [RunningRoutePerformanceEntry]
    }

    private func loadRunningRoutePerformanceCacheIfNeeded() {
        guard !runningRoutePerformanceCacheLoaded else {
            return
        }

        runningRoutePerformanceCacheLoaded = true

        guard let data = UserDefaults.standard.data(
                  forKey: runningRoutePerformanceDiskKey
              ),
              let cache = try? JSONDecoder().decode(
                  RunningRoutePerformanceDiskCache.self,
                  from: data
              )
        else {
            return
        }

        runningRoutePerformanceCache =
            Dictionary(
                uniqueKeysWithValues:
                    cache.entries.map {
                        ($0.workoutID, $0)
                    }
            )
    }

    private func persistRunningRoutePerformanceCache() {
        let diskCache =
            RunningRoutePerformanceDiskCache(
                entries:
                    runningRoutePerformanceCache
                    .values
                    .sorted {
                        $0.endDate > $1.endDate
                    }
            )

        guard let data =
                try? JSONEncoder().encode(diskCache)
        else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: runningRoutePerformanceDiskKey
        )
    }

    private func runningRoutePerformanceEntries(
        for runningWorkouts: [HKWorkout]
    ) async -> [RunningRoutePerformanceEntry] {
        loadRunningRoutePerformanceCacheIfNeeded()

        let currentIDs =
            Set(runningWorkouts.map(\.uuid))
        let staleIDs =
            runningRoutePerformanceCache.keys
            .filter { !currentIDs.contains($0) }

        var cacheChanged = !staleIDs.isEmpty
        for id in staleIDs {
            runningRoutePerformanceCache[id] = nil
        }

        for workout in runningWorkouts {
            let distance =
                workout.athlthDistanceMeters ?? 0

            guard distance >= 1_000 else {
                continue
            }

            if let cached =
                    runningRoutePerformanceCache[
                        workout.uuid
                    ],
               abs(
                   cached.endDate.timeIntervalSince(
                       workout.endDate
                   )
               ) < 1,
               abs(
                   cached.reportedDistanceMeters -
                   distance
               ) < 1 {
                let shouldRetryUnavailableRoute =
                    !cached.routeAvailable &&
                    Date().timeIntervalSince(
                        cached.analyzedAt
                    ) > 600 &&
                    Date().timeIntervalSince(
                        workout.endDate
                    ) < 86_400

                if !shouldRetryUnavailableRoute {
                    continue
                }
            }

            let route =
                (try? await fetchRoute(
                    for: workout
                )) ?? []
            let hasRoute = route.count >= 2

            func segment(
                _ target: Double
            ) -> TimeInterval? {
                guard hasRoute,
                      distance >= target
                else {
                    return nil
                }

                return fastestSegmentDuration(
                    in: route,
                    targetDistance: target
                )
            }

            runningRoutePerformanceCache[
                workout.uuid
            ] = RunningRoutePerformanceEntry(
                workoutID: workout.uuid,
                startDate: workout.startDate,
                endDate: workout.endDate,
                reportedDistanceMeters: distance,
                analyzedAt: Date(),
                routeAvailable: hasRoute,
                fastestOneK: segment(1_000),
                fastestMile: segment(1_609.344),
                fastestFiveK: segment(5_000),
                fastestTenK: segment(10_000),
                fastestHalfMarathon: segment(21_097.5),
                fastestMarathon: segment(42_195)
            )
            cacheChanged = true
        }

        if cacheChanged {
            persistRunningRoutePerformanceCache()
        }

        return runningWorkouts.compactMap {
            runningRoutePerformanceCache[$0.uuid]
        }
    }

    private func fetchAllWorkoutsCached(
        forceRefresh: Bool = false
    ) async throws -> [HKWorkout] {
        if !forceRefresh,
           let cached = allWorkoutsCache,
           Date().timeIntervalSince(cached.generatedAt) < 600 {
            return cached.workouts
        }

        let fetched = try await fetchAllWorkouts()
        allWorkoutsCache = (fetched, Date())

        for workout in fetched {
            workoutObjects[workout.uuid] = workout
        }

        return fetched
    }

    private func fetchAllWorkouts() async throws -> [HKWorkout] {
        let fetched = try await fetchRawAllWorkouts()
        return fetched.filter(isWorkoutAcceptedForATHLTH)
    }

    private func fetchRawAllWorkouts() async throws -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKWorkout], Error>) in

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }

            healthStore.execute(query)
        }
    }

    private func fetchWorkouts(
        startDate: Date,
        endDate: Date,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [HKWorkout] {
        let fetched = try await fetchRawWorkouts(
            startDate: startDate,
            endDate: endDate,
            limit: limit
        )
        return fetched.filter(isWorkoutAcceptedForATHLTH)
    }

    private func fetchRawWorkouts(
        startDate: Date,
        endDate: Date,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKWorkout], Error>) in

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }

            healthStore.execute(query)
        }
    }

    private func fetchLatestSleep() async throws -> SleepSummary {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return .empty
        }

        let end = Date()
        let calendar = Calendar.current
        let start =
            calendar.date(
                byAdding: .day,
                value: -3,
                to: calendar.startOfDay(for: end)
            ) ??
            end.addingTimeInterval(-259_200)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: []
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKCategorySample], Error>) in

            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
            }

            healthStore.execute(query)
        }

        func sleepValue(_ sample: HKCategorySample) -> HKCategoryValueSleepAnalysis? {
            HKCategoryValueSleepAnalysis(rawValue: sample.value)
        }

        func isAsleep(_ sample: HKCategorySample) -> Bool {
            guard let value = sleepValue(sample) else { return false }

            switch value {
            case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
                return true
            default:
                return false
            }
        }

        func mergedDuration(_ input: [HKCategorySample]) -> TimeInterval {
            let sorted = input
                .filter { $0.endDate > $0.startDate }
                .sorted { $0.startDate < $1.startDate }

            guard let first = sorted.first else { return 0 }

            var total: TimeInterval = 0
            var currentStart = first.startDate
            var currentEnd = first.endDate

            for sample in sorted.dropFirst() {
                if sample.startDate <= currentEnd {
                    currentEnd = max(currentEnd, sample.endDate)
                } else {
                    total += currentEnd.timeIntervalSince(currentStart)
                    currentStart = sample.startDate
                    currentEnd = sample.endDate
                }
            }

            total += currentEnd.timeIntervalSince(currentStart)
            return max(total, 0)
        }

        let asleepSamples = samples.filter(isAsleep)
        guard !asleepSamples.isEmpty else {
            return .empty
        }

        // Build sleep sessions while allowing normal awake gaps during the
        // night. Selecting the longest recent session keeps a later short nap
        // from replacing the main overnight sleep.
        let sortedAsleep = asleepSamples.sorted { $0.startDate < $1.startDate }
        var sessions: [[HKCategorySample]] = []

        for sample in sortedAsleep {
            guard !sessions.isEmpty else {
                sessions.append([sample])
                continue
            }

            let currentIndex = sessions.index(before: sessions.endIndex)
            let latestEnd = sessions[currentIndex]
                .map(\.endDate)
                .max() ?? sample.startDate

            if sample.startDate.timeIntervalSince(latestEnd) <= 2 * 60 * 60 {
                sessions[currentIndex].append(sample)
            } else {
                sessions.append([sample])
            }
        }

        // Prefer the newest substantial sleep session. The previous
        // 36-hour query could begin in the middle of an older overnight
        // session late in the afternoon, leaving only the final couple of
        // hours visible to ATHLTH. A wider query plus a minimum main-sleep
        // duration avoids both that truncation and a short later nap
        // replacing the most recent overnight sleep.
        let substantialSessions = sessions.filter {
            mergedDuration($0) >= 3 * 60 * 60
        }
        let primaryCandidates =
            substantialSessions.isEmpty
                ? sessions
                : substantialSessions

        guard let primarySession =
                primaryCandidates.max(by: { lhs, rhs in
                    let leftEnd =
                        lhs.map(\.endDate).max() ??
                        .distantPast
                    let rightEnd =
                        rhs.map(\.endDate).max() ??
                        .distantPast

                    if abs(
                        leftEnd.timeIntervalSince(
                            rightEnd
                        )
                    ) > 60 {
                        return leftEnd < rightEnd
                    }

                    return mergedDuration(lhs) <
                        mergedDuration(rhs)
                })
        else {
            return .empty
        }

        guard let sessionStart = primarySession.map(\.startDate).min(),
              let sessionEnd = primarySession.map(\.endDate).max()
        else {
            return .empty
        }

        let sourceGroups = Dictionary(
            grouping: primarySession,
            by: { $0.sourceRevision.source.bundleIdentifier }
        )

        func detailedStageDuration(_ group: [HKCategorySample]) -> TimeInterval {
            mergedDuration(group.filter { sample in
                guard let value = sleepValue(sample) else { return false }
                switch value {
                case .asleepCore, .asleepDeep, .asleepREM:
                    return true
                default:
                    return false
                }
            })
        }

        let preferredSourceGroup = sourceGroups.values.max(by: { lhs, rhs in
            let leftDetailed = detailedStageDuration(lhs)
            let rightDetailed = detailedStageDuration(rhs)

            if abs(leftDetailed - rightDetailed) > 60 {
                return leftDetailed < rightDetailed
            }

            return mergedDuration(lhs) < mergedDuration(rhs)
        }) ?? primarySession

        let preferredBundleID =
            preferredSourceGroup.first?
                .sourceRevision
                .source
                .bundleIdentifier
        let preferredSessionStart =
            preferredSourceGroup
                .map(\.startDate)
                .min() ??
            sessionStart
        let preferredSessionEnd =
            preferredSourceGroup
                .map(\.endDate)
                .max() ??
            sessionEnd

        func stageDuration(
            _ stage:
                HKCategoryValueSleepAnalysis
        ) -> TimeInterval {
            mergedDuration(
                preferredSourceGroup.filter {
                    sleepValue($0) ==
                        stage
                }
            )
        }

        let awakeSamples =
            samples.filter { sample in
                guard
                    sleepValue(sample) ==
                        .awake,
                    sample.endDate >
                        preferredSessionStart,
                    sample.startDate <
                        preferredSessionEnd
                else {
                    return false
                }

                if let preferredBundleID {
                    return sample
                        .sourceRevision
                        .source
                        .bundleIdentifier ==
                        preferredBundleID
                }

                return true
            }

        var result = SleepSummary.empty
        result.totalAsleep =
            mergedDuration(
                preferredSourceGroup
            )
        result.core =
            stageDuration(.asleepCore)
        result.deep =
            stageDuration(.asleepDeep)
        result.rem =
            stageDuration(.asleepREM)
        result.awake =
            mergedDuration(awakeSamples)
        result.sleepStart =
            preferredSessionStart
        result.sleepEnd =
            preferredSessionEnd
        return result
    }

    private func fetchHeartSummary() async throws -> HeartSummary {
        let now = Date()

        async let latest = latestQuantity(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate:
                now.addingTimeInterval(
                    -24 * 3_600
                )
        )
        async let resting = latestQuantity(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate:
                now.addingTimeInterval(
                    -72 * 3_600
                )
        )
        async let hrv = latestDailyAverageQuantity(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            lookbackDays: 3,
            now: now
        )

        let latestValue:
            (Double, Date)?
        do {
            latestValue =
                try await latest
        } catch {
            if Self.isTemporarilyUnavailableHealthRead(
                error
            ) {
                throw error
            }

            latestValue = nil
        }

        let restingValue =
            try? await resting
        let hrvValue =
            try? await hrv

        let validLatest =
            latestValue.flatMap {
                $0.0 > 0 ? $0 : nil
            }
        let validResting =
            restingValue.flatMap {
                $0.0 > 0 ? $0 : nil
            }

        return HeartSummary(
            latestHeartRate:
                validLatest?.0,
            latestHeartRateDate:
                validLatest?.1,
            restingHeartRate:
                validResting?.0,
            restingHeartRateDate:
                validResting?.1,
            hrvMilliseconds:
                hrvValue?.0,
            hrvDate:
                hrvValue?.1
        )
    }

    private func fetchTrainingSummary() async throws -> TrainingHealthSummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = Date()

        async let steps = summedQuantity(
            identifier: .stepCount,
            unit: .count(),
            start: start,
            end: end
        )
        async let activeEnergy = summedQuantity(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end
        )
        async let basalEnergy = summedQuantity(
            identifier: .basalEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end
        )
        async let exerciseMinutes = summedQuantity(
            identifier: .appleExerciseTime,
            unit: .minute(),
            start: start,
            end: end
        )
        async let walkingRunningDistance = summedQuantity(
            identifier: .distanceWalkingRunning,
            unit: .meter(),
            start: start,
            end: end
        )
        async let cyclingDistance = summedQuantity(
            identifier: .distanceCycling,
            unit: .meter(),
            start: start,
            end: end
        )
        async let swimmingDistance = summedQuantity(
            identifier: .distanceSwimming,
            unit: .meter(),
            start: start,
            end: end
        )
        async let flights = summedQuantity(
            identifier: .flightsClimbed,
            unit: .count(),
            start: start,
            end: end
        )
        let now = Date()

        async let vo2 = latestQuantity(
            identifier: .vo2Max,
            unit: HKUnit(from: "ml/kg*min"),
            startDate:
                now.addingTimeInterval(
                    -90 * 86_400
                )
        )
        async let walkingHeartRate = latestQuantity(
            identifier: .walkingHeartRateAverage,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate:
                now.addingTimeInterval(
                    -7 * 86_400
                )
        )
        async let oxygen = latestQuantity(
            identifier: .oxygenSaturation,
            unit: .percent(),
            startDate:
                now.addingTimeInterval(
                    -7 * 86_400
                )
        )
        async let respiratory = latestQuantity(
            identifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate:
                now.addingTimeInterval(
                    -7 * 86_400
                )
        )

        let stepsValue: Double?
        do {
            stepsValue =
                try await steps
        } catch {
            if Self.isTemporarilyUnavailableHealthRead(
                error
            ) {
                throw error
            }

            stepsValue = nil
        }

        let activeEnergyValue =
            try? await activeEnergy
        let moveGoalValue: Double?
        if ATHLTHWatchWorkoutRuntime
            .isMirroredWorkoutActive {
            // HKActivitySummaryQuery has historically been the most fragile
            // HealthKit read in ATHLTH during an active mirrored Watch workout.
            // Keep the last known goal while the workout is live instead of
            // starting that Objective-C predicate/query on app activation.
            moveGoalValue =
                training
                    .moveGoalKilocaloriesToday
        } else {
            moveGoalValue =
                try? await fetchTodayMoveGoal()
        }
        let basalEnergyValue = try? await basalEnergy
        let exerciseMinutesValue = try? await exerciseMinutes
        let walkingRunningDistanceValue = try? await walkingRunningDistance
        let cyclingDistanceValue = try? await cyclingDistance
        let swimmingDistanceValue = try? await swimmingDistance
        let flightsValue = try? await flights
        let vo2Value = try? await vo2
        let walkingHeartRateValue = try? await walkingHeartRate
        let oxygenValue = try? await oxygen
        let respiratoryValue = try? await respiratory

        return TrainingHealthSummary(
            stepsToday: stepsValue,
            activeEnergyKilocaloriesToday: activeEnergyValue,
            moveGoalKilocaloriesToday: moveGoalValue,
            basalEnergyKilocaloriesToday: basalEnergyValue,
            exerciseMinutesToday: exerciseMinutesValue,
            distanceWalkingRunningMetersToday: walkingRunningDistanceValue,
            distanceCyclingMetersToday: cyclingDistanceValue,
            distanceSwimmingMetersToday: swimmingDistanceValue,
            flightsClimbedToday: flightsValue,
            vo2Max: vo2Value?.0,
            walkingHeartRateAverage: walkingHeartRateValue?.0,
            oxygenSaturationPercent:
                oxygenValue.flatMap {
                    sample in

                    let value = sample.0
                    guard value >= 0,
                          value <= 1
                    else {
                        return nil
                    }

                    return value * 100
                },
            respiratoryRate: respiratoryValue?.0
        )
    }

    private struct ProgressMetrics {
        let workoutCount: Int
        let totalSteps: Double?
        let averageDailySteps: Double?
        let averageSleepDuration: TimeInterval?
        let trainingDuration: TimeInterval
        let workoutDistanceMeters: Double
        let activeWorkoutDays: [Date]
        let buckets: [HealthProgressBucket]
    }

    private func progressMetrics(
        startDate: Date,
        endDate: Date,
        grouping: HealthProgressGrouping
    ) async throws -> ProgressMetrics {
        async let workoutsTask = fetchWorkouts(
            startDate: startDate,
            endDate: endDate
        )
        async let stepsTask = dailyCumulativeQuantities(
            identifier: .stepCount,
            unit: .count(),
            startDate: startDate,
            endDate: endDate
        )
        async let sleepTask = sleepDurationsByWakeDay(
            startDate: startDate,
            endDate: endDate
        )

        let workouts = (try? await workoutsTask) ?? []
        let stepsByDay = (try? await stepsTask) ?? [:]
        let sleepByDay = (try? await sleepTask) ?? [:]

        let calendar = Calendar.current
        let totalTrainingDuration = workouts.reduce(0) { $0 + $1.duration }
        let totalWorkoutDistance = workouts.reduce(0) { partial, workout in
            partial +
                (workout.athlthDistanceMeters ?? 0)
        }
        let totalSteps = stepsByDay.isEmpty ? nil : stepsByDay.values.reduce(0, +)
        let averageSteps = average(Array(stepsByDay.values))
        let averageSleep = average(Array(sleepByDay.values))
        let activeWorkoutDays = Array(
            Set(workouts.map { calendar.startOfDay(for: $0.startDate) })
        )
        .sorted()

        return ProgressMetrics(
            workoutCount: workouts.count,
            totalSteps: totalSteps,
            averageDailySteps: averageSteps,
            averageSleepDuration: averageSleep,
            trainingDuration: totalTrainingDuration,
            workoutDistanceMeters: totalWorkoutDistance,
            activeWorkoutDays: activeWorkoutDays,
            buckets: makeProgressBuckets(
                startDate: startDate,
                endDate: endDate,
                grouping: grouping,
                workouts: workouts,
                stepsByDay: stepsByDay,
                sleepByDay: sleepByDay
            )
        )
    }

    private func fetchTodayMoveGoal() async throws -> Double? {
        guard !ATHLTHWatchWorkoutRuntime
            .isMirroredWorkoutActive
        else {
            return training
                .moveGoalKilocaloriesToday
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: Date()
        )

        // HealthKit requires the DateComponents used for an activity-summary
        // predicate to carry a valid Calendar. iOS 27 raises an Objective-C
        // exception here (which Swift cannot catch) when calendar is nil.
        // Calendar.dateComponents(_:from:) does not guarantee that property.
        components.calendar = calendar
        components.timeZone = calendar.timeZone

        let predicate = HKQuery.predicateForActivitySummary(
            with: components
        )

        let summaries = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKActivitySummary], Error>) in

            let query = HKActivitySummaryQuery(predicate: predicate) {
                _, summaries, error in

                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: summaries ?? [])
                }
            }

            healthStore.execute(query)
        }

        guard let summary = summaries.first else { return nil }

        guard let goal = Self.safeDoubleValue(
            summary.activeEnergyBurnedGoal,
            unit: .kilocalorie()
        ) else {
            return nil
        }

        return goal > 0 ? goal : nil
    }

    private func fetchRecoveryReadiness(
        currentSleep: SleepSummary,
        currentHeart: HeartSummary
    ) async throws -> RecoveryReadinessSummary {
        let calendar = Calendar.current
        let baselineEnd = calendar.startOfDay(for: Date())
        let baselineStart = calendar.date(
            byAdding: .day,
            value: -14,
            to: baselineEnd
        ) ?? baselineEnd.addingTimeInterval(-1_209_600)

        async let sleepDaysTask = sleepDurationsByWakeDay(
            startDate: baselineStart,
            endDate: baselineEnd
        )
        async let hrvDaysTask = dailyAverageQuantities(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            startDate: baselineStart,
            endDate: baselineEnd
        )
        async let restingDaysTask = dailyAverageQuantities(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            startDate: baselineStart,
            endDate: baselineEnd
        )

        let sleepDays = (try? await sleepDaysTask) ?? [:]
        let hrvDays = (try? await hrvDaysTask) ?? [:]
        let restingDays = (try? await restingDaysTask) ?? [:]

        return RecoveryReadinessEngine.evaluate(
            currentSleep: currentSleep,
            currentHeart: currentHeart,
            sleepDays: sleepDays,
            hrvDays: hrvDays,
            restingHeartRateDays: restingDays
        )
    }

    private func dailyAverageQuantities(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date
    ) async throws -> [Date: Double] {
        guard startDate <= endDate,
              let type =
                HKObjectType.quantityType(
                    forIdentifier: identifier
                )
        else {
            return [:]
        }

        let calendar = Calendar.current
        let anchor =
            calendar.startOfDay(
                for: startDate
            )
        let predicate =
            HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )

        var values =
            try await withCheckedThrowingContinuation {
                (
                    continuation:
                        CheckedContinuation<
                            [Date: Double],
                            Error
                        >
                ) in

                let query =
                    HKStatisticsCollectionQuery(
                        quantityType: type,
                        quantitySamplePredicate:
                            predicate,
                        options:
                            .discreteAverage,
                        anchorDate: anchor,
                        intervalComponents:
                            DateComponents(
                                day: 1
                            )
                    )

                query.initialResultsHandler = {
                    _,
                    results,
                    error in

                    if let error {
                        continuation.resume(
                            throwing: error
                        )
                        return
                    }

                    guard let results else {
                        continuation.resume(
                            returning: [:]
                        )
                        return
                    }

                    var collected:
                        [Date: Double] = [:]

                    results.enumerateStatistics(
                        from: startDate,
                        to: endDate
                    ) {
                        statistics,
                        _ in

                        guard let quantity =
                                statistics
                                    .averageQuantity(),
                              let value =
                                Self.safeDoubleValue(
                                    quantity,
                                    unit: unit
                                ),
                              value > 0
                        else {
                            return
                        }

                        let day =
                            calendar.startOfDay(
                                for:
                                    statistics
                                        .startDate
                            )
                        collected[day] =
                            value
                    }

                    continuation.resume(
                        returning: collected
                    )
                }

                healthStore.execute(query)
            }

        // Preserve HealthKit's normal source-merging statistics. If a recent
        // interval is unexpectedly empty, re-check only a few missing days
        // with a single HKStatisticsQuery per day. This covers the intermittent
        // iOS 27 collection-gap behavior without raw-summing multiple sources.
        let rangeStart =
            calendar.startOfDay(
                for: startDate
            )
        let finalDay =
            min(
                calendar.startOfDay(
                    for: endDate
                ),
                calendar.startOfDay(
                    for: Date()
                )
            )

        var missingDays:
            [Date] = []
        var cursor = rangeStart

        while cursor <= finalDay {
            if values[cursor] == nil {
                missingDays.append(
                    cursor
                )
            }

            guard let next =
                    calendar.date(
                        byAdding: .day,
                        value: 1,
                        to: cursor
                    ),
                  next > cursor
            else {
                break
            }
            cursor = next
        }

        for day in
            missingDays.suffix(4) {
            guard let dayEnd =
                    calendar.date(
                        byAdding: .day,
                        value: 1,
                        to: day
                    )
            else {
                continue
            }

            if let fallback =
                    try? await averageQuantity(
                        identifier: identifier,
                        unit: unit,
                        start: max(
                            day,
                            startDate
                        ),
                        end: min(
                            dayEnd,
                            endDate
                        )
                    ),
               fallback > 0 {
                values[day] = fallback
            }
        }

        return values
    }

    private func dailyCumulativeQuantities(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date
    ) async throws -> [Date: Double] {
        guard startDate <= endDate,
              let type =
                HKObjectType.quantityType(
                    forIdentifier: identifier
                )
        else {
            return [:]
        }

        let calendar = Calendar.current
        let anchor =
            calendar.startOfDay(
                for: startDate
            )
        let predicate =
            HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )

        var values =
            try await withCheckedThrowingContinuation {
                (
                    continuation:
                        CheckedContinuation<
                            [Date: Double],
                            Error
                        >
                ) in

                let query =
                    HKStatisticsCollectionQuery(
                        quantityType: type,
                        quantitySamplePredicate:
                            predicate,
                        options:
                            .cumulativeSum,
                        anchorDate: anchor,
                        intervalComponents:
                            DateComponents(
                                day: 1
                            )
                    )

                query.initialResultsHandler = {
                    _,
                    results,
                    error in

                    if let error {
                        continuation.resume(
                            throwing: error
                        )
                        return
                    }

                    guard let results else {
                        continuation.resume(
                            returning: [:]
                        )
                        return
                    }

                    var collected:
                        [Date: Double] = [:]

                    results.enumerateStatistics(
                        from: startDate,
                        to: endDate
                    ) {
                        statistics,
                        _ in

                        guard let quantity =
                                statistics
                                    .sumQuantity(),
                              let value =
                                Self.safeDoubleValue(
                                    quantity,
                                    unit: unit
                                )
                        else {
                            return
                        }

                        let day =
                            calendar.startOfDay(
                                for:
                                    statistics
                                        .startDate
                            )
                        collected[day] =
                            value
                    }

                    continuation.resume(
                        returning: collected
                    )
                }

                healthStore.execute(query)
            }

        // iOS 27 has shown intermittent empty HKStatisticsCollection buckets
        // for existing step data. Re-check only the newest missing days with a
        // direct statistics query. This is intentionally bounded to avoid
        // turning progress refreshes into N-per-day HealthKit work.
        let today =
            calendar.startOfDay(
                for: Date()
            )
        let recentStart =
            max(
                calendar.startOfDay(
                    for: startDate
                ),
                calendar.date(
                    byAdding: .day,
                    value: -6,
                    to: today
                ) ?? today
            )

        var missingRecentDays:
            [Date] = []
        var cursor = recentStart
        let finalDay =
            min(
                calendar.startOfDay(
                    for: endDate
                ),
                today
            )

        while cursor <= finalDay {
            if values[cursor] == nil {
                missingRecentDays.append(
                    cursor
                )
            }

            guard let next =
                    calendar.date(
                        byAdding: .day,
                        value: 1,
                        to: cursor
                    ),
                  next > cursor
            else {
                break
            }
            cursor = next
        }

        for day in
            missingRecentDays.suffix(3) {
            guard let dayEnd =
                    calendar.date(
                        byAdding: .day,
                        value: 1,
                        to: day
                    )
            else {
                continue
            }

            if let fallback =
                    try? await summedQuantity(
                        identifier: identifier,
                        unit: unit,
                        start: max(
                            day,
                            startDate
                        ),
                        end: min(
                            dayEnd,
                            endDate
                        )
                    ) {
                values[day] = fallback
            }
        }

        return values
    }

    private func sleepDurationsByWakeDay(
        startDate: Date,
        endDate: Date
    ) async throws -> [Date: TimeInterval] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return [:]
        }

        let calendar = Calendar.current
        let queryStart = calendar.date(byAdding: .day, value: -1, to: startDate) ?? startDate
        let predicate = HKQuery.predicateForSamples(
            withStart: queryStart,
            end: endDate,
            options: []
        )

        let samples = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKCategorySample], Error>) in

            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
            }

            healthStore.execute(query)
        }

        let asleepSamples = samples.filter { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else {
                return false
            }

            switch value {
            case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
                return sample.endDate > sample.startDate
            default:
                return false
            }
        }
        .sorted { $0.startDate < $1.startDate }

        guard !asleepSamples.isEmpty else { return [:] }

        func mergedDuration(_ input: [HKCategorySample]) -> TimeInterval {
            let sorted = input.sorted { $0.startDate < $1.startDate }
            guard let first = sorted.first else { return 0 }

            var total: TimeInterval = 0
            var currentStart = first.startDate
            var currentEnd = first.endDate

            for sample in sorted.dropFirst() {
                if sample.startDate <= currentEnd {
                    currentEnd = max(currentEnd, sample.endDate)
                } else {
                    total += currentEnd.timeIntervalSince(currentStart)
                    currentStart = sample.startDate
                    currentEnd = sample.endDate
                }
            }

            total += currentEnd.timeIntervalSince(currentStart)
            return max(total, 0)
        }

        // Build complete sleep sessions first. A normal awake period inside a
        // night does not create a new session, while a long daytime gap does.
        var sessions: [[HKCategorySample]] = []

        for sample in asleepSamples {
            guard !sessions.isEmpty else {
                sessions.append([sample])
                continue
            }

            let currentIndex = sessions.index(before: sessions.endIndex)
            let latestEnd = sessions[currentIndex]
                .map(\.endDate)
                .max() ?? sample.startDate

            if sample.startDate.timeIntervalSince(latestEnd) <= 2 * 60 * 60 {
                sessions[currentIndex].append(sample)
            } else {
                sessions.append([sample])
            }
        }

        // Tie the complete session to its wake-up day. If a nap and an
        // overnight sleep end on the same day, keep the longer session for
        // sleep trends/recovery instead of inflating the nightly duration.
        var durations: [Date: TimeInterval] = [:]

        for session in sessions {
            let sourceGroups =
                Dictionary(
                    grouping: session,
                    by: {
                        $0.sourceRevision
                            .source
                            .bundleIdentifier
                    }
                )

            func detailedStageDuration(
                _ group:
                    [HKCategorySample]
            ) -> TimeInterval {
                mergedDuration(
                    group.filter {
                        sample in

                        guard let value =
                                HKCategoryValueSleepAnalysis(
                                    rawValue:
                                        sample.value
                                )
                        else {
                            return false
                        }

                        switch value {
                        case .asleepCore,
                             .asleepDeep,
                             .asleepREM:
                            return true
                        default:
                            return false
                        }
                    }
                )
            }

            let preferred =
                sourceGroups.values.max {
                    lhs,
                    rhs in

                    let leftDetailed =
                        detailedStageDuration(
                            lhs
                        )
                    let rightDetailed =
                        detailedStageDuration(
                            rhs
                        )

                    if abs(
                        leftDetailed -
                        rightDetailed
                    ) > 60 {
                        return leftDetailed <
                            rightDetailed
                    }

                    return mergedDuration(lhs) <
                        mergedDuration(rhs)
                } ??
                session

            guard let wakeTime =
                    preferred
                        .map(\.endDate)
                        .max(),
                  wakeTime >= startDate,
                  wakeTime <= endDate
            else {
                continue
            }

            let wakeDay =
                calendar.startOfDay(
                    for: wakeTime
                )
            let duration =
                mergedDuration(
                    preferred
                )

            if duration >
                (durations[wakeDay] ?? 0) {
                durations[wakeDay] =
                    duration
            }
        }

        return durations
    }

    private func makeProgressBuckets(
        startDate: Date,
        endDate: Date,
        grouping: HealthProgressGrouping,
        workouts: [HKWorkout],
        stepsByDay: [Date: Double],
        sleepByDay: [Date: TimeInterval]
    ) -> [HealthProgressBucket] {
        let calendar = Calendar.current
        var buckets: [HealthProgressBucket] = []
        var cursor = calendar.startOfDay(for: startDate)

        while cursor < endDate {
            let next: Date

            switch grouping {
            case .day:
                next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endDate
            case .week:
                next = calendar.date(byAdding: .day, value: 7, to: cursor) ?? endDate
            case .month:
                next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? endDate
            }

            let bucketEnd = min(next, endDate)
            let bucketWorkouts = workouts.filter {
                $0.startDate >= cursor && $0.startDate < bucketEnd
            }

            let stepValues = stepsByDay.compactMap { day, value in
                day >= cursor && day < bucketEnd ? value : nil
            }
            let sleepValues = sleepByDay.compactMap { day, value in
                day >= cursor && day < bucketEnd ? value : nil
            }

            buckets.append(
                HealthProgressBucket(
                    startDate: cursor,
                    endDate: bucketEnd,
                    workoutCount: bucketWorkouts.count,
                    averageDailySteps: average(stepValues),
                    averageSleepDuration: average(sleepValues),
                    trainingDuration:
                        bucketWorkouts.reduce(0) { $0 + $1.duration },
                    workoutDistanceMeters:
                        bucketWorkouts.reduce(0) { partial, workout in
                            partial +
                                (workout.athlthDistanceMeters ?? 0)
                        }
                )
            )

            cursor = next
        }

        return buckets
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func averageQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard start <= end,
              let type =
                HKObjectType.quantityType(
                    forIdentifier: identifier
                )
        else {
            return nil
        }

        let predicate =
            HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )

        return try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<
                        Double?,
                        Error
                    >
            ) in

            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate:
                    predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                    return
                }

                continuation.resume(
                    returning:
                        Self.safeDoubleValue(
                            result?
                                .averageQuantity(),
                            unit: unit
                        )
                )
            }

            healthStore.execute(query)
        }
    }

    private func summedQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard start <= end,
              let type = HKObjectType.quantityType(forIdentifier: identifier)
        else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Double?, Error>) in

            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(
                    returning: Self.safeDoubleValue(result?.sumQuantity(), unit: unit)
                )
            }

            healthStore.execute(query)
        }
    }

    private func workoutQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        option: HKStatisticsOptions,
        workout: HKWorkout
    ) async throws -> Double? {
        guard let type =
                HKObjectType.quantityType(
                    forIdentifier: identifier
                )
        else {
            return nil
        }

        func quantity(
            from statistics: HKStatistics
        ) -> HKQuantity? {
            if option.contains(
                .cumulativeSum
            ) {
                return statistics
                    .sumQuantity()
            }

            if option.contains(
                .discreteAverage
            ) {
                return statistics
                    .averageQuantity()
            }

            if option.contains(
                .discreteMax
            ) {
                return statistics
                    .maximumQuantity()
            }

            if option.contains(
                .discreteMin
            ) {
                return statistics
                    .minimumQuantity()
            }

            return nil
        }

        if let statistics =
                workout.statistics(
                    for: type
                ),
           let value =
                Self.safeDoubleValue(
                    quantity(
                        from: statistics
                    ),
                    unit: unit
                ) {
            return value
        }

        // Compatibility fallback for older/imported workouts that have
        // associated samples but no cached workout statistics.
        let predicate =
            HKQuery.predicateForObjects(
                from: workout
            )

        return try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<
                        Double?,
                        Error
                    >
            ) in

            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate:
                    predicate,
                options: option
            ) { _, result, error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                    return
                }

                guard let result else {
                    continuation.resume(
                        returning: nil
                    )
                    return
                }

                continuation.resume(
                    returning:
                        Self.safeDoubleValue(
                            quantity(
                                from: result
                            ),
                            unit: unit
                        )
                )
            }

            healthStore.execute(query)
        }
    }

    private func latestDailyAverageQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        lookbackDays: Int,
        now: Date = Date()
    ) async throws -> (Double, Date)? {
        let calendar = Calendar.current
        let start =
            calendar.date(
                byAdding: .day,
                value:
                    -max(
                        lookbackDays,
                        1
                    ),
                to: now
            ) ??
            now.addingTimeInterval(
                -Double(
                    max(
                        lookbackDays,
                        1
                    )
                ) * 86_400
            )

        guard let latest =
                try await latestQuantity(
                    identifier: identifier,
                    unit: unit,
                    startDate: start
                ),
              latest.0 > 0
        else {
            return nil
        }

        let dayStart =
            calendar.startOfDay(
                for: latest.1
            )
        guard let dayEnd =
                calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: dayStart
                ),
              let average =
                try await averageQuantity(
                    identifier: identifier,
                    unit: unit,
                    start: dayStart,
                    end: min(dayEnd, now)
                ),
              average > 0
        else {
            return latest
        }

        return (average, latest.1)
    }

    private func latestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date
    ) async throws -> (Double, Date)? {
        let endDate = Date()
        guard startDate <= endDate,
              let type = HKObjectType.quantityType(forIdentifier: identifier)
        else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Double, Date)?, Error>) in

            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                guard let value =
                        Self.safeDoubleValue(
                            sample.quantity,
                            unit: unit
                        )
                else {
                    continuation.resume(
                        returning: nil
                    )
                    return
                }

                continuation.resume(
                    returning:
                        (value, sample.endDate)
                )
            }

            healthStore.execute(query)
        }
    }

    private func latestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async throws -> (Double, Date)? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Double, Date)?, Error>) in

            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                guard let value =
                        Self.safeDoubleValue(
                            sample.quantity,
                            unit: unit
                        )
                else {
                    continuation.resume(
                        returning: nil
                    )
                    return
                }

                continuation.resume(
                    returning:
                        (value, sample.endDate)
                )
            }

            healthStore.execute(query)
        }
    }

    private func fetchHeartRateStats(
        for workout: HKWorkout
    ) async throws -> (Double?, Double?) {
        guard let type =
                HKObjectType.quantityType(
                    forIdentifier: .heartRate
                )
        else {
            return (nil, nil)
        }

        let unit =
            HKUnit.count()
                .unitDivided(by: .minute())

        if let statistics =
                workout.statistics(
                    for: type
                ) {
            let average =
                Self.safeDoubleValue(
                    statistics
                        .averageQuantity(),
                    unit: unit
                )
            let maximum =
                Self.safeDoubleValue(
                    statistics
                        .maximumQuantity(),
                    unit: unit
                )
            let validAverage =
                average.flatMap {
                    $0 >= 30 &&
                    $0 <= 260
                        ? $0
                        : nil
                }
            let validMaximum =
                maximum.flatMap {
                    $0 >= 30 &&
                    $0 <= 260
                        ? $0
                        : nil
                }

            if validAverage != nil ||
                validMaximum != nil {
                return (
                    validAverage,
                    validMaximum
                )
            }
        }

        let predicate =
            HKQuery.predicateForObjects(
                from: workout
            )
        let samples =
            try await withCheckedThrowingContinuation {
                (
                    continuation:
                        CheckedContinuation<
                            [HKQuantitySample],
                            Error
                        >
                ) in

                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(
                            throwing: error
                        )
                        return
                    }

                    continuation.resume(
                        returning:
                            samples
                                as? [HKQuantitySample]
                                ?? []
                    )
                }

                healthStore.execute(query)
            }

        let values =
            samples.compactMap {
                sample -> Double? in

                guard let value =
                        Self.safeDoubleValue(
                            sample.quantity,
                            unit: unit
                        ),
                      value >= 30,
                      value <= 260
                else {
                    return nil
                }

                return value
            }

        guard !values.isEmpty else {
            return (nil, nil)
        }

        return (
            values.reduce(0, +) /
                Double(values.count),
            values.max()
        )
    }

    private func fastestSegmentDuration(
        in locations: [CLLocation],
        targetDistance: Double
    ) -> TimeInterval? {
        guard targetDistance > 0 else { return nil }

        let points = locations
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 65 }
            .sorted { $0.timestamp < $1.timestamp }

        guard points.count >= 2 else { return nil }

        var cumulativeDistance = Array(repeating: 0.0, count: points.count)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)

            guard elapsed > 0 else {
                cumulativeDistance[index] = cumulativeDistance[index - 1]
                continue
            }

            let distance = current.distance(from: previous)
            let speed = distance / elapsed

            // Reject GPS jumps that would imply a non-running speed.
            let acceptedDistance = distance >= 0 && speed <= 12.5 ? distance : 0
            cumulativeDistance[index] = cumulativeDistance[index - 1] + acceptedDistance
        }

        guard cumulativeDistance.last ?? 0 >= targetDistance else {
            return nil
        }

        var bestDuration: TimeInterval?
        var endIndex = 1

        for startIndex in 0..<(points.count - 1) {
            if endIndex <= startIndex {
                endIndex = startIndex + 1
            }

            while endIndex < points.count &&
                    cumulativeDistance[endIndex] - cumulativeDistance[startIndex] < targetDistance {
                endIndex += 1
            }

            guard endIndex < points.count else { break }

            let previousEndIndex = max(endIndex - 1, startIndex)
            let distanceBeforeEnd =
                cumulativeDistance[previousEndIndex] - cumulativeDistance[startIndex]
            let distanceAtEnd =
                cumulativeDistance[endIndex] - cumulativeDistance[startIndex]
            let finalSegmentDistance = distanceAtEnd - distanceBeforeEnd

            let fraction: Double
            if finalSegmentDistance > 0 {
                fraction = min(
                    max(
                        (targetDistance - distanceBeforeEnd) / finalSegmentDistance,
                        0
                    ),
                    1
                )
            } else {
                fraction = 1
            }

            let finalSegmentTime = points[endIndex].timestamp.timeIntervalSince(
                points[previousEndIndex].timestamp
            )
            let interpolatedEnd = points[previousEndIndex].timestamp.addingTimeInterval(
                finalSegmentTime * fraction
            )
            let duration = interpolatedEnd.timeIntervalSince(points[startIndex].timestamp)

            guard duration > 0 else { continue }

            if bestDuration == nil || duration < bestDuration! {
                bestDuration = duration
            }
        }

        return bestDuration
    }

    private func challengeEndpointsMatch(
        actualLocations: [CLLocation],
        referenceCoordinates: [RouteCoordinate],
        toleranceMeters: Double,
        direction: ChallengeRouteDirection
    ) -> Bool {
        let actual = actualLocations
            .filter {
                $0.horizontalAccuracy >= 0 &&
                $0.horizontalAccuracy <= 65
            }
            .sorted {
                $0.timestamp < $1.timestamp
            }

        guard let actualStart = actual.first,
              let actualFinish = actual.last,
              let referenceStart =
                referenceCoordinates.first,
              let referenceFinish =
                referenceCoordinates.last
        else {
            return false
        }

        let requiredStart = CLLocation(
            latitude: referenceStart.latitude,
            longitude: referenceStart.longitude
        )
        let requiredFinish = CLLocation(
            latitude: referenceFinish.latitude,
            longitude: referenceFinish.longitude
        )

        let direct =
            actualStart.distance(
                from: requiredStart
            ) <= toleranceMeters &&
            actualFinish.distance(
                from: requiredFinish
            ) <= toleranceMeters

        guard direction == .eitherDirection else {
            return direct
        }

        let reverse =
            actualStart.distance(
                from: requiredFinish
            ) <= toleranceMeters &&
            actualFinish.distance(
                from: requiredStart
            ) <= toleranceMeters

        return direct || reverse
    }

    private func workoutForChallenge(uuid: UUID) async throws -> HKWorkout? {
        if let cached = workoutObjects[uuid] {
            return cached
        }

        let predicate = HKQuery.predicateForObject(with: uuid)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<HKWorkout?, Error>) in

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples?.first as? HKWorkout)
            }

            healthStore.execute(query)
        }
    }

    private func challengeEvidenceFailure(
        result: WatchWorkoutResult,
        duration: TimeInterval,
        routeMatch: Double?,
        reason: String
    ) -> ChallengeRunningEvidence {
        ChallengeRunningEvidence(
            startedAt: result.startedAt,
            endedAt: result.endedAt,
            durationSeconds: duration,
            distanceMeters: result.distanceMeters,
            routeMatchPercent: routeMatch,
            score: 0,
            detail: String(format: "%.2f km", result.distanceMeters / 1_000),
            isEligible: false,
            ineligibilityReason: reason
        )
    }

    private func challengeClock(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }

        return String(format: "%d:%02d", minutes, remainder)
    }

    private func routeMatchPercent(
        actualLocations: [CLLocation],
        referenceCoordinates: [RouteCoordinate]
    ) -> Double {
        guard actualLocations.count >= 2,
              referenceCoordinates.count >= 2
        else {
            return 0
        }

        let actual = actualLocations
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 65 }

        guard actual.count >= 2 else { return 0 }

        let referenceLocations = referenceCoordinates.map {
            CLLocation(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }

        let sampleStep = max(referenceLocations.count / 100, 1)
        let samples = stride(
            from: 0,
            to: referenceLocations.count,
            by: sampleStep
        )
        .map { referenceLocations[$0] }

        guard !samples.isEmpty else { return 0 }

        let tolerance = 80.0
        let matched = samples.reduce(0) { count, reference in
            let nearest = actual.lazy
                .map { $0.distance(from: reference) }
                .min() ?? .greatestFiniteMagnitude

            return count + (nearest <= tolerance ? 1 : 0)
        }

        return Double(matched) / Double(samples.count) * 100
    }

    private func maximumRouteDistance(
        in locations: [CLLocation],
        within duration: TimeInterval
    ) -> Double? {
        let points = locations
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 65 }
            .sorted { $0.timestamp < $1.timestamp }

        guard points.count >= 2, duration > 0 else { return nil }

        var cumulative = Array(repeating: 0.0, count: points.count)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)

            guard elapsed > 0 else {
                cumulative[index] = cumulative[index - 1]
                continue
            }

            let distance = current.distance(from: previous)
            let speed = distance / elapsed
            cumulative[index] = cumulative[index - 1] + (
                distance >= 0 && speed <= 12.5 ? distance : 0
            )
        }

        var best = 0.0
        var endIndex = 1

        for startIndex in 0..<(points.count - 1) {
            if endIndex <= startIndex {
                endIndex = startIndex + 1
            }

            let cutoff = points[startIndex].timestamp.addingTimeInterval(duration)

            while endIndex + 1 < points.count &&
                    points[endIndex + 1].timestamp <= cutoff {
                endIndex += 1
            }

            guard endIndex > startIndex else { continue }
            best = max(
                best,
                cumulative[endIndex] - cumulative[startIndex]
            )
        }

        return best > 0 ? best : nil
    }

    private func fetchRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        let predicate = HKQuery.predicateForObjects(from: workout)

        let routes = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKWorkoutRoute], Error>) in

            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
                }
            }

            healthStore.execute(query)
        }

        var allLocations: [CLLocation] = []
        for route in routes {
            allLocations.append(contentsOf: try await locations(for: route))
        }

        return allLocations.sorted { $0.timestamp < $1.timestamp }
    }

    private func locations(
        for route: HKWorkoutRoute
    ) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<
                        [CLLocation],
                        Error
                    >
            ) in
            let accumulator =
                HealthRouteQueryAccumulator()

            let query =
                HKWorkoutRouteQuery(
                    route: route
                ) {
                    _,
                    batch,
                    done,
                    error in

                    guard let result =
                            accumulator.consume(
                                batch: batch,
                                done: done,
                                error: error
                            )
                    else {
                        return
                    }

                    continuation.resume(
                        with: result
                    )
                }

            healthStore.execute(query)
        }
    }
    nonisolated private static func isTemporarilyUnavailableHealthRead(
        _ error: Error
    ) -> Bool {
        guard let healthError =
                error as? HKError
        else {
            return false
        }

        return healthError.code ==
            .errorDatabaseInaccessible
    }

    nonisolated private static func safeDoubleValue(
        _ quantity: HKQuantity?,
        unit: HKUnit
    ) -> Double? {
        guard let quantity,
              quantity.is(compatibleWith: unit)
        else {
            return nil
        }

        let value = quantity.doubleValue(for: unit)
        return value.isFinite ? value : nil
    }

}
