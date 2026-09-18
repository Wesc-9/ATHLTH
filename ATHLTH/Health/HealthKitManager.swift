import Combine
import CoreLocation
import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var workouts: [WorkoutSummary] = []
    @Published private(set) var sleep: SleepSummary = .empty
    @Published private(set) var heart: HeartSummary = .empty
    @Published private(set) var isRefreshing = false
    @Published var authorizationError: String?

    private let healthStore = HKHealthStore()
    private var workoutObjects: [UUID: HKWorkout] = [:]
    private let authorizationFlagKey = "athlth.healthAuthorizationRequested"

    var hasRequestedAuthorization: Bool {
        UserDefaults.standard.bool(forKey: authorizationFlagKey)
    }

    var healthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .activeEnergyBurned,
            .distanceWalkingRunning
        ]

        for identifier in quantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
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
            UserDefaults.standard.set(true, forKey: authorizationFlagKey)
            objectWillChange.send()
            await refreshAll()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    func refreshAll() async {
        guard healthDataAvailable else { return }

        isRefreshing = true
        authorizationError = nil
        defer { isRefreshing = false }

        do {
            let fetched = try await fetchRecentWorkouts(limit: 30)
            workouts = fetched.map(WorkoutSummary.init)
            workoutObjects = Dictionary(uniqueKeysWithValues: fetched.map { ($0.uuid, $0) })
            sleep = try await fetchLatestSleep()
            heart = try await fetchHeartSummary()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    func workoutDetail(for summary: WorkoutSummary) async -> WorkoutDetail {
        guard let workout = workoutObjects[summary.id] else { return WorkoutDetail() }

        async let routeTask = fetchRoute(for: workout)
        async let heartTask = fetchHeartRateStats(for: workout)

        let route = (try? await routeTask) ?? []
        let heartStats = (try? await heartTask) ?? (nil, nil)

        return WorkoutDetail(
            route: route,
            averageHeartRate: heartStats.0,
            maxHeartRate: heartStats.1
        )
    }

    private func fetchRecentWorkouts(limit: Int) async throws -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[HKWorkout], Error>) in

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: nil,
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

        var locations: [CLLocation] = []
        for route in routes {
            locations.append(contentsOf: try await locations(for: route))
        }

        return locations.sorted { $0.timestamp < $1.timestamp }
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
