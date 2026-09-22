import Combine
import CoreLocation
import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var workouts: [WorkoutSummary] = []
    @Published private(set) var sleep: SleepSummary = .empty
    @Published private(set) var heart: HeartSummary = .empty
    @Published private(set) var training: TrainingHealthSummary = .empty
    @Published private(set) var personalDetails: HealthProfileBasics = .empty
    @Published private(set) var isRefreshing = false
    @Published var authorizationError: String?
    @Published private(set) var backgroundDeliveryTestResult: String?
    @Published private(set) var routeCapabilityTestResult: String?
    @Published private(set) var lastSuccessfulRefreshAt: Date?
    @Published private(set) var backgroundSyncError: String?

    private let healthStore = HKHealthStore()
    private var workoutObjects: [UUID: HKWorkout] = [:]
    private var observerQueries: [HKObserverQuery] = []
    private var profilePerformanceCache: (stats: ProfilePerformanceStats, generatedAt: Date)?
    private let legacyAuthorizationFlagKey = "athlth.healthAuthorizationRequested"
    private let authorizationVersionKey = "athlth.healthAuthorizationVersion"
    private let currentAuthorizationVersion = 2

    init() {
        // Apple recommends installing observer queries as early as possible
        // so HealthKit can deliver background updates immediately after launch.
        if (
            UserDefaults.standard.integer(forKey: authorizationVersionKey) >= currentAuthorizationVersion ||
            UserDefaults.standard.bool(forKey: legacyAuthorizationFlagKey)
        ),
           HKHealthStore.isHealthDataAvailable() {
            startBackgroundObservers()
        }
    }

    var hasRequestedAuthorization: Bool {
        UserDefaults.standard.integer(forKey: authorizationVersionKey) >= currentAuthorizationVersion
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

    func requestAuthorization() async {
        authorizationError = nil

        guard healthDataAvailable else {
            authorizationError = "Apple Health data isn't available on this device."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: legacyAuthorizationFlagKey)
            UserDefaults.standard.set(currentAuthorizationVersion, forKey: authorizationVersionKey)
            objectWillChange.send()
            await refreshPersonalDetails()
            await refreshAll()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    func configureBackgroundSync(allowed: Bool) async {
        guard healthDataAvailable else { return }

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
            (.heartRate, .immediate),
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
            (.runningSpeed, .immediate),
            (.runningPower, .immediate),
            (.cyclingSpeed, .immediate),
            (.cyclingPower, .immediate),
            (.swimmingStrokeCount, .immediate)
        ]

        for (identifier, frequency) in quantityTypes {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                registrations.append((type, frequency))
            }
        }

        var failures: [String] = []

        for (type, frequency) in registrations {
            let result: (Bool, String?) = await withCheckedContinuation { continuation in
                healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
                    continuation.resume(
                        returning: (success, error?.localizedDescription)
                    )
                }
            }

            if !result.0 {
                failures.append(
                    result.1 ?? "HealthKit rejected background delivery for \(type.identifier)."
                )
            }
        }

        if !failures.isEmpty {
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
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                defer { completionHandler() }
                guard error == nil else { return }

                Task { @MainActor [weak self] in
                    await self?.refreshAll()
                }
            }

            observerQueries.append(query)
            healthStore.execute(query)
        }
    }

    func refreshAll() async {
        guard healthDataAvailable else { return }

        isRefreshing = true
        authorizationError = nil
        defer { isRefreshing = false }

        do {
            let end = Date()
            let start = Calendar.current.date(byAdding: .month, value: -3, to: end)
                ?? end.addingTimeInterval(-7_776_000)

            let fetched = try await fetchWorkouts(
                startDate: start,
                endDate: end,
                limit: 100
            )
            workouts = fetched.map(WorkoutSummary.init)
            workoutObjects = Dictionary(uniqueKeysWithValues: fetched.map { ($0.uuid, $0) })
            sleep = try await fetchLatestSleep()
            heart = try await fetchHeartSummary()
            training = try await fetchTrainingSummary()
            await refreshPersonalDetails()
            lastSuccessfulRefreshAt = Date()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    func workoutHistory() async throws -> [WorkoutSummary] {
        try await fetchAllWorkouts()
            .map(WorkoutSummary.init)
            .sorted { $0.startDate > $1.startDate }
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
            activeWorkoutDays: current.activeWorkoutDays,
            buckets: current.buckets,
            previousWorkoutCount: previous.workoutCount,
            previousTotalSteps: previous.totalSteps,
            previousAverageDailySteps: previous.averageDailySteps,
            previousAverageSleepDuration: previous.averageSleepDuration,
            previousTrainingDuration: previous.trainingDuration
        )
    }

    func trophySnapshot() async throws -> TrophyHealthSnapshot {
        let workouts = try await fetchAllWorkouts()
            .sorted { $0.startDate < $1.startDate }

        let workoutThresholds = [10, 50, 100, 250]
        var workoutCountReachedAt: [Int: Date] = [:]

        for (index, workout) in workouts.enumerated() {
            let count = index + 1
            if workoutThresholds.contains(count) {
                workoutCountReachedAt[count] = workout.endDate
            }
        }

        let runThresholds = [25_000, 100_000, 500_000, 1_000_000]
        var runningDistanceReachedAt: [Int: Date] = [:]
        var cumulativeRunDistance = 0.0
        var longestRunMeters = 0.0
        var firstFiveKDate: Date?
        var firstHalfMarathonDate: Date?
        var firstMarathonDate: Date?

        for workout in workouts where workout.workoutActivityType == .running {
            let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
            guard distance > 0 else { continue }

            longestRunMeters = max(longestRunMeters, distance)
            cumulativeRunDistance += distance

            if firstFiveKDate == nil, distance >= 5_000 {
                firstFiveKDate = workout.endDate
            }

            if firstHalfMarathonDate == nil, distance >= 21_097.5 {
                firstHalfMarathonDate = workout.endDate
            }

            if firstMarathonDate == nil, distance >= 42_195 {
                firstMarathonDate = workout.endDate
            }

            for threshold in runThresholds
            where runningDistanceReachedAt[threshold] == nil &&
                    cumulativeRunDistance >= Double(threshold) {
                runningDistanceReachedAt[threshold] = workout.endDate
            }
        }

        let calendar = Calendar.current
        let workoutDays = Array(
            Set(workouts.map { calendar.startOfDay(for: $0.startDate) })
        )
        .sorted()

        let streakThresholds = [3, 7, 14, 30]
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

        let sleepThresholds = [7, 30, 100]
        var qualifyingSleepNightsReachedAt: [Int: Date] = [:]

        for (index, day) in qualifyingSleepDays.enumerated() {
            let count = index + 1
            if sleepThresholds.contains(count) {
                qualifyingSleepNightsReachedAt[count] = day
            }
        }

        return TrophyHealthSnapshot(
            workoutCount: workouts.count,
            workoutCountReachedAt: workoutCountReachedAt,
            totalRunningDistanceMeters: cumulativeRunDistance,
            runningDistanceReachedAt: runningDistanceReachedAt,
            longestRunMeters: longestRunMeters,
            firstFiveKDate: firstFiveKDate,
            firstHalfMarathonDate: firstHalfMarathonDate,
            firstMarathonDate: firstMarathonDate,
            longestWorkoutStreakDays: longestStreak,
            workoutStreakReachedAt: workoutStreakReachedAt,
            qualifyingSleepNights: qualifyingSleepDays.count,
            qualifyingSleepNightsReachedAt: qualifyingSleepNightsReachedAt
        )
    }

    func challengeRunningEvidence(
        for result: WatchWorkoutResult,
        rules: ATHLTHChallengeRules
    ) async -> ChallengeRunningEvidence {
        let elapsedDuration = max(
            result.endedAt.timeIntervalSince(result.startedAt),
            0
        )
        let movingDuration = max(result.duration, 0)
        let selectedDuration = rules.timeBasis == .elapsed
            ? elapsedDuration
            : movingDuration

        var route: [CLLocation] = []

        if let workoutUUID = result.healthKitWorkoutUUID,
           let workout = try? await workoutForChallenge(uuid: workoutUUID) {
            route = (try? await fetchRoute(for: workout)) ?? []
        }

        let routeNeeded =
            rules.gpsRequired ||
            rules.route != nil ||
            rules.scoring == .fastestDistance ||
            rules.scoring == .farthestInTime

        if routeNeeded && route.count < 2 {
            if rules.scoring == .mostDistance && !rules.gpsRequired && rules.route == nil {
                return ChallengeRunningEvidence(
                    startedAt: result.startedAt,
                    endedAt: result.endedAt,
                    durationSeconds: selectedDuration,
                    distanceMeters: result.distanceMeters,
                    routeMatchPercent: nil,
                    score: result.distanceMeters,
                    detail: String(format: "%.2f km", result.distanceMeters / 1_000),
                    isEligible: true,
                    ineligibilityReason: nil
                )
            }

            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds: selectedDuration,
                distanceMeters: result.distanceMeters,
                routeMatchPercent: nil,
                score: 0,
                detail: String(format: "%.2f km", result.distanceMeters / 1_000),
                isEligible: false,
                ineligibilityReason: "No qualifying GPS route was available for this attempt."
            )
        }

        var routeMatch: Double?

        if let requiredRoute = rules.route {
            routeMatch = routeMatchPercent(
                actualLocations: route,
                referenceCoordinates: requiredRoute.coordinates
            )

            let requiredMatch = rules.minimumRouteMatchPercent ?? 90

            if (routeMatch ?? 0) < requiredMatch {
                return ChallengeRunningEvidence(
                    startedAt: result.startedAt,
                    endedAt: result.endedAt,
                    durationSeconds: selectedDuration,
                    distanceMeters: result.distanceMeters,
                    routeMatchPercent: routeMatch,
                    score: 0,
                    detail: String(
                        format: "%.0f%% route match",
                        routeMatch ?? 0
                    ),
                    isEligible: false,
                    ineligibilityReason: String(
                        format: "Route match %.0f%% · required %.0f%%.",
                        routeMatch ?? 0,
                        requiredMatch
                    )
                )
            }
        }

        switch rules.scoring {
        case .fastestDistance:
            guard let target = rules.targetDistanceMeters, target > 0 else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason: "This challenge has no valid target distance."
                )
            }

            guard result.distanceMeters >= target else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason: String(
                        format: "%.2f km completed · %.2f km required.",
                        result.distanceMeters / 1_000,
                        target / 1_000
                    )
                )
            }

            guard let segmentDuration = fastestSegmentDuration(
                in: route,
                targetDistance: target
            ) else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason: "ATHLTH could not verify the target distance from the GPS track."
                )
            }

            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds: segmentDuration,
                distanceMeters: target,
                routeMatchPercent: routeMatch,
                score: segmentDuration,
                detail: "\(challengeClock(segmentDuration)) · \(String(format: "%.2f", target / 1_000)) km",
                isEligible: true,
                ineligibilityReason: nil
            )

        case .fastestRoute:
            guard rules.route != nil else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason: "A specific route is required for this challenge."
                )
            }

            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds: selectedDuration,
                distanceMeters: result.distanceMeters,
                routeMatchPercent: routeMatch,
                score: selectedDuration,
                detail: "\(challengeClock(selectedDuration)) · \(String(format: "%.0f%%", routeMatch ?? 0)) route match",
                isEligible: true,
                ineligibilityReason: nil
            )

        case .farthestInTime:
            guard let targetDuration = rules.targetDurationSeconds,
                  targetDuration > 0
            else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason: "This challenge has no valid time target."
                )
            }

            guard let distance = maximumRouteDistance(
                in: route,
                within: targetDuration
            ) else {
                return challengeEvidenceFailure(
                    result: result,
                    duration: selectedDuration,
                    routeMatch: routeMatch,
                    reason: "ATHLTH could not verify distance inside the required time window."
                )
            }

            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds: targetDuration,
                distanceMeters: distance,
                routeMatchPercent: routeMatch,
                score: distance,
                detail: "\(String(format: "%.2f km", distance / 1_000)) in \(challengeClock(targetDuration))",
                isEligible: true,
                ineligibilityReason: nil
            )

        case .mostDistance:
            return ChallengeRunningEvidence(
                startedAt: result.startedAt,
                endedAt: result.endedAt,
                durationSeconds: selectedDuration,
                distanceMeters: result.distanceMeters,
                routeMatchPercent: routeMatch,
                score: result.distanceMeters,
                detail: String(format: "%.2f km", result.distanceMeters / 1_000),
                isEligible: true,
                ineligibilityReason: nil
            )

        case .heaviestWeight, .mostReps, .exerciseVolume, .workoutVolume:
            return challengeEvidenceFailure(
                result: result,
                duration: selectedDuration,
                routeMatch: routeMatch,
                reason: "This is not a running scoring rule."
            )
        }
    }

    func profilePerformanceStats(
        forceRefresh: Bool = false
    ) async throws -> ProfilePerformanceStats {
        if !forceRefresh,
           let cached = profilePerformanceCache,
           Date().timeIntervalSince(cached.generatedAt) < 600 {
            return cached.stats
        }

        let allWorkouts = try await fetchAllWorkouts()
        let workoutsByDate = allWorkouts.sorted { $0.startDate < $1.startDate }

        let longestWorkout = allWorkouts.max { lhs, rhs in
            lhs.duration < rhs.duration
        }

        let longestDistanceWorkout = allWorkouts
            .filter { ($0.totalDistance?.doubleValue(for: .meter()) ?? 0) > 0 }
            .max { lhs, rhs in
                (lhs.totalDistance?.doubleValue(for: .meter()) ?? 0) <
                (rhs.totalDistance?.doubleValue(for: .meter()) ?? 0)
            }

        let runningWorkouts = workoutsByDate.filter {
            $0.workoutActivityType == .running &&
            ($0.totalDistance?.doubleValue(for: .meter()) ?? 0) > 0
        }

        let longestRun = runningWorkouts.max { lhs, rhs in
            (lhs.totalDistance?.doubleValue(for: .meter()) ?? 0) <
            (rhs.totalDistance?.doubleValue(for: .meter()) ?? 0)
        }

        let totalRunningDistance = runningWorkouts.reduce(0.0) { partial, workout in
            partial + (workout.totalDistance?.doubleValue(for: .meter()) ?? 0)
        }

        var fastestOneK: TimedDistancePerformanceRecord?
        var fastestFiveK: TimedDistancePerformanceRecord?
        var fastestMarathon: TimedDistancePerformanceRecord?

        for workout in runningWorkouts {
            let reportedDistance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
            guard reportedDistance >= 1_000,
                  let route = try? await fetchRoute(for: workout),
                  route.count >= 2
            else {
                continue
            }

            if let duration = fastestSegmentDuration(
                in: route,
                targetDistance: 1_000
            ),
               fastestOneK == nil || duration < fastestOneK!.duration {
                fastestOneK = TimedDistancePerformanceRecord(
                    distanceMeters: 1_000,
                    duration: duration,
                    date: workout.startDate,
                    workoutID: workout.uuid
                )
            }

            if reportedDistance >= 5_000,
               let duration = fastestSegmentDuration(
                    in: route,
                    targetDistance: 5_000
               ),
               fastestFiveK == nil || duration < fastestFiveK!.duration {
                fastestFiveK = TimedDistancePerformanceRecord(
                    distanceMeters: 5_000,
                    duration: duration,
                    date: workout.startDate,
                    workoutID: workout.uuid
                )
            }

            if reportedDistance >= 42_195,
               let duration = fastestSegmentDuration(
                    in: route,
                    targetDistance: 42_195
               ),
               fastestMarathon == nil || duration < fastestMarathon!.duration {
                fastestMarathon = TimedDistancePerformanceRecord(
                    distanceMeters: 42_195,
                    duration: duration,
                    date: workout.startDate,
                    workoutID: workout.uuid
                )
            }
        }

        let stats = ProfilePerformanceStats(
            fastestOneKilometer: fastestOneK,
            fastestFiveKilometers: fastestFiveK,
            fastestMarathon: fastestMarathon,
            longestWorkoutDuration: longestWorkout?.duration,
            longestWorkoutDate: longestWorkout?.startDate,
            longestWorkoutActivity: longestWorkout.map {
                WorkoutActivity(healthKitType: $0.workoutActivityType)
            },
            longestWorkoutDistanceMeters: longestDistanceWorkout?.totalDistance?
                .doubleValue(for: .meter()),
            longestWorkoutDistanceDate: longestDistanceWorkout?.startDate,
            longestWorkoutDistanceActivity: longestDistanceWorkout.map {
                WorkoutActivity(healthKitType: $0.workoutActivityType)
            },
            longestRunMeters: longestRun?.totalDistance?.doubleValue(for: .meter()),
            longestRunDate: longestRun?.startDate,
            totalWorkoutCount: allWorkouts.count,
            totalTrainingDuration: allWorkouts.reduce(0) { $0 + $1.duration },
            totalRunningDistanceMeters: totalRunningDistance
        )

        profilePerformanceCache = (stats, Date())
        return stats
    }

    func personalRecords() async throws -> [HealthPersonalRecord] {
        let workouts = try await fetchAllWorkouts()
        var records: [HealthPersonalRecord] = []

        if let workout = workouts
            .filter({ $0.workoutActivityType == .running && $0.totalDistance != nil })
            .max(by: {
                ($0.totalDistance?.doubleValue(for: .meter()) ?? 0) <
                ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
            }),
           let distance = workout.totalDistance?.doubleValue(for: .meter()),
           distance > 0 {
            records.append(
                HealthPersonalRecord(
                    kind: .longestRun,
                    value: distance,
                    date: workout.startDate
                )
            )
        }

        let fiveKCandidates = workouts.filter {
            guard $0.workoutActivityType == .running,
                  let distance = $0.totalDistance?.doubleValue(for: .meter())
            else {
                return false
            }

            return distance >= 5_000
        }

        var fastestFiveK: (duration: TimeInterval, date: Date)?

        for workout in fiveKCandidates {
            guard let route = try? await fetchRoute(for: workout),
                  let duration = fastestSegmentDuration(in: route, targetDistance: 5_000)
            else {
                continue
            }

            if fastestFiveK == nil || duration < fastestFiveK!.duration {
                fastestFiveK = (duration, workout.startDate)
            }
        }

        if let fastestFiveK {
            records.append(
                HealthPersonalRecord(
                    kind: .fastest5K,
                    value: fastestFiveK.duration,
                    date: fastestFiveK.date
                )
            )
        }

        if let workout = workouts
            .filter({ $0.workoutActivityType == .cycling && $0.totalDistance != nil })
            .max(by: {
                ($0.totalDistance?.doubleValue(for: .meter()) ?? 0) <
                ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
            }),
           let distance = workout.totalDistance?.doubleValue(for: .meter()),
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
                $0.totalDistance != nil
            })
            .max(by: {
                ($0.totalDistance?.doubleValue(for: .meter()) ?? 0) <
                ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
            }),
           let distance = workout.totalDistance?.doubleValue(for: .meter()),
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

        if let workout = workouts
            .filter({ $0.totalEnergyBurned != nil })
            .max(by: {
                ($0.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0) <
                ($1.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)
            }),
           let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
           calories > 0 {
            records.append(
                HealthPersonalRecord(
                    kind: .mostActiveCalories,
                    value: calories,
                    date: workout.startDate
                )
            )
        }

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
                .filter({ $0.totalDistance != nil })
                .max(by: {
                    ($0.totalDistance?.doubleValue(for: .meter()) ?? 0) <
                    ($1.totalDistance?.doubleValue(for: .meter()) ?? 0)
                }),
                let distance = workout.totalDistance?.doubleValue(for: .meter())
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
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
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
        guard let workout = workoutObjects[summary.id] else { return WorkoutDetail() }

        async let routeTask = fetchRoute(for: workout)
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

        let route = (try? await routeTask) ?? []
        let heartStats = (try? await heartTask) ?? (nil, nil)

        return WorkoutDetail(
            route: route,
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

    private func fetchAllWorkouts() async throws -> [HKWorkout] {
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
        let start = Calendar.current.date(byAdding: .hour, value: -36, to: end)
            ?? end.addingTimeInterval(-129_600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
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

        var result = SleepSummary.empty
        var asleepSamples: [HKCategorySample] = []

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }

            switch value {
            case .asleepCore:
                result.core += duration
                result.totalAsleep += duration
                asleepSamples.append(sample)
            case .asleepDeep:
                result.deep += duration
                result.totalAsleep += duration
                asleepSamples.append(sample)
            case .asleepREM:
                result.rem += duration
                result.totalAsleep += duration
                asleepSamples.append(sample)
            case .asleepUnspecified:
                result.totalAsleep += duration
                asleepSamples.append(sample)
            case .awake:
                result.awake += duration
            default:
                break
            }
        }

        result.sleepStart = asleepSamples.first?.startDate
        result.sleepEnd = asleepSamples.last?.endDate
        return result
    }

    private func fetchHeartSummary() async throws -> HeartSummary {
        async let latest = latestQuantity(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let resting = latestQuantity(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrv = latestQuantity(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli)
        )

        let latestValue = try await latest
        let restingValue = try await resting
        let hrvValue = try await hrv

        return HeartSummary(
            latestHeartRate: latestValue?.0,
            latestHeartRateDate: latestValue?.1,
            restingHeartRate: restingValue?.0,
            restingHeartRateDate: restingValue?.1,
            hrvMilliseconds: hrvValue?.0,
            hrvDate: hrvValue?.1
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
        async let vo2 = latestQuantity(
            identifier: .vo2Max,
            unit: HKUnit(from: "ml/kg*min")
        )
        async let walkingHeartRate = latestQuantity(
            identifier: .walkingHeartRateAverage,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let oxygen = latestQuantity(
            identifier: .oxygenSaturation,
            unit: .percent()
        )
        async let respiratory = latestQuantity(
            identifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )

        return TrainingHealthSummary(
            stepsToday: try await steps,
            activeEnergyKilocaloriesToday: try await activeEnergy,
            basalEnergyKilocaloriesToday: try await basalEnergy,
            exerciseMinutesToday: try await exerciseMinutes,
            distanceWalkingRunningMetersToday: try await walkingRunningDistance,
            distanceCyclingMetersToday: try await cyclingDistance,
            distanceSwimmingMetersToday: try await swimmingDistance,
            flightsClimbedToday: try await flights,
            vo2Max: try await vo2?.0,
            walkingHeartRateAverage: try await walkingHeartRate?.0,
            oxygenSaturationPercent: try await oxygen?.0,
            respiratoryRate: try await respiratory?.0
        )
    }

    private struct ProgressMetrics {
        let workoutCount: Int
        let totalSteps: Double?
        let averageDailySteps: Double?
        let averageSleepDuration: TimeInterval?
        let trainingDuration: TimeInterval
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

        let workouts = try await workoutsTask
        let stepsByDay = try await stepsTask
        let sleepByDay = try await sleepTask

        let calendar = Calendar.current
        let totalTrainingDuration = workouts.reduce(0) { $0 + $1.duration }
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

    private func dailyCumulativeQuantities(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return [:]
        }

        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: startDate)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[Date: Double], Error>) in

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results else {
                    continuation.resume(returning: [:])
                    return
                }

                var values: [Date: Double] = [:]
                results.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let day = calendar.startOfDay(for: statistics.startDate)
                    values[day] = quantity.doubleValue(for: unit)
                }

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
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

        var durations: [Date: TimeInterval] = [:]

        for sample in samples {
            guard sample.endDate >= startDate && sample.endDate <= endDate,
                  let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            else {
                continue
            }

            switch value {
            case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
                let wakeDay = calendar.startOfDay(for: sample.endDate)
                durations[wakeDay, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
            default:
                continue
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
                    trainingDuration: bucketWorkouts.reduce(0) { $0 + $1.duration }
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

    private func summedQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
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
                    returning: result?.sumQuantity()?.doubleValue(for: unit)
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
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Double?, Error>) in

            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: option
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let quantity: HKQuantity?
                if option.contains(.cumulativeSum) {
                    quantity = result?.sumQuantity()
                } else if option.contains(.discreteAverage) {
                    quantity = result?.averageQuantity()
                } else {
                    quantity = nil
                }

                continuation.resume(
                    returning: quantity?.doubleValue(for: unit)
                )
            }

            healthStore.execute(query)
        }
    }

    private func latestQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date
    ) async throws -> (Double, Date)? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
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

                continuation.resume(
                    returning: (sample.quantity.doubleValue(for: unit), sample.endDate)
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

                continuation.resume(
                    returning: (sample.quantity.doubleValue(for: unit), sample.endDate)
                )
            }

            healthStore.execute(query)
        }
    }

    private func fetchHeartRateStats(for workout: HKWorkout) async throws -> (Double?, Double?) {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil)
        }

        let predicate = HKQuery.predicateForObjects(from: workout)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let samples = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKQuantitySample], Error>) in

            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
            }

            healthStore.execute(query)
        }

        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        guard !values.isEmpty else { return (nil, nil) }

        return (
            values.reduce(0, +) / Double(values.count),
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

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[CLLocation], Error>) in

            var result: [CLLocation] = []
            var finished = false

            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                guard !finished else { return }

                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }

                result.append(contentsOf: batch ?? [])

                if done {
                    finished = true
                    continuation.resume(returning: result)
                }
            }

            healthStore.execute(query)
        }
    }
}
