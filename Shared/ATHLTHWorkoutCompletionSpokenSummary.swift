import Foundation

/// One verified workout metric source for iPhone and Apple Watch completion
/// announcements. Personal records are never inferred from a single workout:
/// callers may add them only after a genuine history/record comparison.
enum ATHLTHWorkoutCompletionSpokenSummary {
    static func make(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        averageHeartRateBPM: Double? = nil,
        verifiedRecordEnglish: String? = nil,
        verifiedRecordNorwegian: String? = nil
    ) -> (english: String, norwegian: String) {
        let seconds = elapsedSeconds.isFinite
            ? max(0, Int(elapsedSeconds.rounded())) : 0
        let minutes = seconds / 60
        let remaining = seconds % 60

        var english = ["Workout complete."]
        var norwegian = ["Økten er fullført."]

        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            english.append("Time: \(hours) hours and \(rest) minutes.")
            norwegian.append("Tid: \(hours) timer og \(rest) minutter.")
        } else if minutes > 0 {
            english.append("Time: \(minutes) minutes and \(remaining) seconds.")
            norwegian.append("Tid: \(minutes) minutter og \(remaining) sekunder.")
        } else {
            english.append("Time: \(remaining) seconds.")
            norwegian.append("Tid: \(remaining) sekunder.")
        }

        if distanceMeters.isFinite, distanceMeters > 0 {
            let km = distanceMeters / 1_000
            let decimal = String(format: "%.2f", km)
            english.append("Distance: \(decimal) kilometres.")
            norwegian.append("Distanse: \(decimal.replacingOccurrences(of: ".", with: ",")) kilometer.")

            if distanceMeters >= 250 && elapsedSeconds.isFinite,
               elapsedSeconds > 0 {
                let paceSeconds = elapsedSeconds / km
                if paceSeconds.isFinite, (120...3_600).contains(paceSeconds) {
                    let pace = Int(paceSeconds.rounded())
                    english.append("Average pace: \(pace / 60) minutes and \(pace % 60) seconds per kilometre.")
                    norwegian.append("Snittempo: \(pace / 60) minutter og \(pace % 60) sekunder per kilometer.")
                }
            }
        }

        if let heartRate = averageHeartRateBPM, heartRate.isFinite,
           (30...240).contains(heartRate) {
            english.append("Average heart rate: \(Int(heartRate.rounded())) beats per minute.")
            norwegian.append("Snittpuls: \(Int(heartRate.rounded())) slag i minuttet.")
        }

        if let verifiedRecordEnglish,
           let verifiedRecordNorwegian,
           !verifiedRecordEnglish.isEmpty,
           !verifiedRecordNorwegian.isEmpty {
            english.append(verifiedRecordEnglish)
            norwegian.append(verifiedRecordNorwegian)
        }

        return (english.joined(separator: " "), norwegian.joined(separator: " "))
    }
}

/// Pure comparison, shared by saved iPhone sessions and authorized Apple
/// Health history on Watch. A first activity is never called a new record.
struct ATHLTHVerifiedRunningEvidence: Hashable {
    let distanceMeters: Double
    let activeSeconds: TimeInterval
}

enum ATHLTHVerifiedRunningRecordComparison {
    enum Achievement: Hashable {
        case longestDistance
        case fastestAveragePace
    }

    static func achievements(
        current: ATHLTHVerifiedRunningEvidence,
        previous: [ATHLTHVerifiedRunningEvidence]
    ) -> Set<Achievement> {
        guard current.distanceMeters.isFinite,
              current.activeSeconds.isFinite,
              current.distanceMeters >= 1_000,
              current.activeSeconds > 0
        else { return [] }
        let validPrevious = previous.filter {
            $0.distanceMeters.isFinite && $0.distanceMeters >= 1_000 &&
            $0.activeSeconds.isFinite && $0.activeSeconds > 0
        }
        guard !validPrevious.isEmpty else { return [] }
        var results: Set<Achievement> = []
        if let distance = validPrevious.map(\.distanceMeters).max(),
           current.distanceMeters >= distance + 10 {
            results.insert(.longestDistance)
        }
        let previousPaces = validPrevious.map {
            $0.activeSeconds / ($0.distanceMeters / 1_000)
        }.filter { (120...3_600).contains($0) }
        let currentPace = current.activeSeconds /
            (current.distanceMeters / 1_000)
        if let bestPace = previousPaces.min(),
           currentPace.isFinite, (120...3_600).contains(currentPace),
           currentPace <= bestPace - 2 {
            results.insert(.fastestAveragePace)
        }
        return results
    }

    static func phrase(
        achievements: Set<Achievement>,
        sourceEnglish: String,
        sourceNorwegian: String
    ) -> (english: String, norwegian: String)? {
        guard !achievements.isEmpty else { return nil }
        var english: [String] = []
        var norwegian: [String] = []
        if achievements.contains(.longestDistance) {
            english.append("longest recorded run")
            norwegian.append("lengste registrerte løpetur")
        }
        if achievements.contains(.fastestAveragePace) {
            english.append("best average pace on a recorded run")
            norwegian.append("beste gjennomsnittstempo på en registrert løpetur")
        }
        return (
            english: "New record in \(sourceEnglish): " +
                english.joined(separator: ", ") + ".",
            norwegian: "Ny rekord i \(sourceNorwegian): " +
                norwegian.joined(separator: ", ") + "."
        )
    }
}
