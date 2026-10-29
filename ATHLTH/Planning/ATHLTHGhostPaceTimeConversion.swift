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
        guard fields.count == 2,
              let minutes = Int(fields[0]),
              let seconds = Int(fields[1]),
              minutes >= 0, (0..<60).contains(seconds)
        else { return nil }

        let pace = TimeInterval(minutes * 60 + seconds)
        // Reject impossible or accidental inputs; 13:52/km and walking
        // paces remain supported.
        guard pace.isFinite, (30...3_600).contains(pace) else {
            return nil
        }
        return pace
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
