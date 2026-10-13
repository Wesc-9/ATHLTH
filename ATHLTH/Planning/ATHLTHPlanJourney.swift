import Foundation

/// Canonical navigation contract for the plan-creation experience.
/// Both simple and advanced modes create the same persisted TrainingPlan.
enum ATHLTHPlanJourneyStep: Int, CaseIterable {
    case mode
    case basics
    case source
    case profile
    case week
    case review
}

enum ATHLTHPlanJourney {
    static func sequence(advanced: Bool) -> [ATHLTHPlanJourneyStep] {
        if advanced {
            return [.mode, .basics, .source, .profile, .week, .review]
        }
        return [.mode, .basics]
    }

    static func position(
        of step: ATHLTHPlanJourneyStep,
        advanced: Bool
    ) -> Int? {
        sequence(advanced: advanced)
            .firstIndex(of: step)
            .map { $0 + 1 }
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
