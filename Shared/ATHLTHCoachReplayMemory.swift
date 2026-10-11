import Foundation

/// One recent spoken Audio Coach cue, never persisted or transmitted.
/// Only normal coaching is retained; critical route/target and Ghost alerts
/// must not be replayed as if they represented current conditions.
struct ATHLTHCoachReplayMemory {
    private(set) var text: String?
    private(set) var spokenAt: Date?

    static let maximumReplayAge: TimeInterval = 45

    mutating func remember(
        _ phrase: String,
        priority: ATHLTHGuidancePriority,
        at date: Date = Date()
    ) {
        guard Self.mayRemember(priority: priority),
              !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        text = phrase
        spokenAt = date
    }

    func replayableText(at now: Date = Date()) -> String? {
        guard let text, let spokenAt,
              now.timeIntervalSince(spokenAt) >= -2,
              now.timeIntervalSince(spokenAt) <= Self.maximumReplayAge
        else { return nil }
        return text
    }

    mutating func reset() {
        text = nil
        spokenAt = nil
    }

    static func mayRemember(
        priority: ATHLTHGuidancePriority
    ) -> Bool {
        priority == .routineCoach || priority == .structuredStep
    }
}
