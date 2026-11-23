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
        next.targetVMAPercent = block.targetVMAPercent
        next.targetIntensityType = block.targetIntensityType
        next.targetElevationGainMeters = block.targetElevationGainMeters
        next.targetGradientPercent = block.targetGradientPercent
        next.targetTerrainType = block.targetTerrainType
        next.targetRepetitionsMaximum = block.targetRepetitionsMaximum
        next.targetRepsInReserve = block.targetRepsInReserve
        next.targetMovementTempo = block.targetMovementTempo
        next.sourceSupersetGroupIndex = block.sourceSupersetGroupIndex
        next.sourceLoadAlternativesKilograms = block.sourceLoadAlternativesKilograms
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
        next.assessmentMethod = ATHLTHAssessmentMethod.normalized(
            block.assessmentMethod, for: next
        )
        next.assessmentScope = next.assessmentMethod == nil
            ? nil : block.assessmentScope
        next.measurementStepID = block.measurementStepID
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
            copy.assessmentMethod = ATHLTHAssessmentMethod.normalized(
                copy.assessmentMethod, for: copy
            )
            if copy.assessmentMethod == nil { copy.assessmentScope = nil }
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
    /// Context-free behavior remains valid for a standalone recovery in the
    /// guided-day planner. The full Studio uses the context-aware overload so
    /// interval recoveries follow their efforts, including active recoveries.
    static func presentedPhase(
        for block: WorkoutTemplateBlock,
        visiblePhases: Set<WorkoutPhaseKind>
    ) -> WorkoutPhaseKind {
        if block.isActiveRecovery { return .recovery }
        return block.resolvedPhase == .recovery && !visiblePhases.contains(.recovery)
            ? .main : block.resolvedPhase
    }

    /// Presentation only. A 4×4 is still [work, active recovery, work, ...]
    /// in its original recording recipe. Never change stored phases or sort
    /// independently by work/rest type. An independent active pause (for
    /// example a guided day starting with recovery) remains a Pause section.
    static func presentedPhase(
        at index: Int,
        in blocks: [WorkoutTemplateBlock],
        visiblePhases: Set<WorkoutPhaseKind>
    ) -> WorkoutPhaseKind {
        guard blocks.indices.contains(index) else { return .main }
        let block = blocks[index]
        guard block.isRestOrActiveRecovery else {
            return presentedPhase(for: block, visiblePhases: visiblePhases)
        }

        if index > 0 {
            let previous = blocks[index - 1]
            // Explicit intervals have an immutable shared ID even when
            // active recovery keeps phase=.recovery and an easy 6 km/h pace.
            if let id = block.groupID, block.groupKind == .intervals,
               previous.groupID == id, previous.groupKind == .intervals,
               previous.kind == .run && !previous.isActiveRecovery {
                return previous.resolvedPhase
            }

            // Older ungrouped recipes may still interleave run/recovery/run.
            // The next effort is necessary: do not swallow a standalone
            // active recovery placed after a completed workout.
            if block.groupID == nil, previous.groupID == nil,
               previous.kind == .run, !previous.isRestOrActiveRecovery,
               index + 1 < blocks.count {
                let next = blocks[index + 1]
                if next.kind == .run, !next.isRestOrActiveRecovery,
                   next.groupID == nil,
                   previous.resolvedPhase == next.resolvedPhase,
                   previous.cardioActivity == next.cardioActivity {
                    return previous.resolvedPhase
                }
            }
        }
        return presentedPhase(for: block, visiblePhases: visiblePhases)
    }

    /// Any explicit section is listed once, but a transient recovery phase
    /// in a bundled interval must not produce an empty Pause card.
    static func orderedVisiblePhases(
        for blocks: [WorkoutTemplateBlock],
        visiblePhases: Set<WorkoutPhaseKind>
    ) -> [WorkoutPhaseKind] {
        let classified = blocks.indices.map {
            presentedPhase(at: $0, in: blocks, visiblePhases: visiblePhases)
        }
        var phases = WorkoutPhaseKind.allCases.filter { phase in
            if classified.contains(phase) { return true }
            if phase == .recovery &&
               blocks.contains(where: { $0.isRestOrActiveRecovery }) {
                return false
            }
            return visiblePhases.contains(phase)
        }
        if let recoveryIndex = classified.firstIndex(of: .recovery),
           let mainIndex = classified.firstIndex(of: .main),
           recoveryIndex < mainIndex,
           let existingRecovery = phases.firstIndex(of: .recovery) {
            phases.remove(at: existingRecovery)
            if let firstMain = phases.firstIndex(of: .main) {
                phases.insert(.recovery, at: firstMain)
            }
        }
        return phases
    }

    static func removing(
        _ phase: WorkoutPhaseKind,
        from blocks: [WorkoutTemplateBlock],
        visiblePhases: Set<WorkoutPhaseKind>
    ) -> [WorkoutTemplateBlock] {
        var remaining = blocks.enumerated().compactMap { index, block in
            presentedPhase(
                at: index, in: blocks, visiblePhases: visiblePhases
            ) == phase ? nil : block
        }

        // Deleting Main deletes its interval recoveries as well; it cannot
        // strand a detached Pause group or a broken explicit interval.
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
        for (index, block) in blocks.enumerated() {
            // Active recoveries inside an explicit interval share their
            // effort's visible section, even though they are actual moving
            // running steps rather than passive .rest blocks.
            let phase: WorkoutPhaseKind
            if block.kind == .rest {
                phase = sections.last?.phase ?? block.resolvedPhase
            } else if block.isActiveRecovery {
                phase = ATHLTHWorkoutPhaseDeletionPolicy.presentedPhase(
                    at: index, in: blocks, visiblePhases: []
                )
            } else {
                phase = block.resolvedPhase
            }

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
