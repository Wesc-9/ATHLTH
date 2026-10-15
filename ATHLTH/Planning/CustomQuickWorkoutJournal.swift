import Foundation

/// A phone-timed or retrospective workout entered by the athlete.
/// Never substitute these values for HealthKit GPS, heart rate, or Watch data.
enum CustomQuickWorkoutEvidence: String, Codable, Hashable {
    case phoneTimer
    case manual

    var label: String {
        switch self {
        case .phoneTimer:
            return ATHLTHLocalization.choose(
                english: "iPhone-timed · manual entry",
                norwegian: "Tid målt på iPhone · øvrige data manuelt"
            )
        case .manual:
            return ATHLTHLocalization.choose(
                english: "Manually logged · unverified",
                norwegian: "Manuelt registrert · ikke kvalitetssikret"
            )
        }
    }
}

struct CustomQuickWorkoutRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let activity: CustomQuickWorkoutActivity
    let method: CustomQuickWorkoutMethod
    let recordedAt: Date
    let durationSeconds: TimeInterval
    /// Entered by the user: never GPS-derived.
    let manualDistanceKilometers: Double?
    let perceivedEffort: Int?
    let notes: String?
    let evidence: CustomQuickWorkoutEvidence

    var title: String {
        method == .open
            ? activity.localizedTitle
            : "\(activity.localizedTitle) · \(method.localizedTitle)"
    }

    var manuallyEnteredMetricsAreUnverified: Bool { true }

    /// Plausibility ceiling with 10% headroom, not verification.
    static func maximumRunningSpeedKilometersPerHour(for seconds: TimeInterval) -> Double {
        let minutes = seconds / 60
        let benchmark: Double
        switch minutes {
        case ..<1: benchmark = 44.72
        case ..<3: benchmark = 30
        case ..<10: benchmark = 26
        case ..<30: benchmark = 23
        case ..<90: benchmark = 21.1
        default: benchmark = 19
        }
        return benchmark * 1.10
    }

    static func validDistance(_ value: Double?, durationSeconds: TimeInterval,
                              activity: CustomQuickWorkoutActivity) -> Bool {
        guard let value else { return true }
        guard value.isFinite && value > 0 && value <= 1_000 else { return false }
        if activity == .cycling || activity == .rowing { return true }
        return value <= maximumRunningSpeedKilometersPerHour(for: durationSeconds)
            * durationSeconds / 3600
    }

    static func validDistance(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value > 0 && value <= 1_000
    }

    static func validDuration(_ seconds: TimeInterval) -> Bool {
        seconds.isFinite && seconds >= 1 && seconds <= 24 * 60 * 60
    }

    static func make(
        configuration: CustomQuickWorkoutConfiguration,
        recordedAt: Date,
        durationSeconds: TimeInterval,
        distanceKilometers: Double?,
        perceivedEffort: Int?,
        notes: String?,
        evidence: CustomQuickWorkoutEvidence
    ) -> CustomQuickWorkoutRecord? {
        guard validDuration(durationSeconds),
              validDistance(distanceKilometers, durationSeconds: durationSeconds, activity: configuration.activity),
              perceivedEffort.map({ (1...10).contains($0) }) ?? true
        else { return nil }
        return CustomQuickWorkoutRecord(
            id: UUID(),
            activity: configuration.activity,
            method: configuration.method,
            recordedAt: recordedAt,
            durationSeconds: durationSeconds,
            manualDistanceKilometers: distanceKilometers,
            perceivedEffort: perceivedEffort,
            notes: notes,
            evidence: evidence
        )
    }
}

enum CustomQuickWorkoutJournal {
    private static let key = "customQuickManualWorkoutHistory"

    static func load(userID: UUID) -> [CustomQuickWorkoutRecord] {
        AccountLocalStorage.read(
            [CustomQuickWorkoutRecord].self, name: key, userID: userID
        ) ?? []
    }

    static func save(_ record: CustomQuickWorkoutRecord, userID: UUID) {
        var entries = load(userID: userID)
        guard !entries.contains(where: { $0.id == record.id }) else { return }
        entries.insert(record, at: 0)
        entries.sort { $0.recordedAt > $1.recordedAt }
        AccountLocalStorage.write(
            Array(entries.prefix(300)), name: key, userID: userID
        )
        ATHLTHTrainingDataChangeSignal.post(userID: userID)
    }
}
