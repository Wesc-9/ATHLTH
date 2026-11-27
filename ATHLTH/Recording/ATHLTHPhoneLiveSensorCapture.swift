import Foundation
@preconcurrency import HealthKit

/// Pure freshness check: no cached/resting measurement can masquerade as live.
enum ATHLTHPhonePulseFreshness {
    static func value(_ bpm: Double, sampledAt: Date, startedAt: Date, now: Date) -> Double? {
        guard bpm.isFinite, bpm > 0, sampledAt >= startedAt,
              now.timeIntervalSince(sampledAt) >= -2,
              now.timeIntervalSince(sampledAt) <= 15 else { return nil }
        return bpm
    }
}

/// Optional native capture for the existing phone recorder. Owns a single
/// session and its associated builder, never a separate saved workout.
@available(iOS 26.0, *)
@MainActor
final class ATHLTHPhoneLiveSensorCapture: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    let workoutID: UUID
    private let startedAt: Date
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var began = false
    private var paused = false
    private var exporting = false
    private var exported = false
    private var stopRequested = false
    private var reading: (bpm: Double, date: Date)?
    private var freshAfter: Date

    init(workoutID: UUID, startedAt: Date) {
        self.workoutID = workoutID
        self.startedAt = startedAt
        self.freshAfter = startedAt
        super.init()
    }

    func start(store: HKHealthStore, configuration: HKWorkoutConfiguration) {
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            // ATHLTH owns GPS/manual treadmill distance and pause events.
            // Disable system distance and all other automatic data except pulse
            // and energy, to avoid conflicting or duplicated samples.
            let allowed = Set([HKQuantityTypeIdentifier.heartRate.rawValue,
                               HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                               HKQuantityTypeIdentifier.basalEnergyBurned.rawValue])
            for type in source.typesToCollect where !allowed.contains(type.identifier) {
                source.disableCollection(for: type)
            }
            if let pulse = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                source.enableCollection(for: pulse, predicate: nil)
            }
            builder.dataSource = source
            builder.shouldCollectWorkoutEvents = false
            self.session = session
            self.builder = builder
            session.delegate = self
            builder.delegate = self
            session.startActivity(with: startedAt)
            let identity = ObjectIdentifier(builder)
            builder.beginCollection(withStart: startedAt) { [weak self] success, _ in
                Task { @MainActor [weak self] in
                    guard let self, let builder = self.builder,
                          ObjectIdentifier(builder) == identity else { return }
                    if success { self.began = true }
                    else { self.discard() }
                }
            }
        } catch {
            discard()
        }
    }

    func freshHeartRate(at now: Date) -> Double? {
        guard began, !paused, !exporting, !stopRequested, let reading else { return nil }
        return ATHLTHPhonePulseFreshness.value(reading.bpm, sampledAt: reading.date,
            startedAt: freshAfter, now: now)
    }

    func setPaused(_ value: Bool) {
        guard !exporting, paused != value else { return }
        paused = value
        reading = nil
        freshAfter = Date()
        if value { session?.pause() } else { session?.resume() }
    }

    func summary() -> (activeCalories: Double?, averageHeartRate: Double?, maxHeartRate: Double?) {
        guard began, let builder else { return (nil, nil, nil) }
        let pulse = HKQuantityType.quantityType(forIdentifier: .heartRate)
            .flatMap { builder.statistics(for: $0) }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
            .flatMap { builder.statistics(for: $0) }?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let average = pulse?.averageQuantity()?.doubleValue(for: bpm)
        let maximum = pulse?.maximumQuantity()?.doubleValue(for: bpm)
        return (Self.valid(energy), Self.valid(average), Self.valid(maximum))
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Stop collection immediately when the local journal commits; the
    /// canonical exporter can finish the same builder asynchronously.
    func requestStop(at end: Date) {
        guard !stopRequested else { return }
        stopRequested = true
        reading = nil
        session?.stopActivity(with: end)
    }

    /// Wait briefly for HealthKit's stopped state before letting the existing
    /// exporter attach metadata, pause events and distance to this builder.
    func stopForExport(at end: Date) async -> HKLiveWorkoutBuilder? {
        guard began, let session, let builder, !exporting else {
            discard()
            return nil
        }
        exporting = true
        reading = nil
        requestStop(at: end)
        for _ in 0..<30 {
            guard self.session === session, self.builder === builder else { return nil }
            if session.state == .stopped { return builder }
            if session.state == .ended { break }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { break }
        }
        discard()
        return nil
    }

    func markExported() {
        exported = true
        discard()
    }

    func discard() {
        let oldSession = session
        let oldBuilder = builder
        session = nil
        builder = nil
        reading = nil
        began = false
        oldSession?.delegate = nil
        oldBuilder?.delegate = nil
        if oldSession?.state != .ended { oldSession?.end() }
        if !exported { oldBuilder?.discardWorkout() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        let identity = ObjectIdentifier(workoutSession)
        let rawState = toState.rawValue
        Task { @MainActor [weak self] in
            guard let self, let session = self.session, ObjectIdentifier(session) == identity else { return }
            if rawState == HKWorkoutSessionState.ended.rawValue && !self.exporting {
                self.discard()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let identity = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            guard let self, let session = self.session, ObjectIdentifier(session) == identity,
                  !self.exporting else { return }
            self.discard()
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(where: { $0.identifier == HKQuantityTypeIdentifier.heartRate.rawValue }) else { return }
        let identity = ObjectIdentifier(workoutBuilder)
        Task { @MainActor [weak self] in
            guard let self, !self.paused, !self.exporting, !self.stopRequested, let builder = self.builder,
                  ObjectIdentifier(builder) == identity,
                  let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
                  let stats = builder.statistics(for: type),
                  let quantity = stats.mostRecentQuantity(),
                  let date = stats.mostRecentQuantityDateInterval()?.end,
                  self.reading.map({ date > $0.date }) ?? true else { return }
            let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            guard ATHLTHPhonePulseFreshness.value(bpm, sampledAt: date,
                startedAt: self.freshAfter, now: Date()) != nil else { return }
            self.reading = (bpm, date)
        }
    }
}
