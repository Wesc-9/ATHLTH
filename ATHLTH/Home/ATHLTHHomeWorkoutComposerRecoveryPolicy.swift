import Foundation

/// Restore only the signed-in athlete's recoverable day-workout editor.
enum ATHLTHHomeWorkoutComposerRecoveryPolicy {
    static func canRestore(account: String, currentAccountID: UUID, day: TimeInterval) -> Bool {
        account == currentAccountID.uuidString && day.isFinite && day > 0
    }
}
