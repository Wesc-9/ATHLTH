import Foundation

/// Quick strength entry can explicitly request an exercise composer while
/// keeping the saved-workout and free-training start paths unchanged.
enum ATHLTHStrengthQuickStartEntryPolicy {
    static func initialType(
        requested: ATHLTHQuickStartType?,
        hasStructuredBlocks: Bool,
        hasExercises: Bool
    ) -> ATHLTHQuickStartType {
        if requested == .exercises { return .exercises }
        if requested == .free { return .free }
        if hasStructuredBlocks { return .workout }
        return hasExercises ? .exercises : .free
    }
}
