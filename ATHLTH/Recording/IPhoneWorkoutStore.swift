import CoreLocation
import Foundation
import HealthKit

struct PhoneRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let accuracy: Double
    let timestamp: Date
    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude; longitude = location.coordinate.longitude
        altitude = location.altitude; accuracy = location.horizontalAccuracy; timestamp = location.timestamp
    }
    var location: CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: altitude, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: timestamp)
    }
}

struct PhoneWorkout: Codable, Identifiable {
    var id = UUID()
    var walking: Bool
    var start: Date
    var end: Date?
    var accumulatedSeconds: TimeInterval = 0
    var resumedAt: Date?
    var lastCheckpoint: Date
    var distanceMeters: Double = 0
    var points: [PhoneRoutePoint] = []
    var healthID: UUID?
    var title: String { walking ? "iPhone Walk" : "iPhone Run" }
    func elapsed(at date: Date) -> TimeInterval {
        accumulatedSeconds + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

@MainActor
final class IPhoneWorkoutStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var active: PhoneWorkout?
    @Published private(set) var history: [PhoneWorkout] = []
    @Published var showingWorkout = false
    @Published private(set) var message: String?
    @Published private(set) var saving = false
    private var accountID: UUID?
    private var pendingWalking: Bool?
    private var lastLocation: CLLocation?
    private var lastActiveCheckpointWriteAt: Date?
    private let activeCheckpointInterval: TimeInterval = 5
    private let manager = CLLocationManager()
    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        pause()
        manager.stopUpdatingLocation()
        accountID = userID
        pendingWalking = nil
        active = userID.flatMap { AccountLocalStorage.read(PhoneWorkout.self, name: "phoneActive", userID: $0) }
        if var workout = active, workout.resumedAt != nil {
            workout.accumulatedSeconds = workout.elapsed(at: workout.lastCheckpoint)
            workout.resumedAt = nil
            active = workout
        }
        history = userID.flatMap { AccountLocalStorage.read([PhoneWorkout].self, name: "phoneHistory", userID: $0) } ?? []
        if let active, history.contains(where: { $0.id == active.id }) { self.active = nil }
        showingWorkout = false
        message = active == nil ? nil : "Recovered workout paused at the last saved checkpoint. Resume when you are ready."
        lastActiveCheckpointWriteAt = nil
    }

    func start(walking: Bool) {
        guard accountID != nil, !saving else { return }
        showingWorkout = true
        guard active == nil else { return }
        pendingWalking = walking
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { beginIfAuthorized() }
    }

    private func beginIfAuthorized() {
        guard let walking = pendingWalking else { return }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            message = "Allow location access in iPhone Settings to record an outdoor workout."
            return
        }
        pendingWalking = nil
        let now = Date()
        active = PhoneWorkout(walking: walking, start: now, resumedAt: now, lastCheckpoint: now)
        message = "Waiting for a reliable GPS signal. Keep your iPhone with you."
        lastLocation = nil
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        persistActiveCheckpoint(force: true)
    }

    func pause() {
        guard var workout = active, workout.resumedAt != nil else { return }
        let now = Date()
        workout.accumulatedSeconds = workout.elapsed(at: now)
        workout.resumedAt = nil
        workout.lastCheckpoint = now
        active = workout
        manager.stopUpdatingLocation()
        lastLocation = nil
        persistActiveCheckpoint(force: true)
    }

    func resume() {
        guard var workout = active, workout.resumedAt == nil, !saving else { return }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            message = "Allow location access in iPhone Settings before resuming."
            return
        }
        workout.resumedAt = Date()
        workout.lastCheckpoint = Date()
        active = workout
        lastLocation = nil
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        persistActiveCheckpoint(force: true)
    }

    func finish() async {
        guard !saving else { return }
        pause()
        guard var workout = active, let userID = accountID else { return }
        workout.end = Date()
        history.insert(workout, at: 0)
        active = nil
        persistActiveCheckpoint(force: true)
        persistHistory()
        await saveToHealth(workout, userID: userID)
    }

    func retryHealthSave(_ workout: PhoneWorkout) async {
        guard let accountID, !saving else { return }
        await saveToHealth(workout, userID: accountID)
    }

    private func saveToHealth(_ workout: PhoneWorkout, userID: UUID) async {
        saving = true
        defer { saving = false }
        guard HKHealthStore.isHealthDataAvailable(), let end = workout.end,
              healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            message = "Workout saved in ATHLTH. Enable Apple Health workout access to copy it to your history."
            return
        }
        do {
            // Idempotent retry: a successful Health save may precede an interrupted local update.
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [workout.id.uuidString])
            let existing: HKWorkout? = try await withCheckedThrowingContinuation { continuation in
                healthStore.execute(HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples?.first as? HKWorkout) }
                })
            }
            guard accountID == userID else { return }
            let saved: HKWorkout
            if let existing { saved = existing }
            else {
                saved = HKWorkout(activityType: workout.walking ? .walking : .running, start: workout.start, end: end, duration: workout.accumulatedSeconds, totalEnergyBurned: nil, totalDistance: HKQuantity(unit: .meter(), doubleValue: workout.distanceMeters), metadata: [HKMetadataKeyExternalUUID: workout.id.uuidString, HKMetadataKeyIndoorWorkout: false])
                try await healthStore.save(saved)
                // Route failure must not create a duplicate workout on retry.
                if !workout.points.isEmpty, healthStore.authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingAuthorized {
                    let route = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                    do {
                        try await route.insertRouteData(workout.points.map(\.location))
                        _ = try await route.finishRoute(with: saved, metadata: nil)
                    } catch { message = "Workout saved to Apple Health; the GPS route remains available in ATHLTH." }
                }
            }
            guard accountID == userID else { return }
            if let index = history.firstIndex(where: { $0.id == workout.id }) { history[index].healthID = saved.uuid }
            persistHistory()
            if message?.contains("GPS route remains") != true { message = "Workout saved to ATHLTH and Apple Health." }
            await HealthKitManager.shared.refreshAll()
        } catch {
            if accountID == userID { message = "Saved in ATHLTH. Apple Health copy failed: \(error.localizedDescription). You can retry below." }
        }
    }

    func checkpoint() {
        guard var workout = active else { return }
        workout.lastCheckpoint = Date()
        active = workout
        persistActiveCheckpoint(force: true)
    }

    private func persistActiveCheckpoint(
        force: Bool = false
    ) {
        guard let accountID,
              !UserDefaults.standard.bool(
                forKey: AccountLocalStorage.key(
                    "deleted",
                    userID: accountID
                )
              )
        else {
            return
        }

        let now = Date()

        if !force,
           let lastActiveCheckpointWriteAt,
           now.timeIntervalSince(lastActiveCheckpointWriteAt) <
                activeCheckpointInterval {
            return
        }

        if let active {
            AccountLocalStorage.write(
                active,
                name: "phoneActive",
                userID: accountID
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: AccountLocalStorage.key(
                    "phoneActive",
                    userID: accountID
                )
            )
        }

        lastActiveCheckpointWriteAt = now
    }

    private func persistHistory() {
        guard let accountID,
              !UserDefaults.standard.bool(
                forKey: AccountLocalStorage.key(
                    "deleted",
                    userID: accountID
                )
              )
        else {
            return
        }

        AccountLocalStorage.write(
            history,
            name: "phoneHistory",
            userID: accountID
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.manager.authorizationStatus == .denied || self.manager.authorizationStatus == .restricted { self.pause() }
            self.beginIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.accept(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.message = "GPS is unavailable. Time continues; distance will resume when the signal returns."; self.lastLocation = nil }
    }

    private func accept(_ locations: [CLLocation]) {
        guard var workout = active, let resumedAt = workout.resumedAt else { return }
        for location in locations {
            guard location.timestamp >= resumedAt, abs(location.timestamp.timeIntervalSinceNow) < 15,
                  location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30 else { continue }
            if let previous = lastLocation {
                let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
                guard seconds > 0 else { continue }
                let distance = location.distance(from: previous)
                // Ignore long signal gaps and implausible jumps rather than inventing distance.
                if seconds <= 30, distance / seconds <= 12 { workout.distanceMeters += distance }
            }
            lastLocation = location
            workout.points.append(PhoneRoutePoint(location))
            workout.lastCheckpoint = Date()
            message = nil
        }
        active = workout
        persistActiveCheckpoint()
    }
}
