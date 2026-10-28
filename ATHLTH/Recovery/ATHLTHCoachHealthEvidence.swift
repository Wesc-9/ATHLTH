import Foundation

/// Explicit sample timestamps. A calculated readiness value is not a new
/// HealthKit measurement. Never give the AI a stronger freshness claim than
/// its underlying sources support.
struct ATHLTHCoachHealthEvidence: Codable, Hashable {
    let capturedAt: String
    let sleepEndedAt: String?
    let hrvSampledAt: String?
    let restingPulseSampledAt: String?

    static func valid(_ measurementAt: Date?, now: Date = Date(),
                      maxAgeHours: TimeInterval) -> Bool {
        guard let measurementAt else { return false }
        let seconds = now.timeIntervalSince(measurementAt)
        return seconds >= -300 && seconds <= maxAgeHours * 3600
    }

    static func iso(_ date: Date?) -> String? {
        date.map { ISO8601DateFormatter().string(from: $0) }
    }
}
