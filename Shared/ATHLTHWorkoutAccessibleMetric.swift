import Foundation

/// Screen-reader wording shared by Watch and phone workout surfaces.
/// Never narrate missing sensor data as zero or as a confirmed live value.
enum ATHLTHWorkoutAccessibleMetric {
    static func duration(_ seconds: TimeInterval, norwegian: Bool) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return norwegian ? "Tid ikke tilgjengelig" : "Time unavailable"
        }
        // Real-world workout durations are bounded before Int conversion.
        // Avoid overflow if corrupt telemetry contains an extreme value.
        let total = Int(min(seconds.rounded(.down), 365 * 24 * 3_600))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60

        func spoken(_ number: Int, singular: String, plural: String) -> String {
            "\(number) \(number == 1 ? singular : plural)"
        }

        var parts: [String] = []
        if hours > 0 {
            parts.append(spoken(
                hours, singular: norwegian ? "time" : "hour",
                plural: norwegian ? "timer" : "hours"
            ))
        }
        if minutes > 0 {
            parts.append(spoken(
                minutes, singular: norwegian ? "minutt" : "minute",
                plural: norwegian ? "minutter" : "minutes"
            ))
        }
        if remainder > 0 || parts.isEmpty {
            parts.append(spoken(
                remainder, singular: norwegian ? "sekund" : "second",
                plural: norwegian ? "sekunder" : "seconds"
            ))
        }
        return parts.joined(separator: ", ")
    }

    static func distance(_ meters: Double, norwegian: Bool) -> String {
        guard meters.isFinite, meters >= 0 else {
            return norwegian ? "Distanse ikke tilgjengelig" : "Distance unavailable"
        }
        if meters < 1_000 {
            return "\(Int(meters.rounded())) \(norwegian ? "meter" : "meters")"
        }
        let kilometers = String(format: "%.2f", meters / 1_000)
        return "\(kilometers) \(norwegian ? "kilometer" : "kilometers")"
    }

    static func pulse(
        _ bpm: Double,
        isFresh: Bool,
        norwegian: Bool
    ) -> String {
        guard isFresh, bpm.isFinite, bpm > 0 else {
            return norwegian ? "Venter på pulsmåling" : "Waiting for heart-rate sensor"
        }
        return "\(Int(bpm.rounded())) \(norwegian ? "slag i minuttet" : "beats per minute")"
    }
}
