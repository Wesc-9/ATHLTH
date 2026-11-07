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
        case heartRateZone
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
            case .heartRateZone: return ATHLTHLocalization.choose(
                english: "Heart-rate zone", norwegian: "Pulssone")
            }
        }
    }

    var id: UUID = UUID()
    var trigger: Trigger
    var metric: Metric
    /// Metres for distance rules, seconds for time rules.
    var interval: Int
    /// Optional for compatibility with existing stored one-metric rules.
    /// A single scheduled event can read several metrics as ONE spoken cue.
    var additionalMetrics: [Metric]? = nil

    var selectedMetrics: [Metric] {
        var ordered: [Metric] = [metric]
        for next in additionalMetrics ?? [] where !ordered.contains(next) {
            ordered.append(next)
        }
        return Array(ordered.prefix(5))
    }

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
        norwegian: Bool,
        maximumHeartRateBPM: Double? = nil,
        excluding excludedMetrics: Set<Metric> = []
    ) -> String? {
        let parts = selectedMetrics.filter {
            !excludedMetrics.contains($0)
        }.compactMap { item in
            component(
                item, distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds,
                paceSecondsPerKilometer: paceSecondsPerKilometer,
                heartRateBPM: heartRateBPM, norwegian: norwegian,
                maximumHeartRateBPM: maximumHeartRateBPM
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    private func component(
        _ metric: Metric,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        maximumHeartRateBPM: Double?
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
        case .heartRateZone:
            guard let zone = ATHLTHHeartRateZones.measuredZone(
                heartRateBPM: heartRateBPM, maximumBPM: maximumHeartRateBPM
            ) else { return nil }
            return norwegian ? "Pulssone \(zone)" : "Heart-rate zone \(zone)"
        }
    }
}

/// A spoken rule together with the metrics it covers. Used by both voice
/// owners to combine scheduled/default updates without repeating a metric.
struct ATHLTHAudioCoachDueAnnouncement {
    let text: String
    let metrics: Set<ATHLTHAudioCoachRule.Metric>
    /// Deterministic milestone identity, stable across Watch and phone.
    let milestoneKey: String
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
        maximumHeartRateBPM: Double? = nil,
        lastSlots: inout [UUID: Int]
    ) -> [String] {
        dueAnnouncements(
            rules: rules,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            paceSecondsPerKilometer: paceSecondsPerKilometer,
            heartRateBPM: heartRateBPM,
            norwegian: norwegian,
            maximumHeartRateBPM: maximumHeartRateBPM,
            lastSlots: &lastSlots
        ).map(\.text)
    }

    static func dueAnnouncements(
        rules: [ATHLTHAudioCoachRule],
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        maximumHeartRateBPM: Double? = nil,
        lastSlots: inout [UUID: Int]
    ) -> [ATHLTHAudioCoachDueAnnouncement] {
        var messages: [ATHLTHAudioCoachDueAnnouncement] = []
        var spokenMetrics: Set<ATHLTHAudioCoachRule.Metric> = []
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
            // Simultaneous rules are composed into one speech event. A
            // metric already included by another rule is not repeated.
            let available = rule.selectedMetrics.filter { metric in
                switch metric {
                case .heartRate: return heartRateBPM != nil
                case .heartRateZone:
                    return ATHLTHHeartRateZones.measuredZone(
                        heartRateBPM: heartRateBPM,
                        maximumBPM: maximumHeartRateBPM
                    ) != nil
                case .pace: return paceSecondsPerKilometer != nil
                case .distance, .elapsedTime: return true
                }
            }
            let effective = available.filter { !spokenMetrics.contains($0) }
            guard !effective.isEmpty,
                  let message = rule.phrase(
                    distanceMeters: distanceMeters,
                    elapsedSeconds: elapsedSeconds,
                    paceSecondsPerKilometer: paceSecondsPerKilometer,
                    heartRateBPM: heartRateBPM,
                    norwegian: norwegian,
                    maximumHeartRateBPM: maximumHeartRateBPM,
                    excluding: Set(rule.selectedMetrics).subtracting(effective)
                  ) else { continue }
            let covered = Set(effective)
            messages.append(ATHLTHAudioCoachDueAnnouncement(
                text: message,
                metrics: covered,
                milestoneKey: rule.id.uuidString + ":" + String(current)
            ))
            spokenMetrics.formUnion(covered)
        }
        return messages
    }

    /// Event receipts must identify the scheduled milestone, not the
    /// exact live distance/time when speech starts. Watch/iPhone snapshots
    /// arrive at different moments and otherwise produce different keys.
    /// A small deterministic digest also stays beneath receipt length limits
    /// when several custom rules happen together.
    static func stableDeliveryKey(
        standardMilestones: [String],
        customAnnouncements: [ATHLTHAudioCoachDueAnnouncement]
    ) -> String {
        let pieces = (
            standardMilestones.map { "s:" + $0 } +
            customAnnouncements.map { "c:" + $0.milestoneKey }
        ).sorted()
        var digest: UInt64 = 0xcbf29ce484222325
        for byte in pieces.joined(separator: "|").utf8 {
            digest = (digest ^ UInt64(byte)) &* 0x100000001b3
        }
        return "audio:" + String(digest, radix: 16)
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
