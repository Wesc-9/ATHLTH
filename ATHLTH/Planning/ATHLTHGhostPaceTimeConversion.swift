import Foundation

/// Two-way conversion for Ghost Race goals using the selected route distance.
/// The source of truth for launching a Ghost remains target duration.
enum ATHLTHGhostPaceTimeConversion {
    static func paceSeconds(from input: String) -> TimeInterval? {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "/km", with: "", options: .caseInsensitive
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = trimmed.split(
            separator: ":", omittingEmptySubsequences: false
        )
        // "5" is five minutes per km (5:00), not an invalid pace.
        // Keep full M:SS input and reject incomplete/ambiguous forms.
        guard (1...2).contains(fields.count),
              let minutes = Int(fields[0]),
              (0...60).contains(minutes)
        else { return nil }
        let seconds: Int
        if fields.count == 2 {
            guard let parsed = Int(fields[1]), (0..<60).contains(parsed)
            else { return nil }
            seconds = parsed
        } else {
            seconds = 0
        }

        let pace = TimeInterval(minutes * 60 + seconds)
        // Reject impossible or accidental inputs; 13:52/km and walking
        // paces remain supported.
        guard pace.isFinite, (30...3_600).contains(pace) else {
            return nil
        }
        return pace
    }

    /// Expand shorthand only when the athlete finishes editing so typing
    /// "5:30" never causes cursor jumps or wipes an in-progress value.
    static func normalizedPaceText(from input: String) -> String? {
        guard let seconds = paceSeconds(from: input) else { return nil }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func paceText(
        duration: TimeInterval?,
        distanceKilometers: Double?
    ) -> String? {
        guard let duration, let distanceKilometers,
              duration.isFinite, duration > 0,
              distanceKilometers.isFinite, distanceKilometers > 0
        else { return nil }

        let pace = duration / distanceKilometers
        guard pace.isFinite, (30...3_600).contains(pace) else {
            return nil
        }
        let rounded = Int(pace.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    static func targetDuration(
        paceText: String,
        distanceKilometers: Double?
    ) -> TimeInterval? {
        guard let distanceKilometers,
              distanceKilometers.isFinite, distanceKilometers > 0,
              let pace = paceSeconds(from: paceText)
        else { return nil }

        let duration = (distanceKilometers * pace).rounded()
        guard duration.isFinite, duration > 0, duration <= 86_400 else {
            return nil
        }
        return duration
    }
}
