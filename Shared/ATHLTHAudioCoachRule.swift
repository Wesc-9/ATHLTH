import Foundation

/// Independent periodic Audio Coach rules. Stored as part of the iPhone
/// settings and copied unchanged to a Watch workout's configuration.
struct ATHLTHAudioCoachRule: Codable, Hashable, Identifiable {
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case distance
        case time
        var id: String { rawValue }
        var title: String {
            switch self {
            case .distance: return ATHLTHLocalization.choose(
                english: "Distance", norwegian: "Distanse")
            case .time: return ATHLTHLocalization.choose(
                english: "Time", norwegian: "Tid")
            }
        }
    }

    enum Metric: String, Codable, CaseIterable, Identifiable {
        case pace
        case elapsedTime
        case distance
        case heartRate
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pace: return ATHLTHLocalization.choose(
                english: "Pace", norwegian: "Tempo")
            case .elapsedTime: return ATHLTHLocalization.choose(
                english: "Elapsed time", norwegian: "Medgått tid")
            case .distance: return ATHLTHLocalization.choose(
                english: "Distance", norwegian: "Distanse")
            case .heartRate: return ATHLTHLocalization.choose(
                english: "Heart rate", norwegian: "Puls")
            }
        }
    }

    var id: UUID = UUID()
    var trigger: Trigger
    var metric: Metric
    /// Metres for distance rules, seconds for time rules.
    var interval: Int

    var validatedInterval: Int {
        switch trigger {
        case .distance: return min(max(interval, 100), 42_000)
        case .time: return min(max(interval, 15), 7_200)
        }
    }

    func phrase(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool
    ) -> String? {
        switch metric {
        case .pace:
            guard let pace = paceSecondsPerKilometer, pace.isFinite,
                  pace > 0, pace < 3_600 else { return nil }
            let seconds = Int(pace.rounded())
            let minutes = seconds / 60
            let remainder = seconds % 60
            return norwegian
                ? "Tempo \(minutes) minutter \(remainder) sekunder per kilometer"
                : "Pace \(minutes) minutes \(remainder) seconds per kilometer"
        case .elapsedTime:
            guard elapsedSeconds.isFinite, elapsedSeconds >= 0 else { return nil }
            let seconds = Int(elapsedSeconds.rounded(.down))
            let minutes = seconds / 60
            let remainder = seconds % 60
            return norwegian
                ? "Tid \(minutes) minutter \(remainder) sekunder"
                : "Time \(minutes) minutes \(remainder) seconds"
        case .distance:
            guard distanceMeters.isFinite, distanceMeters >= 0 else { return nil }
            return norwegian
                ? String(format: "Distanse %.2f kilometer", distanceMeters / 1_000)
                : String(format: "Distance %.2f kilometers", distanceMeters / 1_000)
        case .heartRate:
            guard let heartRateBPM, heartRateBPM.isFinite,
                  (30...230).contains(heartRateBPM) else { return nil }
            return norwegian ? "Puls \(Int(heartRateBPM.rounded()))"
                : "Heart rate \(Int(heartRateBPM.rounded()))"
        }
    }
}

/// Evaluates each user's distance/time rule independently. The slot journal
/// prevents repeats when workout snapshots arrive more than once per second.
enum ATHLTHAudioCoachRuleDelivery {
    static func initialSlots(
        rules: [ATHLTHAudioCoachRule],
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for rule in rules {
            result[rule.id] = slot(
                for: rule,
                distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds
            )
        }
        return result
    }

    static func dueMessages(
        rules: [ATHLTHAudioCoachRule],
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        lastSlots: inout [UUID: Int]
    ) -> [String] {
        var messages: [String] = []
        for rule in rules.prefix(20) {
            let current = slot(
                for: rule,
                distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds
            )
            let previous = lastSlots[rule.id] ?? 0
            guard current > previous else { continue }
            // Consume the crossed milestone even if a sensor value is missing.
            // It must not be announced much later after that value recovers.
            lastSlots[rule.id] = current
            guard let message = rule.phrase(
                distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds,
                paceSecondsPerKilometer: paceSecondsPerKilometer,
                heartRateBPM: heartRateBPM,
                norwegian: norwegian
            ) else { continue }
            messages.append(message)
        }
        return messages
    }

    private static func slot(
        for rule: ATHLTHAudioCoachRule,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Int {
        let value = rule.trigger == .distance ? distanceMeters : elapsedSeconds
        guard value.isFinite, value >= 0 else { return 0 }
        return Int(min(
            floor(value / Double(rule.validatedInterval)),
            Double(Int.max / 2)
        ))
    }
}

struct ATHLTHAudioCoachRuleSet: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var rules: [ATHLTHAudioCoachRule]
}
/// Workout-local rule cadence. Each rule advances independently, so adding a
/// 30-second time cue never changes a kilometre-based pace cue. Late time slots
/// are skipped rather than spoken in a burst after a pause or reconnect.
struct ATHLTHAudioCoachRuleSchedule {
    private var nextByRuleID: [UUID: Double] = [:]

    mutating func reset(
        rules: [ATHLTHAudioCoachRule]?,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) {
        nextByRuleID.removeAll(keepingCapacity: true)
        for rule in (rules ?? []).prefix(20) {
            let current = rule.trigger == .distance
                ? distanceMeters : elapsedSeconds
            guard current.isFinite else { continue }
            let step = Double(rule.validatedInterval)
            nextByRuleID[rule.id] =
                (floor(max(current, 0) / step) + 1) * step
        }
    }

    mutating func consumeDue(
        rules: [ATHLTHAudioCoachRule]?,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> [ATHLTHAudioCoachRule] {
        var due: [ATHLTHAudioCoachRule] = []
        for rule in (rules ?? []).prefix(20) {
            let current = rule.trigger == .distance
                ? distanceMeters : elapsedSeconds
            guard current.isFinite, current >= 0 else { continue }
            let step = Double(rule.validatedInterval)
            guard let next = nextByRuleID[rule.id] else {
                // A new rule added during an ongoing session starts at its
                // next full interval, not with an old catch-up announcement.
                nextByRuleID[rule.id] =
                    (floor(current / step) + 1) * step
                continue
            }
            guard current >= next else { continue }
            nextByRuleID[rule.id] = (floor(current / step) + 1) * step
            if rule.trigger == .time && current - next > 2.5 {
                continue
            }
            due.append(rule)
        }
        return due
    }
}
