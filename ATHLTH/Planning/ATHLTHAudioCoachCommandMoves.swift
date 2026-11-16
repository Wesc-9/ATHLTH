import Foundation

/// Moves individual spoken values between groups and the independent
/// command list without duplicating scheduled Watch / iPhone announcements.
/// Drag payloads contain local IDs only, never workout data.
enum ATHLTHAudioCoachCommandMoves {
    static func move(
        _ payload: String,
        to destination: UUID?,
        draft: inout AudioCoachDraft
    ) -> Bool {
        // A command always belongs to a trigger-bearing group. Dropping it
        // outside a group is not a valid destination.
        guard let destination,
              draft.coachGroups.contains(where: { $0.id == destination })
        else { return false }

        let parts = payload.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2, parts[0] == "option",
           let option = ATHLTHAudioCoachOption(rawValue: String(parts[1])),
           option.isActive(in: draft) {
            let old = draft.coachGroups.first(where: {
                $0.optionIDs.contains(option.rawValue)
            })?.id
            guard old != destination else { return false }
            for index in draft.coachGroups.indices {
                draft.coachGroups[index].optionIDs.removeAll {
                    $0 == option.rawValue
                }
            }
            if let index = draft.coachGroups.firstIndex(where: {
                $0.id == destination
            }) {
                draft.coachGroups[index].optionIDs.append(option.rawValue)
            }
            return true
        }

        guard parts.count == 3, parts[0] == "metric",
              let id = UUID(uuidString: String(parts[1])),
              let metric = ATHLTHAudioCoachRule.Metric(rawValue: String(parts[2])),
              let sourceIndex = draft.customRules.firstIndex(where: {
                  $0.id == id && $0.selectedMetrics.contains(metric)
              })
        else { return false }

        let source = draft.customRules[sourceIndex]
        let origin = draft.coachGroups.first(where: {
            $0.ruleIDs.contains(id)
        })?.id
        guard destination != origin else { return false }

        // A moved metric inherits the target group's schedule.
        let targetIndex = destination.flatMap { destination in
            draft.coachGroups.firstIndex { $0.id == destination }
        }
        let destinationRuleID = targetIndex.flatMap { index in
            draft.coachGroups[index].ruleIDs.first(where: { ruleID in
                ruleID != id && draft.customRules.contains(where: {
                    $0.id == ruleID && $0.beforeEndSeconds == nil &&
                        $0.customPhrase == nil
                })
            })
        }
        let createsRule = destinationRuleID == nil
        if createsRule && draft.customRules.count >= 20 &&
           source.selectedMetrics.count > 1 {
            return false
        }

        // Prepare all changes before mutating the source. An empty group
        // remains valid and can receive new commands later.
        let destinationConfig = targetIndex.map { draft.coachGroups[$0] }
        let trigger = destinationConfig?.trigger ?? source.trigger
        let interval = destinationConfig?.interval ?? source.interval

        if let destinationRuleID,
           let index = draft.customRules.firstIndex(where: {
               $0.id == destinationRuleID
           }) {
            draft.customRules[index].trigger = trigger
            draft.customRules[index].interval = interval
            if !draft.customRules[index].selectedMetrics.contains(metric) {
                draft.customRules[index].additionalMetrics =
                    (draft.customRules[index].additionalMetrics ?? []) + [metric]
            }
            // Preserve an authored motivation sentence when that individual
            // command is dragged into another group's shared spoken cue.
            if metric == .motivation,
               let phrase = source.customPhrase?.trimmingCharacters(
                   in: .whitespacesAndNewlines
               ), !phrase.isEmpty {
                let original = draft.customRules[index].customPhrase ?? ""
                let combined = original.isEmpty ? phrase : original + " " + phrase
                draft.customRules[index].customPhrase =
                    String(combined.prefix(180))
            }
        } else {
            var newRule = source
            newRule.id = UUID()
            newRule.trigger = trigger
            newRule.interval = interval
            newRule.metric = metric
            newRule.additionalMetrics = nil
            if metric != .motivation { newRule.customPhrase = nil }
            draft.customRules.append(newRule)
            if let targetIndex {
                draft.coachGroups[targetIndex].ruleIDs.append(newRule.id)
            }
        }

        // Remove just the dragged value, not every value at its original
        // trigger. Only drop the old rule when it has no remaining content.
        let remaining = source.selectedMetrics.filter { $0 != metric }
        if let index = draft.customRules.firstIndex(where: { $0.id == id }) {
            if let next = remaining.first {
                draft.customRules[index].metric = next
                draft.customRules[index].additionalMetrics = Array(
                    remaining.dropFirst()
                )
                if next != .motivation {
                    draft.customRules[index].customPhrase = nil
                }
            } else {
                draft.customRules.remove(at: index)
                for groupIndex in draft.coachGroups.indices {
                    draft.coachGroups[groupIndex].ruleIDs.removeAll { $0 == id }
                }
            }
        }
        return true
    }
}
