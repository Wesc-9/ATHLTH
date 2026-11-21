import Foundation

/// Account-scoped, device-local target overlays for published workout recipes.
/// These values never change catalogue templates, saved copies, or other users'
/// prescriptions. Saving only the differences also makes Reset non-destructive.
enum ATHLTHWorkoutUserTargetsStore {
    private struct TargetOverride: Codable {
        let index: Int
        let pace: Double?
        let weight: Double?
        let incline: Double?
        let heartRateZone: Int?
        let effortRPE: Int?
    }

    private struct Payload: Codable {
        let recipeSignature: String
        let overrides: [TargetOverride]
    }

    private static func key(userID: String, workoutID: UUID) -> String {
        "athlth.workout.userTargets.v1.\(userID).\(workoutID.uuidString)"
    }

    private static func recipeSignature(_ blocks: [WorkoutTemplateBlock]) -> String {
        blocks.map { block in
            [
                String(block.sequence), String(describing: block.kind),
                block.title, block.exerciseSlug ?? "",
                String(block.distanceMeters ?? -1),
                String(block.durationSeconds ?? -1),
                String(describing: block.resolvedPhase)
            ].joined(separator: "|")
        }.joined(separator: "\n")
    }

    static func load(
        userID: String, workoutID: UUID, original: [WorkoutTemplateBlock],
        defaults: UserDefaults = .standard
    ) -> [WorkoutTemplateBlock]? {
        guard let data = defaults.data(forKey: key(userID: userID, workoutID: workoutID)),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.recipeSignature == recipeSignature(original),
              !payload.overrides.isEmpty else { return nil }
        var blocks = original
        for target in payload.overrides where blocks.indices.contains(target.index) {
            if let pace = target.pace, pace.isFinite, (120...959).contains(pace) {
                blocks[target.index].targetPaceSecondsPerKilometer = pace
            }
            if let weight = target.weight, weight.isFinite, (0...2000).contains(weight) {
                blocks[target.index].targetWeightKilograms = weight
            }
            if let incline = target.incline, incline.isFinite, (-30...30).contains(incline) {
                blocks[target.index].treadmillInclinePercent = incline
            }
            if let zone = target.heartRateZone, (1...5).contains(zone) {
                blocks[target.index].targetHeartRateZone = zone
                blocks[target.index].sourceIntensityZoneLabel = nil
                blocks[target.index].targetHeartRatePercentMin = nil
                blocks[target.index].targetHeartRatePercentMax = nil
            }
            if let rpe = target.effortRPE, (1...10).contains(rpe) {
                blocks[target.index].targetEffortRPE = rpe
            }
        }
        return blocks
    }

    @discardableResult
    static func save(
        userID: String, workoutID: UUID, original: [WorkoutTemplateBlock],
        customized: [WorkoutTemplateBlock], defaults: UserDefaults = .standard
    ) -> Bool {
        guard original.count == customized.count, !userID.isEmpty else { return false }
        var overrides: [TargetOverride] = []
        for index in original.indices {
            let base = original[index]
            let edit = customized[index]
            // Never store a target on a different step or a changed prescription.
            guard base.sequence == edit.sequence, base.kind == edit.kind,
                  base.title == edit.title else { return false }
            let pace = edit.targetPaceSecondsPerKilometer != base.targetPaceSecondsPerKilometer
                ? edit.targetPaceSecondsPerKilometer : nil
            let weight = edit.targetWeightKilograms != base.targetWeightKilograms
                ? edit.targetWeightKilograms : nil
            let incline = edit.treadmillInclinePercent != base.treadmillInclinePercent
                ? edit.treadmillInclinePercent : nil
            let zoneChanged =
                edit.targetHeartRateZone != base.targetHeartRateZone ||
                edit.sourceIntensityZoneLabel != base.sourceIntensityZoneLabel ||
                edit.targetHeartRatePercentMin != base.targetHeartRatePercentMin ||
                edit.targetHeartRatePercentMax != base.targetHeartRatePercentMax
            let zone = zoneChanged ? edit.targetHeartRateZone : nil
            let rpe = edit.targetEffortRPE != base.targetEffortRPE
                ? edit.targetEffortRPE : nil
            let target = TargetOverride(
                index: index,
                pace: pace,
                weight: weight,
                incline: incline,
                heartRateZone: zone,
                effortRPE: rpe
            )
            if pace != nil || weight != nil || incline != nil ||
                zone != nil || rpe != nil {
                overrides.append(target)
            }
        }
        if overrides.isEmpty {
            reset(userID: userID, workoutID: workoutID, defaults: defaults)
            return true
        }
        let payload = Payload(recipeSignature: recipeSignature(original), overrides: overrides)
        guard let encoded = try? JSONEncoder().encode(payload) else { return false }
        defaults.set(encoded, forKey: key(userID: userID, workoutID: workoutID))
        return true
    }

    static func reset(
        userID: String, workoutID: UUID, defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: key(userID: userID, workoutID: workoutID))
    }
}
