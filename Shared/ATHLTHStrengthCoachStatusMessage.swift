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
    
    /// One optional, strength-only motivation cue after an exact set milestone.
    /// A personal sentence takes precedence and is never auto-generated for other sports.
    static func setMilestoneMotivation(
        completedSets: Int,
        everySets: Int?,
        personalMessage: String?,
        norwegian: Bool
    ) -> String? {
        guard let everySets, (1...10).contains(everySets),
              completedSets > 0, completedSets % everySets == 0 else { return nil }
        let personal = (personalMessage ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !personal.isEmpty { return String(personal.prefix(180)) }
        let phrases = norwegian
            ? ["Bra jobbet! Fortsett med samme fokus.",
               "Sterk innsats! Ta med deg energien inn i neste sett.",
               "Godt gjennomført! Hold teknikken kontrollert."]
            : ["Great work! Keep your focus.",
               "Strong effort! Bring that energy into the next set.",
               "Well done! Keep your technique controlled."]
        return phrases[((completedSets / everySets) - 1) % phrases.count]
    }

}
