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
        var firstSeenKeys: [String] = []
        var knownKeys: Set<String> = []
        var linkedHealthIDsByKey: [String: Set<UUID>] = [:]

        // Merge repeated snapshots of the same local workout before deciding
        // whether it was already imported from HealthKit. An earlier snapshot
        // may have had no HealthKit UUID while a later one is linked.
        for record in localRecords {
            if knownKeys.insert(record.key).inserted {
                firstSeenKeys.append(record.key)
            }
            if let linked = record.healthID {
                linkedHealthIDsByKey[record.key, default: []].insert(linked)
            }
        }

        var seenHealthIDs = healthIDs
        var selected: Set<String> = []
        for key in firstSeenKeys {
            let linkedIDs = linkedHealthIDsByKey[key] ?? []
            // Conflicting delayed snapshots with the same local key and
            // different HealthKit identities are ambiguous. Neither record
            // may become a reliable workout count until reconciled.
            guard linkedIDs.count <= 1,
                  linkedIDs.isDisjoint(with: seenHealthIDs) else { continue }
            selected.insert(key)
            // A reused HealthKit identity can contribute only once, even
            // when the local history was imported through two record kinds.
            seenHealthIDs.formUnion(linkedIDs)
        }
        return selected
    }
}
