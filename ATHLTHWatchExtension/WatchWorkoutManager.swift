import CoreLocation
import Foundation
import HealthKit
import WatchConnectivity

enum WatchWorkoutState: Equatable {
    case idle
    case preparing
    case running
    case paused
    case ending
    case completed
    case failed(String)
}

final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    @Published private(set) var state: WatchWorkoutState = .idle
    @Published private(set) var kind: WatchWorkoutKind = .running
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    @Published private(set) var routePoints: [WatchRoutePoint] = []
    @Published private(set) var plannedRoute: WatchRouteTransfer?
    @Published private(set) var completedResult: WatchWorkoutResult?
    @Published private(set) var errorMessage: String?

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var timer: Timer?
    private var startedAt: Date?
    private var finishing = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
    }

    var isWorkoutPresented: Bool {
        switch state {
        case .idle, .failed:
            return false
        case .preparing, .running, .paused, .ending, .completed:
            return true
        }
    }

    var isActive: Bool {
        state == .running || state == .paused
    }

    func start(
        kind: WatchWorkoutKind,
        route: WatchRouteTransfer? = nil
    ) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: kind)
        configuration.locationType = kind == .strength ? .indoor : .outdoor

        await start(
            configuration: configuration,
            kind: kind,
            route: route
        )
    }

    func start(configuration: HKWorkoutConfiguration) async {
        let resolvedKind = kind(for: configuration.activityType)
        await start(
            configuration: configuration,
            kind: resolvedKind,
            route: nil
        )
    }

    func pause() {
        guard state == .running else { return }
        workoutSession?.pause()
    }

    func resume() {
        guard state == .paused else { return }
        workoutSession?.resume()
    }

    func end() {
        guard isActive else { return }
        publishState(.ending)
        workoutSession?.end()
    }

    func reset() {
        stopTimer()
        workoutSession = nil
        workoutBuilder = nil
        routeBuilder = nil
        startedAt = nil
        finishing = false
        publish {
            self.state = .idle
            self.elapsedTime = 0
            self.heartRate = 0
            self.activeCalories = 0
            self.distanceMeters = 0
            self.averageHeartRate = nil
            self.maxHeartRate = nil
            self.routePoints = []
            self.plannedRoute = nil
            self.completedResult = nil
            self.errorMessage = nil
        }
    }

    private func start(
        configuration: HKWorkoutConfiguration,
        kind: WatchWorkoutKind,
        route: WatchRouteTransfer?
    ) async {
        guard !isActive, state != .preparing, state != .ending else { return }

        publish {
            self.state = .preparing
            self.kind = kind
            self.plannedRoute = route
            self.completedResult = nil
            self.errorMessage = nil
            self.elapsedTime = 0
            self.heartRate = 0
            self.activeCalories = 0
            self.distanceMeters = 0
            self.averageHeartRate = nil
            self.maxHeartRate = nil
            self.routePoints = []
        }

        do {
            try await requestAuthorization()

            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()

            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            if configuration.locationType == .outdoor,
               let seriesBuilder = builder.seriesBuilder(
                    for: HKSeriesType.workoutRoute()
               ) as? HKWorkoutRouteBuilder {
                routeBuilder = seriesBuilder
            } else {
                routeBuilder = nil
            }

            workoutSession = session
            workoutBuilder = builder
            finishing = false

            let startDate = Date()
            startedAt = startDate

            session.startActivity(with: startDate)

            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                builder.beginCollection(withStart: startDate) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(
                            throwing: WatchWorkoutError.collectionCouldNotStart
                        )
                    }
                }
            }

            if configuration.locationType == .outdoor {
                locationManager.requestWhenInUseAuthorization()
                locationManager.startUpdatingLocation()
            }

            publishState(.running)
            startTimer()
        } catch {
            fail(error)
        }
    }

    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WatchWorkoutError.healthDataUnavailable
        }

        var shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                shareTypes.insert(type)
                readTypes.insert(type)
            }
        }

        try await healthStore.requestAuthorization(
            toShare: shareTypes,
            read: readTypes
        )
    }

    private func startTimer() {
        stopTimer()

        publish {
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
                [weak self] _ in
                guard let self, let builder = self.workoutBuilder else { return }
                self.publish {
                    self.elapsedTime = builder.elapsedTime
                }
            }
        }
    }

    private func stopTimer() {
        publish {
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    private func finishWorkout(at endDate: Date) {
        guard !finishing, let builder = workoutBuilder else { return }
        finishing = true
        stopTimer()
        locationManager.stopUpdatingLocation()

        updateFinalStatistics(from: builder)

        builder.endCollection(withEnd: endDate) { [weak self] success, error in
            guard let self else { return }

            if let error {
                self.fail(error)
                return
            }

            guard success else {
                self.fail(WatchWorkoutError.collectionCouldNotEnd)
                return
            }

            builder.finishWorkout { [weak self] workout, error in
                guard let self else { return }

                if let error {
                    self.fail(error)
                    return
                }

                guard let workout else {
                    self.fail(WatchWorkoutError.workoutCouldNotSave)
                    return
                }

                self.finishRouteIfNeeded(
                    workout: workout,
                    endDate: endDate
                )
            }
        }
    }

    private func finishRouteIfNeeded(
        workout: HKWorkout,
        endDate: Date
    ) {
        guard let routeBuilder, !routePoints.isEmpty else {
            complete(workout: workout, endDate: endDate)
            return
        }

        routeBuilder.finishRoute(with: workout, metadata: nil) {
            [weak self] _, error in
            guard let self else { return }

            if let error {
                self.publish {
                    self.errorMessage = "Workout saved, but the GPS route could not be attached: \(error.localizedDescription)"
                }
            }

            self.complete(workout: workout, endDate: endDate)
        }
    }

    private func complete(
        workout: HKWorkout,
        endDate: Date
    ) {
        let start = startedAt ?? workout.startDate
        let result = WatchWorkoutResult(
            id: UUID(),
            kind: kind,
            healthKitWorkoutUUID: workout.uuid,
            startedAt: start,
            endedAt: endDate,
            duration: max(workout.duration, elapsedTime),
            activeCalories: activeCalories,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            routePoints: routePoints
        )

        sendToPhone(result)

        publish {
            self.completedResult = result
            self.elapsedTime = result.duration
            self.state = .completed
        }
    }

    private func sendToPhone(_ result: WatchWorkoutResult) {
        guard
            WCSession.isSupported(),
            let data = try? JSONEncoder().encode(result)
        else {
            return
        }

        WCSession.default.transferUserInfo([
            WatchTransferMetadataKey.kind: WatchTransferKind.workoutResult.rawValue,
            WatchTransferMetadataKey.payload: data
        ])
    }

    private func updateStatistics(
        _ types: Set<HKSampleType>,
        builder: HKLiveWorkoutBuilder
    ) {
        let heartType = HKObjectType.quantityType(forIdentifier: .heartRate)
        let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)

        if let heartType, types.contains(heartType),
           let statistics = builder.statistics(for: heartType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            let latest = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? heartRate
            let average = statistics.averageQuantity()?.doubleValue(for: unit)
            let maximum = statistics.maximumQuantity()?.doubleValue(for: unit)

            publish {
                self.heartRate = latest
                self.averageHeartRate = average ?? self.averageHeartRate
                self.maxHeartRate = maximum ?? self.maxHeartRate
            }
        }

        if let energyType, types.contains(energyType),
           let statistics = builder.statistics(for: energyType),
           let quantity = statistics.sumQuantity() {
            publish {
                self.activeCalories = quantity.doubleValue(for: .kilocalorie())
            }
        }

        if let distanceType, types.contains(distanceType),
           let statistics = builder.statistics(for: distanceType),
           let quantity = statistics.sumQuantity() {
            publish {
                self.distanceMeters = quantity.doubleValue(for: .meter())
            }
        }
    }

    private func updateFinalStatistics(from builder: HKLiveWorkoutBuilder) {
        var types = Set<HKSampleType>()

        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning
        ] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        updateStatistics(types, builder: builder)
    }

    private func activityType(
        for kind: WatchWorkoutKind
    ) -> HKWorkoutActivityType {
        switch kind {
        case .running: return .running
        case .walking: return .walking
        case .strength: return .traditionalStrengthTraining
        }
    }

    private func kind(
        for activityType: HKWorkoutActivityType
    ) -> WatchWorkoutKind {
        switch activityType {
        case .walking:
            return .walking
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:
            return .strength
        default:
            return .running
        }
    }

    private func fail(_ error: Error) {
        stopTimer()
        locationManager.stopUpdatingLocation()
        publish {
            self.errorMessage = error.localizedDescription
            self.state = .failed(error.localizedDescription)
        }
    }

    private func publishState(_ newState: WatchWorkoutState) {
        publish {
            self.state = newState
        }
    }

    private func publish(_ changes: @escaping () -> Void) {
        if Thread.isMainThread {
            changes()
        } else {
            DispatchQueue.main.async(execute: changes)
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        switch toState {
        case .running:
            publishState(.running)
        case .paused:
            publishState(.paused)
        case .ended:
            finishWorkout(at: date)
        default:
            break
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        fail(error)
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        updateStatistics(collectedTypes, builder: workoutBuilder)
    }
}

extension WatchWorkoutManager: CLLocationManagerDelegate {
    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let filtered = locations.filter {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50
        }

        guard !filtered.isEmpty else { return }

        routeBuilder?.insertRouteData(filtered) { [weak self] success, error in
            guard let self, !success, let error else { return }
            self.publish {
                self.errorMessage = "GPS route update failed: \(error.localizedDescription)"
            }
        }

        publish {
            let startIndex = self.routePoints.count
            self.routePoints.append(
                contentsOf: filtered.enumerated().map { offset, location in
                    WatchRoutePoint(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.altitude,
                        sequence: startIndex + offset
                    )
                }
            )
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        publish {
            self.errorMessage = "Location: \(error.localizedDescription)"
        }
    }
}

enum WatchWorkoutError: LocalizedError {
    case healthDataUnavailable
    case collectionCouldNotStart
    case collectionCouldNotEnd
    case workoutCouldNotSave

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "HealthKit isn't available on this Apple Watch."
        case .collectionCouldNotStart:
            return "ATHLTH couldn't start workout data collection."
        case .collectionCouldNotEnd:
            return "ATHLTH couldn't finish workout data collection."
        case .workoutCouldNotSave:
            return "ATHLTH couldn't save the workout to Apple Health."
        }
    }
}
