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
    /// Retains "Fri trening" when a generic .other session is completed.
    /// Optional for backward-compatible decoding of existing workout history.
    var titleOverride: String? = nil

    var title: String {
        if let titleOverride, !titleOverride.isEmpty { return titleOverride }
        return method == .open
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
        // Follow the same activity policy as the live/manual entry UI.
        // A hidden distance field can never create a fictional yoga,
        // HIIT or circuit distance through a stale draft or API caller.
        guard ATHLTHSpectatorSportMetricPolicy.supportsDistance(
            activity.rawValue
        ) else { return false }
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
        evidence: CustomQuickWorkoutEvidence,
        id: UUID = UUID()
    ) -> CustomQuickWorkoutRecord? {
        guard validDuration(durationSeconds),
              validDistance(distanceKilometers, durationSeconds: durationSeconds, activity: configuration.activity),
              perceivedEffort.map({ (1...10).contains($0) }) ?? true
        else { return nil }
        return CustomQuickWorkoutRecord(
            id: id,
            activity: configuration.activity,
            method: configuration.method,
            recordedAt: recordedAt,
            durationSeconds: durationSeconds,
            manualDistanceKilometers: distanceKilometers,
            perceivedEffort: perceivedEffort,
            notes: notes,
            evidence: evidence,
            titleOverride: configuration.titleOverride
        )
    }
}

enum CustomQuickWorkoutJournal {
    private static let key = "customQuickManualWorkoutHistory"

    static func load(
        userID: UUID, defaults: UserDefaults = .standard
    ) -> [CustomQuickWorkoutRecord] {
        AccountLocalStorage.read(
            [CustomQuickWorkoutRecord].self, name: key,
            userID: userID, defaults: defaults
        ) ?? []
    }

    /// Exactly one history receipt for a stable timer ID, including a retry
    /// after an interrupted finish. No notification on a failed write.
    /// UserDefaults readback is not a substitute for physical crash testing.
    @discardableResult
    static func save(
        _ record: CustomQuickWorkoutRecord,
        userID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        var entries = load(userID: userID, defaults: defaults)
        if entries.contains(where: { $0.id == record.id }) { return true }
        entries.insert(record, at: 0)
        entries.sort { $0.recordedAt > $1.recordedAt }
        do {
            try AccountLocalStorage.writeChecked(
                Array(entries.prefix(300)), name: key,
                userID: userID, defaults: defaults
            )
            guard load(userID: userID, defaults: defaults)
                .contains(where: { $0 == record }) else { return false }
            ATHLTHTrainingDataChangeSignal.post(userID: userID)
            return true
        } catch {
            return false
        }
    }
}
