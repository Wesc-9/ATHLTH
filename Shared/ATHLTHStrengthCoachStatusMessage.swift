import Foundation

/// A fresh, localized set/exercise summary independent of workout capture.
/// Never persists exercise names, notes or training measurements.
enum ATHLTHStrengthCoachStatusMessage {
    static func make(
        completedSets: Int,
        totalSets: Int,
        exerciseName: String?,
        restEndsAt: Date?,
        now: Date = Date(),
        norwegian: Bool
    ) -> String {
        let complete = max(completedSets, 0)
        let total = max(totalSets, complete)
        var parts = [
            norwegian
                ? "\(complete) av \(total) sett fullført."
                : "\(complete) of \(total) sets complete."
        ]

        if let exerciseName,
           !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(
                norwegian
                    ? "Nåværende øvelse: \(exerciseName)."
                    : "Current exercise: \(exerciseName)."
            )
        }

        if let restEndsAt {
            let seconds = max(Int(restEndsAt.timeIntervalSince(now).rounded()), 0)
            if seconds > 0 {
                parts.append(
                    norwegian
                        ? "\(seconds) sekunder igjen av hvilen."
                        : "\(seconds) seconds of rest remaining."
                )
            }
        }

        return parts.joined(separator: " ")
    }
}
