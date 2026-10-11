import Foundation

/// Local-only provenance checks for explicit Arena sharing. A HealthKit or
/// ATHLTH history match means the record was found on *this device*; it is
/// not a server signature and must never authorize automatic points.
enum ATHLTHArenaLocalSourceCheck: Equatable {
    case healthRecord
    case athlthRecording
    case missingRecord
    case conflictingRecord

    var isUsable: Bool {
        self == .healthRecord || self == .athlthRecording
    }

    var description: String {
        switch self {
        case .healthRecord:
            return ATHLTHLocalization.choose(
                english: "Matched in Apple Health on this device",
                norwegian: "Funnet i Apple Health på denne enheten"
            )
        case .athlthRecording:
            return ATHLTHLocalization.choose(
                english: "Matched in ATHLTH workout history",
                norwegian: "Funnet i ATHLTHs økthistorikk"
            )
        case .missingRecord:
            return ATHLTHLocalization.choose(
                english: "Original workout not found. Refresh workout history.",
                norwegian: "Originaløkten er ikke funnet. Oppdater treningshistorikken."
            )
        case .conflictingRecord:
            return ATHLTHLocalization.choose(
                english: "The original workout differs from this result.",
                norwegian: "Originaløkten stemmer ikke med resultatet."
            )
        }
    }
}

enum ATHLTHArenaLocalEvidenceCheck {
    static func verify(
        _ workout: SocialPublishableWorkout,
        health: [WorkoutSummary],
        phone: [PhoneWorkout],
        strength: [StrengthWorkoutLog]
    ) -> ATHLTHArenaLocalSourceCheck {
        // If an actual HealthKit workout with that UUID is accessible, it must
        // agree with the displayed activity and measurements. A conflicting
        // record blocks the share even if a phone log happens to match.
        if let recorded = health.first(where: { $0.id == workout.id }) {
            return agrees(
                workout,
                activity: recorded.activity,
                start: recorded.startDate,
                end: recorded.endDate,
                duration: recorded.duration,
                distance: recorded.distanceMeters
            ) ? .healthRecord : .conflictingRecord
        }

        if workout.source == "Apple Health" {
            return .missingRecord
        }

        if workout.source == "iPhone" {
            guard let recorded = phone.first(where: {
                ($0.healthID ?? $0.id) == workout.id && $0.end != nil
            }), let end = recorded.end else {
                return .missingRecord
            }
            return agrees(
                workout,
                activity: recorded.walking ? .walking : .running,
                start: recorded.start,
                end: end,
                duration: recorded.accumulatedSeconds > 0
                    ? recorded.accumulatedSeconds
                    : end.timeIntervalSince(recorded.start),
                distance: recorded.distanceMeters > 0 ? recorded.distanceMeters : nil
            ) ? .athlthRecording : .conflictingRecord
        }

        if workout.source == "ATHLTH" {
            guard let recorded = strength.first(where: {
                ($0.healthMetrics.healthKitWorkoutUUID ?? $0.id) == workout.id &&
                $0.isFinished
            }), let end = recorded.endedAt else {
                return .missingRecord
            }
            return agrees(
                workout,
                activity: .strength,
                start: recorded.startedAt,
                end: end,
                duration: max(
                    end.timeIntervalSince(recorded.startedAt),
                    recorded.healthMetrics.duration ?? 0
                ),
                distance: nil
            ) ? .athlthRecording : .conflictingRecord
        }

        return .missingRecord
    }

    private static func agrees(
        _ workout: SocialPublishableWorkout,
        activity: WorkoutActivity,
        start: Date,
        end: Date,
        duration: TimeInterval,
        distance: Double?
    ) -> Bool {
        guard workout.activity == activity,
              workout.startDate.timeIntervalSince(start).magnitude <= 120,
              workout.endDate.timeIntervalSince(end).magnitude <= 120,
              workout.duration.isFinite,
              duration.isFinite, duration > 0,
              abs(workout.duration - duration) <= max(120, duration * 0.12)
        else { return false }
        switch (workout.distanceMeters, distance) {
        case (nil, nil): return true
        case (let a?, let b?):
            guard a.isFinite, b.isFinite, a >= 0, b >= 0 else { return false }
            return abs(a - b) <= max(100, b * 0.02)
        default:
            return false
        }
    }
}
