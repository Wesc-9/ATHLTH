import Foundation

/// Positions new independent blocks in the requested training phase without
/// splitting an existing interval or superset group. Saved order remains the
/// execution order; this policy only governs initial insertion.
enum ATHLTHWorkoutPhasePlacement {
    static func insertionIndex(
        for phase: WorkoutPhaseKind,
        in blocks: [WorkoutTemplateBlock]
    ) -> Int {
        let candidate: Int
        switch phase {
        case .warmup:
            candidate = blocks.firstIndex { $0.resolvedPhase != .warmup }
                ?? blocks.count
        case .main, .recovery:
            candidate = blocks.firstIndex { $0.resolvedPhase == .cooldown }
                ?? blocks.count
        case .cooldown:
            candidate = blocks.count
        }

        guard candidate > 0, candidate < blocks.count,
              let previousGroup = blocks[candidate - 1].groupID,
              previousGroup == blocks[candidate].groupID
        else { return candidate }

        // A phase boundary inside an interval group would corrupt
        // interval rounds. Insert before that entire group instead.
        var position = candidate
        while position > 0, blocks[position - 1].groupID == previousGroup {
            position -= 1
        }
        return position
    }
    /// Rebuild only the immutable sequence field without discarding any
    /// exercise, intensity, cycling or interval-group metadata.
    static func renumbered(
        _ block: WorkoutTemplateBlock,
        sequence: Int
    ) -> WorkoutTemplateBlock {
        var next = WorkoutTemplateBlock(
            sequence: sequence, kind: block.kind,
            title: block.title, exerciseSlug: block.exerciseSlug,
            distanceMeters: block.distanceMeters,
            repetitions: block.repetitions,
            durationSeconds: block.durationSeconds,
            targetWeightKilograms: block.targetWeightKilograms,
            loadNote: block.loadNote, notes: block.notes,
            phase: block.phase,
            targetPaceSecondsPerKilometer: block.targetPaceSecondsPerKilometer,
            targetHeartRateZone: block.targetHeartRateZone
        )
        next.routeID = block.routeID
        next.sourceIntensityZoneLabel = block.sourceIntensityZoneLabel
        next.targetHeartRatePercentMin = block.targetHeartRatePercentMin
        next.targetHeartRatePercentMax = block.targetHeartRatePercentMax
        next.targetEffortRPE = block.targetEffortRPE
        next.treadmillInclinePercent = block.treadmillInclinePercent
        next.setCount = block.setCount
        next.restBetweenSetsSeconds = block.restBetweenSetsSeconds
        next.individualSetTargets = block.individualSetTargets
        next.groupID = block.groupID
        next.groupKind = block.groupKind
        next.groupRounds = block.groupRounds
        // Renumbering happens on *every* editor insert, delete and reorder.
        // Dropping these fields would silently reset timed strength programs.
        next.groupClockSeconds = block.groupClockSeconds
        next.executionGroupKind = block.executionGroupKind
        next.executionGroupID = block.executionGroupID
        next.executionRound = block.executionRound
        next.executionTotalRounds = block.executionTotalRounds
        next.executionGroupClockSeconds = block.executionGroupClockSeconds
        next.executionStationCount = block.executionStationCount
        next.cardioActivity = block.cardioActivity
        next.isIndoor = block.isIndoor
        next.exerciseSnapshot = block.exerciseSnapshot
        next.exerciseID = block.exerciseID
        next.wellnessKind = block.wellnessKind
        next.activityTag = block.activityTag
        next.editorDragID = block.editorDragID
        return next
    }

    /// Move a selected activity (or its entire interval/superset group) to
    /// another part of the workout. Phase and physical timeline order must
    /// change together so previews, execution and Watch get one recipe.
    static func relocatingSelection(
        at selectedIndex: Int,
        to phase: WorkoutPhaseKind,
        in blocks: [WorkoutTemplateBlock]
    ) -> [WorkoutTemplateBlock] {
        guard blocks.indices.contains(selectedIndex) else { return blocks }
        let selected = blocks[selectedIndex]
        let affectedIndices = blocks.indices.filter { index in
            if let groupID = selected.groupID {
                return blocks[index].groupID == groupID
            }
            return index == selectedIndex
        }

        // Preserve the existing order when the requested phase already
        // matches every member. This avoids unexpected jumps on reselect.
        if affectedIndices.allSatisfy({ blocks[$0].resolvedPhase == phase }) {
            return blocks
        }

        let members = affectedIndices.map { index -> WorkoutTemplateBlock in
            var copy = blocks[index]
            copy.phase = phase
            return copy
        }
        let affected = Set(affectedIndices)
        var remaining = blocks.enumerated().compactMap { index, item in
            affected.contains(index) ? nil : item
        }

        // Insert as one indivisible section at the phase boundary, never
        // within the repetitions or recovery steps of an adjacent group.
        let destination = insertionIndex(for: phase, in: remaining)
        remaining.insert(contentsOf: members, at: destination)
        return remaining.enumerated().map { index, item in
            renumbered(item, sequence: index + 1)
        }
    }

}


/// Removes a whole visible workout category and all of its actual workout
/// steps. Presentation can show legacy recovery steps inside Hoveddel when
/// there is no separate Pause category; deleting Hoveddel must remove those
/// rows too, otherwise they would reappear after the next render or save.
enum ATHLTHWorkoutPhaseDeletionPolicy {
    static func presentedPhase(
        for block: WorkoutTemplateBlock,
        visiblePhases: Set<WorkoutPhaseKind>
    ) -> WorkoutPhaseKind {
        block.resolvedPhase == .recovery && !visiblePhases.contains(.recovery)
            ? .main : block.resolvedPhase
    }

    static func removing(
        _ phase: WorkoutPhaseKind,
        from blocks: [WorkoutTemplateBlock],
        visiblePhases: Set<WorkoutPhaseKind>
    ) -> [WorkoutTemplateBlock] {
        var remaining = blocks.filter {
            presentedPhase(for: $0, visiblePhases: visiblePhases) != phase
        }

        // If removing a category leaves a single member of a previous
        // superset / interval group, it is no longer a valid grouped set.
        let groupSizes = Dictionary(
            grouping: remaining.compactMap { item -> (UUID, UUID)? in
                guard let groupID = item.groupID else { return nil }
                return (groupID, item.editorDragID)
            },
            by: { $0.0 }
        ).mapValues(\.count)

        for i in remaining.indices {
            if let groupID = remaining[i].groupID,
               (groupSizes[groupID] ?? 0) < 2 {
                remaining[i].groupID = nil
                remaining[i].groupKind = nil
                remaining[i].groupRounds = nil
            }
        }

        return remaining.enumerated().map {
            ATHLTHWorkoutPhasePlacement.renumbered(
                $0.element, sequence: $0.offset + 1
            )
        }
    }
}


// MARK: - Chronological presentation of workout phases

/// UI-only grouping. The persisted block array already defines playback
/// order, including recovery between intervals; never reorder it by phase.
enum ATHLTHWorkoutTimelinePresentation {
    struct Section: Identifiable {
        let id: Int
        let phase: WorkoutPhaseKind
        var blocks: [WorkoutTemplateBlock]

        // An interval section with four efforts and three pauses reads (4),
        // while its pause rows remain visible between the efforts.
        var activityCount: Int {
            let work = blocks.filter { !$0.isRestOrActiveRecovery }.count
            return work > 0 ? work : blocks.count
        }
    }

    static func sections(for blocks: [WorkoutTemplateBlock]) -> [Section] {
        var sections: [Section] = []
        for block in blocks {
            let phase = block.kind == .rest
                ? (sections.last?.phase ?? block.resolvedPhase)
                : block.resolvedPhase

            if let last = sections.indices.last, sections[last].phase == phase {
                sections[last].blocks.append(block)
            } else {
                sections.append(Section(
                    id: sections.count, phase: phase, blocks: [block]
                ))
            }
        }
        return sections
    }
}
