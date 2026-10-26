import Foundation

/// Canonical navigation contract for the plan-creation experience.
/// Both simple and advanced modes create the same persisted TrainingPlan.
enum ATHLTHPlanJourneyStep: Int, CaseIterable {
    case mode
    case goal
    case basics
    case source
    case profile // Legacy draft stage; new plans skip this question screen.
    case approach
    case week
    case review
}

enum ATHLTHPlanJourney {
    static func sequence(advanced: Bool) -> [ATHLTHPlanJourneyStep] {
        if advanced {
            return [.mode, .goal, .basics, .approach, .week, .review]
        }
        return [.mode, .goal, .basics]
    }

    static func displayedCount(advanced: Bool) -> Int {
        // The in-place review shares step five with the week builder.
        advanced ? 5 : sequence(advanced: false).count
    }

    static func position(
        of step: ATHLTHPlanJourneyStep,
        advanced: Bool
    ) -> Int? {
        let index = sequence(advanced: advanced)
            .firstIndex(of: step)
            .map { $0 + 1 }
        // Review is part of the final plan-building stage in the UI.
        if advanced && step == .review { return 5 }
        return index
    }

    /// Resume only known stages. Unrecognized legacy values fall back to
    /// the mode choice instead of silently dropping the entire draft.
    static func restoredStep(_ stored: String, advanced: Bool) -> ATHLTHPlanJourneyStep {
        guard let candidate = ATHLTHPlanJourneyStep.allCases.first(where: {
            String(describing: $0) == stored
        }) else { return .mode }
        // A draft created before the new method choice must resume safely.
        if candidate == .profile && advanced { return .approach }
        // Source is retained as a valid legacy branch; it is not in today's
        // standard simple/advanced progression.
        if candidate == .source { return .source }
        return sequence(advanced: advanced).contains(candidate) ? candidate : .basics
    }

    static func next(
        after step: ATHLTHPlanJourneyStep,
        advanced: Bool
    ) -> ATHLTHPlanJourneyStep? {
        let path = sequence(advanced: advanced)
        guard let position = path.firstIndex(of: step),
              position + 1 < path.count else {
            return nil
        }
        return path[position + 1]
    }

    static func previous(
        before step: ATHLTHPlanJourneyStep,
        advanced: Bool
    ) -> ATHLTHPlanJourneyStep? {
        let path = sequence(advanced: advanced)
        guard let position = path.firstIndex(of: step),
              position > 0 else {
            return nil
        }
        return path[position - 1]
    }
}
