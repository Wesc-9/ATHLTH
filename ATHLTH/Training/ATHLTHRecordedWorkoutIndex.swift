import Foundation

/// Explicit identity links only: similar timestamps are not proof that two
/// workouts are the same. HealthKit takes priority once its record is available.
enum ATHLTHRecordedWorkoutIndex {
    struct LocalRecord {
        let key: String
        let healthID: UUID?
    }

    static func unlinkedKeys(
        healthIDs: Set<UUID>, localRecords: [LocalRecord]
    ) -> Set<String> {
        var seenHealthIDs = healthIDs
        var seenLocalKeys: Set<String> = []
        var selected: Set<String> = []
        for record in localRecords {
            guard seenLocalKeys.insert(record.key).inserted else { continue }
            if let healthID = record.healthID,
               !seenHealthIDs.insert(healthID).inserted { continue }
            selected.insert(record.key)
        }
        return selected
    }
}
