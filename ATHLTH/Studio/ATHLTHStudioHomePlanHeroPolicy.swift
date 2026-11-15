import Foundation

/// Keeps the iPad Home plan heading truthful for active, future and missing
/// plans. Cloud presence is displayed separately from local plan timing.
enum ATHLTHStudioHomePlanHeroPolicy {
    static func statusLabel(
        for status: TrainingPlanTimingStatus?,
        norwegian: Bool
    ) -> String {
        switch status {
        case .active:
            return norwegian ? "AKTIV TRENINGSPLAN" : "ACTIVE TRAINING PLAN"
        case .upcoming:
            return norwegian ? "KOMMENDE TRENINGSPLAN" : "UPCOMING TRAINING PLAN"
        case .completed:
            return norwegian ? "FULLFØRT TRENINGSPLAN" : "COMPLETED TRAINING PLAN"
        case .unscheduled:
            return norwegian ? "TRENINGPLAN UTEN DATO" : "UNSCHEDULED TRAINING PLAN"
        case nil:
            return norwegian ? "INGEN AKTIV TRENINGSPLAN" : "NO ACTIVE TRAINING PLAN"
        }
    }
}
