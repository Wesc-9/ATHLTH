import Foundation
@preconcurrency import CoreMotion

/// Sensor input validation for LIVE coach alerts; display and HealthKit
/// recording keep their existing independent behavior.
enum ATHLTHCoachSensorFreshness {
    static let maximumHeartRateAge: TimeInterval = 12
    static let maximumPaceAge: TimeInterval = 8
    static let maximumCadenceAge: TimeInterval = 12
    static let maximumSnapshotAge: TimeInterval = 5

    static func isFresh(
        sampledAt: Date?,
        maximumAge: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard let sampledAt,
              maximumAge >= 0
        else { return false }
        let age = now.timeIntervalSince(sampledAt)
        return age >= -2 && age <= maximumAge
    }

    static func validHeartRate(
        _ value: Double,
        sampledAt: Date?,
        now: Date = Date()
    ) -> Bool {
        value.isFinite &&
        (30...240).contains(value) &&
        isFresh(
            sampledAt: sampledAt,
            maximumAge: maximumHeartRateAge,
            now: now
        )
    }

    static func validCadence(_ value: Double, sampledAt: Date?, now: Date = Date()) -> Bool {
        value.isFinite && (30...260).contains(value) &&
            isFresh(sampledAt: sampledAt, maximumAge: maximumCadenceAge, now: now)
    }

    static func validPace(
        _ secondsPerKilometer: TimeInterval?,
        sampledAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let pace = secondsPerKilometer else {
            return false
        }
        return pace.isFinite &&
            (120...1_800).contains(pace) &&
            isFresh(
                sampledAt: sampledAt,
                maximumAge: maximumPaceAge,
                now: now
            )
    }
}

#if os(iOS) || os(watchOS)
/// Motion is requested only for an active running/walking cadence rule.
/// No raw motion samples, location or separate workout recording.
@MainActor
final class ATHLTHCoachCadenceSensor {
    private var pedometer: CMPedometer?
    private var requested = false
    private var generation = UUID()
    private var value: Double?
    private var sampledAt: Date?

    func setEnabled(_ enabled: Bool) {
        guard enabled else { stop(); return }
        guard !requested else { return }
        requested = true
        guard CMPedometer.isCadenceAvailable(),
              CMPedometer.authorizationStatus() != .denied,
              CMPedometer.authorizationStatus() != .restricted else { return }
        let sensor = CMPedometer()
        pedometer = sensor
        let token = UUID()
        generation = token
        sensor.startUpdates(from: Date()) { [weak self] data, error in
            let cadence = (data?.currentCadence?.doubleValue).map { $0 * 60 }
            let date = data?.endDate
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                guard !failed, let cadence,
                      ATHLTHCoachSensorFreshness.validCadence(cadence, sampledAt: date) else {
                    self.value = nil
                    self.sampledAt = nil
                    return
                }
                self.value = cadence
                self.sampledAt = date
            }
        }
    }

    func stop() {
        guard requested else { return }
        requested = false
        generation = UUID()
        pedometer?.stopUpdates()
        pedometer = nil
        value = nil
        sampledAt = nil
    }

    func apply(to context: inout ATHLTHCoachReadoutContext) {
        guard let value, ATHLTHCoachSensorFreshness.validCadence(value, sampledAt: sampledAt) else { return }
        context.measuredCadenceStepsPerMinute = value
        context.cadenceSampleAt = sampledAt
    }
}
#endif
