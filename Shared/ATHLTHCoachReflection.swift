import Foundation

/// Minimal, read-only snapshot for an explicit coach reflection. No identity,
/// location, history, route, exercise names or raw health samples.
struct ATHLTHCoachReflection: Equatable {
    enum Focus: String, CaseIterable {
        case consistency, pacing, recovery, strength, plannedProgress
        func title(norwegian: Bool) -> String {
            switch self {
            case .consistency: return norwegian ? "Fokuser på en jevn, kontrollert innsats." : "Focus on a steady, controlled effort."
            case .pacing: return norwegian ? "Bruk registrert tempo som referanse, ikke som et krav om å løpe raskere." : "Use recorded pace as a reference, not a requirement to run faster."
            case .recovery: return norwegian ? "Ta hensyn til hvordan økten føles, og gi deg selv tid til å hente deg inn." : "Consider how the workout feels and give yourself time to recover."
            case .strength: return norwegian ? "Prioriter god teknikk og tilstrekkelig pause mellom settene." : "Prioritize good technique and sufficient rest between sets."
            case .plannedProgress: return norwegian ? "Følg den planlagte progresjonen i ditt eget tempo." : "Follow the planned progression at your own pace."
            }
        }
    }

    let activity: String
    let completed: Bool
    let elapsedSeconds: Double?
    let distanceMeters: Double?
    let paceSecondsPerKilometer: Double?
    let heartRateBPM: Double?
    let completedSets: Int?
    let planned: Bool

    init(activity: String, completed: Bool, elapsedSeconds: Double?,
         distanceMeters: Double?, paceSecondsPerKilometer: Double?,
         heartRateBPM: Double?, completedSets: Int? = nil, planned: Bool = false) {
        let allowed = ["running", "walking", "strength", "cycling", "rowing", "hiit", "functional", "stairClimbing", "yoga", "other", "sports"]
        self.activity = allowed.contains(activity) ? activity : "other"
        self.completed = completed
        self.elapsedSeconds = Self.bounded(elapsedSeconds, 0...172800)
        self.distanceMeters = Self.bounded(distanceMeters, 1...1_000_000)
        self.paceSecondsPerKilometer = Self.bounded(paceSecondsPerKilometer, 120...1800)
        self.heartRateBPM = Self.bounded(heartRateBPM, 35...250)
        self.completedSets = completedSets.flatMap { (0...1000).contains($0) ? $0 : nil }
        self.planned = planned
    }

    private static func bounded(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    var choices: [Focus] {
        var values: [Focus] = [.consistency, .recovery]
        if activity == "strength" { values.append(.strength) }
        if paceSecondsPerKilometer != nil && ["running", "walking"].contains(activity) { values.append(.pacing) }
        if planned { values.append(.plannedProgress) }
        return values
    }

    var fallback: Focus {
        if completed { return .recovery }
        if activity == "strength" { return .strength }
        if planned { return .plannedProgress }
        return .consistency
    }

    /// AI can choose only a verified candidate, never a workout command.
    func validatedChoice(_ answer: String) -> Focus? {
        let candidate = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let focus = Focus(rawValue: candidate), choices.contains(focus) else { return nil }
        return focus
    }

    func facts(norwegian: Bool) -> [String] {
        var result: [String] = []
        if let seconds = elapsedSeconds {
            result.append((norwegian ? "Tid: " : "Time: ") + ATHLTHWorkoutSummaryEngine.durationText(seconds))
        }
        if let meters = distanceMeters {
            result.append((norwegian ? "Distanse: " : "Distance: ") + ATHLTHWorkoutSummaryEngine.distanceText(meters))
        }
        if let pace = paceSecondsPerKilometer {
            result.append((norwegian ? "Tempo: " : "Pace: ") + ATHLTHWorkoutSummaryEngine.paceText(pace))
        }
        if let pulse = heartRateBPM {
            result.append((completed ? (norwegian ? "Snittpuls: " : "Average HR: ") : (norwegian ? "Puls: " : "Heart rate: ")) + ATHLTHWorkoutSummaryEngine.pulseText(pulse))
        }
        if let sets = completedSets { result.append((norwegian ? "Fullførte sett: " : "Completed sets: ") + String(sets)) }
        return result
    }

    /// Coarse, non-identifying training context only. No pulse or exact
    /// distance is sent to the model. Facts stay on the device.
    var modelPrompt: String {
        let minutes = elapsedSeconds.map { Int($0 / 300) * 5 }.map(String.init) ?? "unknown"
        return """
        Pick one focus for a brief general fitness reflection. Do not give medical advice or alter a workout.
        Activity: \(activity). Completed: \(completed). Approximate minutes: \(minutes).
        Pace available: \(paceSecondsPerKilometer != nil). Planned workout: \(planned).
        Return exactly one identifier from: \(choices.map(\.rawValue).joined(separator: ", ")).
        """
    }
}
