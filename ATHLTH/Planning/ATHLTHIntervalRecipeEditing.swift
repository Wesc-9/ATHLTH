import Foundation

/// An explicit interval sequence is a set of independently editable work and
/// recovery steps, not a compact repeat instruction. A single round of grouped
/// metadata gives the editor a stable accordion without repeating or deleting
/// a final recovery during Watch execution.
enum ATHLTHIntervalRecipeEditing {
    struct Summary: Equatable {
        let groupID: UUID
        let displayName: String
        let rounds: Int
        let hasFinalRecovery: Bool
        let recoveryCount: Int
        let exactSeconds: TimeInterval?
    }

    static func summary(for groupID: UUID, in blocks: [WorkoutTemplateBlock]) -> Summary? {
        guard let range = contiguousRange(for: groupID, in: blocks) else {
            return nil
        }
        let items = Array(blocks[range])
        guard items.first?.groupKind == .intervals,
              items.first?.groupRounds == 1 else { return nil }
        let efforts = items.filter { $0.kind == .run && !$0.isActiveRecovery }
        guard efforts.count >= 1, efforts.count <= 20 else { return nil }
        // Respect individually edited targets without ever synthesizing rounds.
        let recovering = items.filter(\.isRestOrActiveRecovery)
        guard recovering.count == efforts.count ||
              recovering.count == efforts.count - 1 else { return nil }
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 2) {
                guard item.kind == .run && !item.isActiveRecovery else { return nil }
            } else {
                guard item.isRestOrActiveRecovery else { return nil }
            }
        }
        let total: TimeInterval? = items.allSatisfy({
            $0.durationSeconds != nil && $0.durationSeconds! >= 0
        }) ? items.reduce(0) { $0 + ($1.durationSeconds ?? 0) } : nil
        return Summary(
            groupID: groupID,
            displayName: suggestedName(for: items),
            rounds: efforts.count,
            hasFinalRecovery: items.last?.isRestOrActiveRecovery == true,
            recoveryCount: recovering.count, exactSeconds: total
        )
    }

    static func explicitGroupID(
        for step: WorkoutTemplateBlock, in blocks: [WorkoutTemplateBlock]
    ) -> UUID? {
        guard let id = step.groupID, summary(for: id, in: blocks) != nil else {
            return nil
        }
        return id
    }

    /// Changing the repeat count keeps every existing customized interval.
    /// Only newly added efforts/recoveries copy the first pair as a template.
    static func changing(
        _ source: [WorkoutTemplateBlock],
        groupID: UUID,
        rounds: Int,
        finalRecovery: Bool
    ) -> [WorkoutTemplateBlock]? {
        guard let range = contiguousRange(for: groupID, in: source),
              summary(for: groupID, in: source) != nil,
              (1...20).contains(rounds) else { return nil }
        let existing = Array(source[range])
        let efforts = existing.filter { $0.kind == .run && !$0.isActiveRecovery }
        let rests = existing.filter(\.isRestOrActiveRecovery)
        guard let firstEffort = efforts.first else { return nil }
        let firstRest = rests.first ?? passiveRecovery(
            groupID: groupID, phase: firstEffort.resolvedPhase
        )
        var replaced: [WorkoutTemplateBlock] = []
        for index in 0..<rounds {
            var effort = index < efforts.count ? efforts[index] : firstEffort
            if index >= efforts.count {
                effort.editorDragID = UUID()
            }
            if let automatic = automaticEffortBase(effort.title) {
                effort.title = "\(automatic) · \(index + 1)/\(rounds)"
            } else if index >= efforts.count {
                effort.title = numberedTitle(firstEffort.title, round: index + 1)
            }
            replaced.append(effort)
            if index < rounds - 1 || finalRecovery {
                var rest = index < rests.count ? rests[index] : firstRest
                if index >= rests.count {
                    rest.editorDragID = UUID()
                }
                if let automatic = automaticRecoveryBase(rest.title) {
                    rest.title = "\(automatic) · \(index + 1)/\(rounds)"
                } else if index >= rests.count {
                    rest.title = numberedTitle(firstRest.title, round: index + 1)
                }
                replaced.append(rest)
            }
        }
        guard source.count - existing.count + replaced.count <= 200 else {
            return nil
        }
        var updated = source
        updated.replaceSubrange(range, with: replaced)
        return renumbered(updated)
    }

    /// One explicit apply operation for the whole interval. Changing only the
    /// count or final recovery preserves every existing individual override.
    /// Supplying shared work or recovery targets intentionally updates that
    /// type of step, including previously customized steps, but never replaces
    /// sequence identities, custom titles or unrelated phases.
    static func adjusting(
        _ source: [WorkoutTemplateBlock],
        groupID: UUID,
        rounds: Int,
        finalRecovery: Bool,
        sharedWork: WorkoutTemplateBlock?,
        sharedRecovery: WorkoutTemplateBlock?
    ) -> [WorkoutTemplateBlock]? {
        guard sharedWork == nil ||
                (sharedWork?.kind == .run && sharedWork?.isActiveRecovery == false),
              sharedRecovery == nil || sharedRecovery?.isRestOrActiveRecovery == true,
              var updated = changing(
                source, groupID: groupID, rounds: rounds,
                finalRecovery: finalRecovery
              ) else { return nil }

        var recoveryOrdinal = 0
        for index in updated.indices where updated[index].groupID == groupID {
            if updated[index].kind == .run && !updated[index].isActiveRecovery {
                guard let sharedWork else { continue }
                updated[index].durationSeconds = sharedWork.durationSeconds
                updated[index].distanceMeters = sharedWork.distanceMeters
                updated[index].targetPaceSecondsPerKilometer =
                    sharedWork.targetPaceSecondsPerKilometer
                updated[index].targetHeartRateZone = sharedWork.targetHeartRateZone
                updated[index].targetHeartRatePercentMin = sharedWork.targetHeartRatePercentMin
                updated[index].targetHeartRatePercentMax = sharedWork.targetHeartRatePercentMax
                updated[index].sourceIntensityZoneLabel = sharedWork.sourceIntensityZoneLabel
                updated[index].targetEffortRPE = sharedWork.targetEffortRPE
                updated[index].treadmillInclinePercent = sharedWork.treadmillInclinePercent
                updated[index].isIndoor = sharedWork.isIndoor
                updated[index].cardioActivity = sharedWork.cardioActivity
                updated[index].notes = sharedWork.notes
            } else if updated[index].isRestOrActiveRecovery {
                recoveryOrdinal += 1
                guard let sharedRecovery else { continue }
                let active = sharedRecovery.isActiveRecovery
                if automaticRecoveryBase(updated[index].title) != nil {
                    let label = active
                        ? ATHLTHLocalization.choose(
                            english: "Active recovery", norwegian: "Aktiv pause"
                          )
                        : ATHLTHLocalization.choose(
                            english: "Recovery", norwegian: "Pause"
                          )
                    updated[index].title = "\(label) · \(recoveryOrdinal)/\(rounds)"
                }
                updated[index].kind = active ? .run : .rest
                updated[index].activityTag = active ? "active_recovery" : nil
                updated[index].cardioActivity =
                    active ? (sharedRecovery.cardioActivity ?? .running) : nil
                updated[index].durationSeconds = sharedRecovery.durationSeconds
                updated[index].distanceMeters =
                    active ? sharedRecovery.distanceMeters : nil
                updated[index].targetPaceSecondsPerKilometer =
                    active ? sharedRecovery.targetPaceSecondsPerKilometer : nil
                updated[index].targetHeartRateZone =
                    active ? sharedRecovery.targetHeartRateZone : nil
                updated[index].targetHeartRatePercentMin =
                    active ? sharedRecovery.targetHeartRatePercentMin : nil
                updated[index].targetHeartRatePercentMax =
                    active ? sharedRecovery.targetHeartRatePercentMax : nil
                updated[index].sourceIntensityZoneLabel =
                    active ? sharedRecovery.sourceIntensityZoneLabel : nil
                updated[index].targetEffortRPE =
                    active ? sharedRecovery.targetEffortRPE : nil
                updated[index].treadmillInclinePercent =
                    active ? sharedRecovery.treadmillInclinePercent : nil
                updated[index].isIndoor = active ? sharedRecovery.isIndoor : nil
                updated[index].notes = sharedRecovery.notes
            }
        }
        return updated
    }

    /// Explicit user choice, not a hidden intensity recommendation.
    /// A shared target never overwrites independently edited recovery jogs.
    static func copyingFirstEffortTargets(
        in source: [WorkoutTemplateBlock], groupID: UUID
    ) -> [WorkoutTemplateBlock]? {
        guard let range = contiguousRange(for: groupID, in: source),
              summary(for: groupID, in: source) != nil,
              let first = source[range].first(where: {
                  $0.kind == .run && !$0.isActiveRecovery
              }) else { return nil }
        var result = source
        // Active recovery is still part of the same indoor/treadmill
        // environment, but deliberately keeps its own easy pace.
        for index in range where result[index].isActiveRecovery {
            result[index].isIndoor = first.isIndoor
            result[index].treadmillInclinePercent = first.treadmillInclinePercent
        }
        for index in range where result[index].kind == .run &&
                              !result[index].isActiveRecovery {
            result[index].targetPaceSecondsPerKilometer =
                first.targetPaceSecondsPerKilometer
            result[index].targetHeartRateZone = first.targetHeartRateZone
            result[index].treadmillInclinePercent = first.treadmillInclinePercent
            result[index].isIndoor = first.isIndoor
            result[index].sourceIntensityZoneLabel = first.sourceIntensityZoneLabel
            result[index].targetHeartRatePercentMin = first.targetHeartRatePercentMin
            result[index].targetHeartRatePercentMax = first.targetHeartRatePercentMax
        }
        return result
    }

    static func ungrouping(
        _ source: [WorkoutTemplateBlock], groupID: UUID
    ) -> [WorkoutTemplateBlock] {
        var result = source
        for index in result.indices where result[index].groupID == groupID {
            result[index].groupID = nil
            result[index].groupKind = nil
            result[index].groupRounds = nil
        }
        return result
    }

    /// Older compact recipes need expansion; the new explicit single-round
    /// groups must retain their group IDs so they stay collapsible on reuse.
    static func forEditing(_ blocks: [WorkoutTemplateBlock]) -> [WorkoutTemplateBlock] {
        var result: [WorkoutTemplateBlock] = []
        var index = 0
        while index < blocks.count {
            let current = blocks[index]
            if let id = current.groupID, current.groupKind == .intervals {
                let begin = index
                while index < blocks.count && blocks[index].groupID == id {
                    index += 1
                }
                let members = Array(blocks[begin..<index])
                if current.groupRounds ?? 1 > 1 {
                    // Legacy repeat groups get one editable row per actual
                    // effort/recovery and a single-round UI grouping. Their
                    // historic missing final recovery stays missing.
                    var expanded = members.expandedForExecution()
                    for item in expanded.indices {
                        expanded[item].groupID = id
                        expanded[item].groupKind = .intervals
                        expanded[item].groupRounds = 1
                    }
                    result.append(contentsOf: expanded)
                } else {
                    result.append(contentsOf: members)
                }
            } else {
                result.append(current)
                index += 1
            }
        }
        return renumbered(result)
    }

    private static func suggestedName(
        for steps: [WorkoutTemplateBlock]
    ) -> String {
        guard let first = steps.first(where: {
            $0.kind == .run && !$0.isActiveRecovery
        }) else {
            return ATHLTHLocalization.choose(
                english: "Interval sequence", norwegian: "Intervallrekke"
            )
        }
        let easy = steps.first(where: \.isRestOrActiveRecovery)
        let seconds = Int((first.durationSeconds ?? -1).rounded())
        let recoverySeconds = Int((easy?.durationSeconds ?? -1).rounded())
        if seconds == 30 && recoverySeconds == 30 { return "30/30" }
        if seconds == 45 && recoverySeconds == 15 { return "45/15" }
        if seconds == 240 && recoverySeconds == 180 { return "4 × 4" }
        if let automatic = automaticEffortBase(first.title) {
            return automatic
        }
        let cleaned = first.title.replacingOccurrences(
            of: #"\s+\d+$"#, with: "", options: .regularExpression
        )
        if ["drag", "effort", "run interval", "løpeintervall"].contains(
            cleaned.lowercased()
        ) {
            return ATHLTHLocalization.choose(
                english: "Interval sequence", norwegian: "Intervallrekke"
            )
        }
        return cleaned
    }

    private static func contiguousRange(
        for id: UUID, in blocks: [WorkoutTemplateBlock]
    ) -> ClosedRange<Int>? {
        let indices = blocks.indices.filter { blocks[$0].groupID == id }
        guard let first = indices.first, let last = indices.last,
              indices.count == last - first + 1 else { return nil }
        return first...last
    }

    private static func passiveRecovery(
        groupID: UUID, phase: WorkoutPhaseKind
    ) -> WorkoutTemplateBlock {
        var rest = WorkoutTemplateBlock(
            sequence: 0, kind: .rest, title: ATHLTHLocalization.choose(
                english: "Recovery", norwegian: "Pause"
            ),
            exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
            durationSeconds: 60, targetWeightKilograms: nil,
            loadNote: nil, notes: nil, phase: phase
        )
        rest.groupID = groupID
        rest.groupKind = .intervals
        rest.groupRounds = 1
        return rest
    }

    // The legacy expansion stored titles such as "Løpeintervall · 1/4".
    // Increasing to 10 used to append " 5" to that stale denominator.
    // Only normalize known generated labels; respect custom step names.
    private static func automaticEffortBase(_ title: String) -> String? {
        let base = strippingGeneratedCounter(title)
        switch base.lowercased() {
        case "run interval", "running interval", "løpeintervall",
             "effort", "drag":
            return ATHLTHLocalization.choose(
                english: "Run interval", norwegian: "Løpeintervall"
            )
        case "walking interval", "gåintervall":
            return ATHLTHLocalization.choose(
                english: "Walking interval", norwegian: "Gåintervall"
            )
        default:
            return nil
        }
    }

    private static func automaticRecoveryBase(_ title: String) -> String? {
        let base = strippingGeneratedCounter(title)
        switch base.lowercased() {
        case "recovery", "rest", "pause":
            return ATHLTHLocalization.choose(
                english: "Recovery", norwegian: "Pause"
            )
        case "active recovery", "active recovery · easy jog",
             "aktiv pause", "aktiv pause · rolig jogg":
            return ATHLTHLocalization.choose(
                english: "Active recovery", norwegian: "Aktiv pause"
            )
        default:
            return nil
        }
    }

    private static func strippingGeneratedCounter(_ title: String) -> String {
        title.replacingOccurrences(
            of: #"\s*·\s*\d+/\d+(?:\s+\d+)?$"#,
            with: "", options: .regularExpression
        )
        .replacingOccurrences(
            of: #"\s+\d+$"#, with: "", options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numberedTitle(_ title: String, round: Int) -> String {
        let base = title.replacingOccurrences(
            of: #"\s+\d+$"#, with: "", options: .regularExpression
        )
        return base + " \(round)"
    }

    private static func renumbered(
        _ blocks: [WorkoutTemplateBlock]
    ) -> [WorkoutTemplateBlock] {
        blocks.enumerated().map {
            ATHLTHWorkoutPhasePlacement.renumbered(
                $0.element, sequence: $0.offset + 1
            )
        }
    }
}
