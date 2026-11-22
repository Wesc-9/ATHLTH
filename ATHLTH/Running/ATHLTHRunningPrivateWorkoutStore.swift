import Foundation

/// A private override for a named built-in running recipe, distinct from
/// the user's published library copies. Account-local, never sent to friends.
enum ATHLTHRunningPrivateWorkoutStore {
    private struct Record: Codable {
        var sourceSignature: String
        var customized: RunningWorkoutTemplate
    }

    private static func key(userID: UUID, sourceID: UUID) -> String {
        "athlth.running.privatePreset.v1.\(userID.uuidString).\(sourceID.uuidString)"
    }

    /// Ignore runtime-generated RunningWorkoutBlock UUIDs. Built-in templates
    /// can assign fresh block IDs after app relaunch with identical structure.
    private static func signature(_ source: RunningWorkoutTemplate) -> String {
        let pieces = source.blocks.map { block in
            [
                block.kind.rawValue,
                block.title,
                String(block.repetitions),
                String(block.work.durationSeconds ?? -1),
                String(block.work.distanceMeters ?? -1),
                String(block.recovery?.durationSeconds ?? -1),
                String(block.recovery?.distanceMeters ?? -1)
            ].joined(separator: "|")
        }
        return ([source.id.uuidString, source.title, source.type.rawValue] + pieces)
            .joined(separator: "\n")
    }

    static func load(
        userID: UUID, source: RunningWorkoutTemplate,
        defaults: UserDefaults = .standard
    ) -> RunningWorkoutTemplate? {
        guard source.isBuiltIn,
              let data = defaults.data(forKey: key(userID: userID, sourceID: source.id)),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.sourceSignature == signature(source),
              record.customized.sharedSourceWorkoutID == source.id
        else { return nil }
        return record.customized
    }

    @discardableResult
    static func save(
        userID: UUID, source: RunningWorkoutTemplate,
        customized: RunningWorkoutTemplate,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard source.isBuiltIn,
              !customized.blocks.isEmpty,
              customized.blocks.count <= 300
        else { return false }
        var privateCopy = customized
        privateCopy.title = source.title
        privateCopy.summary = source.summary
        privateCopy.isBuiltIn = false
        privateCopy.sharedSourceWorkoutID = source.id
        privateCopy.sharedSourceOwnerID = nil
        privateCopy.updatedAt = Date()

        let record = Record(
            sourceSignature: signature(source),
            customized: privateCopy
        )
        guard let data = try? JSONEncoder().encode(record) else { return false }
        defaults.set(data, forKey: key(userID: userID, sourceID: source.id))
        return true
    }

    static func reset(
        userID: UUID, sourceID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: key(userID: userID, sourceID: sourceID))
    }
}

/// One input sets all 4×4 work reps; warm-up, standing/active recoveries,
/// cooldowns and arbitrary strength steps never receive the pace by mistake.
enum ATHLTHRunningPrivateSpeedPolicy {
    static func applying(
        kilometersPerHour: Double,
        to source: RunningWorkoutTemplate
    ) -> RunningWorkoutTemplate {
        guard kilometersPerHour.isFinite, (2...30).contains(kilometersPerHour)
        else { return source }
        let pace = 3600 / kilometersPerHour
        var result = source
        for index in result.blocks.indices where result.blocks[index].kind == .work {
            result.blocks[index].work.intensity.kind = .pace
            result.blocks[index].work.intensity.paceMinSecondsPerKilometer = pace
            result.blocks[index].work.intensity.paceMaxSecondsPerKilometer = pace
            if var overrides = result.blocks[index].repetitionOverrides {
                for position in overrides.indices {
                    if var step = overrides[position].work {
                        step.intensity.kind = .pace
                        step.intensity.paceMinSecondsPerKilometer = pace
                        step.intensity.paceMaxSecondsPerKilometer = pace
                        overrides[position].work = step
                    }
                }
                result.blocks[index].repetitionOverrides = overrides
            }
        }
        return result
    }

    static func workCount(in workout: RunningWorkoutTemplate) -> Int {
        workout.blocks.filter { $0.kind == .work }
            .reduce(0) { $0 + max(1, $1.repetitions) }
    }
}
