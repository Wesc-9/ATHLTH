import Foundation

/// Independent periodic Audio Coach rules. Stored as part of the iPhone
/// settings and copied unchanged to a Watch workout's configuration.
struct ATHLTHAudioCoachRule: Codable, Hashable, Identifiable {
    /// Persisted in the same rules transferred to Watch. Existing raw values
    /// remain intact; newly configured event rules share the normal cue ledger.
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case distance, time
        case heartRateAbove, heartRateBelow, zoneEnter, zoneExit
        case workoutStart
        case effortStart, effortEnd, recoveryStart, recoveryEnd
        case activeRecoveryStart, activeRecoveryEnd
        case warmupStart, warmupEnd, mainStart, mainEnd
        case cooldownStart, cooldownEnd
        case stepStart, beforeNextStep, beforeMain, beforeCooldown

        var id: String { rawValue }
        var isPeriodic: Bool { self == .time || self == .distance }
        var isHeartRateCondition: Bool {
            switch self {
            case .heartRateAbove, .heartRateBelow, .zoneEnter, .zoneExit: true
            default: false
            }
        }
        var needsStructuredStep: Bool {
            !isPeriodic && !isHeartRateCondition && self != .workoutStart
        }
        var title: String {
            func tr(_ en: String, _ no: String) -> String {
                ATHLTHLocalization.choose(english: en, norwegian: no)
            }
            switch self {
            case .distance: return tr("Distance", "Distanse")
            case .time: return tr("Time", "Tid")
            case .heartRateAbove: return tr("Heart rate above", "Puls over")
            case .heartRateBelow: return tr("Heart rate below", "Puls under")
            case .zoneEnter: return tr("Enter HR zone", "Inn i pulssone")
            case .zoneExit: return tr("Leave HR zone", "Ut av pulssone")
            case .workoutStart: return tr("Workout starts", "Økten starter")
            case .effortStart: return tr("Effort starts", "Drag starter")
            case .effortEnd: return tr("Effort ends", "Drag avsluttes")
            case .recoveryStart: return tr("Recovery starts", "Pause starter")
            case .recoveryEnd: return tr("Recovery ends", "Pause avsluttes")
            case .activeRecoveryStart: return tr("Active recovery starts", "Aktiv pause starter")
            case .activeRecoveryEnd: return tr("Active recovery ends", "Aktiv pause avsluttes")
            case .warmupStart: return tr("Warm-up starts", "Oppvarming starter")
            case .warmupEnd: return tr("Warm-up ends", "Oppvarming avsluttes")
            case .mainStart: return tr("Main part starts", "Hoveddel starter")
            case .mainEnd: return tr("Main part ends", "Hoveddel avsluttes")
            case .cooldownStart: return tr("Cool-down starts", "Nedjogging starter")
            case .cooldownEnd: return tr("Cool-down ends", "Nedjogging avsluttes")
            case .stepStart: return tr("Each workout step starts", "Hver deløkt starter")
            case .beforeNextStep: return tr("Before next step", "Før neste deløkt")
            case .beforeMain: return tr("Before main part", "Før hoveddelen")
            case .beforeCooldown: return tr("Before cool-down", "Før nedjogging")
            }
        }
    }

    enum Metric: String, Codable, CaseIterable, Identifiable {
        case pace
        case elapsedTime
        case distance
        case heartRate
        case heartRateZone
        case motivation
        case hydrationReminder
        case averagePace
        case speed
        case clockTime
        case date
        case stepName
        case stepRemainingTime
        case groupRemainingTime
        case workoutRemainingTime
        case estimatedFinishTime
        case routeRemainingDistance
        case estimatedRouteTime
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
            case .motivation: return ATHLTHLocalization.choose(
                english: "Motivation", norwegian: "Motivasjon")
            case .hydrationReminder: return ATHLTHLocalization.choose(
                english: "Hydration reminder", norwegian: "Drikkepåminnelse")
            case .averagePace: return ATHLTHLocalization.choose(english: "Average pace", norwegian: "Snittempo")
            case .speed: return ATHLTHLocalization.choose(english: "Speed", norwegian: "Hastighet")
            case .clockTime: return ATHLTHLocalization.choose(english: "Clock time", norwegian: "Klokkeslett")
            case .date: return ATHLTHLocalization.choose(english: "Date", norwegian: "Dato")
            case .stepName: return ATHLTHLocalization.choose(english: "Current phase", norwegian: "Gjeldende deløvelse")
            case .stepRemainingTime: return ATHLTHLocalization.choose(english: "Time left in phase", norwegian: "Tid igjen av deløvelsen")
            case .groupRemainingTime: return ATHLTHLocalization.choose(english: "Estimated time left in group", norwegian: "Estimert tid igjen av gruppen")
            case .workoutRemainingTime: return ATHLTHLocalization.choose(english: "Estimated time left in workout", norwegian: "Estimert tid igjen av økten")
            case .estimatedFinishTime: return ATHLTHLocalization.choose(english: "Estimated finish time", norwegian: "Estimert sluttid")
            case .routeRemainingDistance: return ATHLTHLocalization.choose(english: "Route distance remaining", norwegian: "Distanse igjen av ruten")
            case .estimatedRouteTime: return ATHLTHLocalization.choose(english: "Estimated route time remaining", norwegian: "Estimert tid igjen av ruten")
            }
        }
    }

    enum Scope: String, Codable, CaseIterable, Identifiable {
        case workout, effort, group
        var id: String { rawValue }
        var title: String {
            switch self {
            case .workout: return ATHLTHLocalization.choose(english: "Whole workout", norwegian: "Hele økten")
            case .effort: return ATHLTHLocalization.choose(english: "Each effort", norwegian: "Hvert drag")
            case .group: return ATHLTHLocalization.choose(english: "Each interval group", norwegian: "Hver draggruppe")
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
    /// Optional for old saved profiles and existing Watch transfers.
    /// Disabled groups remain visible/editable but never create a spoken cue.
    var enabled: Bool? = nil
    var encouragementStyle: ATHLTHCoachEncouragementStyle? = nil
    var scope: Scope? = nil
    /// An optional single-shot cue before a planned finish. Nothing is
    /// announced if the workout has no reliable remaining-duration estimate.
    var beforeEndSeconds: Int? = nil
    var customPhrase: String? = nil

    var isEnabled: Bool { enabled ?? true }

    var selectedMetrics: [Metric] {
        var ordered: [Metric] = [metric]
        for next in additionalMetrics ?? [] where !ordered.contains(next) {
            ordered.append(next)
        }
        return ordered
    }

    var validatedInterval: Int {
        switch trigger {
        case .distance: return min(max(interval, 100), 42_000)
        case .time: return min(max(interval, 15), 7_200)
        case .heartRateAbove, .heartRateBelow: return min(max(interval, 40), 220)
        case .zoneEnter, .zoneExit: return min(max(interval, 1), 5)
        case .beforeNextStep, .beforeMain, .beforeCooldown:
            return min(max(interval, 5), 60)
        default: return 1
        }
    }

    func phrase(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval,
        paceSecondsPerKilometer: TimeInterval?,
        heartRateBPM: Double?,
        norwegian: Bool,
        maximumHeartRateBPM: Double? = nil,
        context: ATHLTHCoachReadoutContext = .init(),
        now: Date = .now,
        excluding excludedMetrics: Set<Metric> = []
    ) -> String? {
        if beforeEndSeconds != nil,
           let phrase = customPhrase?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phrase.isEmpty {
            return phrase
        }
        let intervalValue = trigger == .distance ? distanceMeters : elapsedSeconds
        let motivationSlot = intervalValue.isFinite && intervalValue >= 0
            ? Int(min(floor(intervalValue / Double(validatedInterval)),
                      Double(Int.max / 2)))
            : 0
        let personal = customPhrase?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = selectedMetrics.filter {
            !excludedMetrics.contains($0)
        }.compactMap { item -> String? in
            if item == .motivation, let personal, !personal.isEmpty {
                return personal
            }
            return component(
                item, distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds,
                paceSecondsPerKilometer: paceSecondsPerKilometer,
                heartRateBPM: heartRateBPM, norwegian: norwegian,
                maximumHeartRateBPM: maximumHeartRateBPM,
                motivationSlot: motivationSlot, context: context, now: now
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
        maximumHeartRateBPM: Double?,
        motivationSlot: Int,
        context: ATHLTHCoachReadoutContext,
        now: Date
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
        case .averagePace:
            guard distanceMeters >= 100 else { return nil }
            return component(.pace, distanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds,
                             paceSecondsPerKilometer: elapsedSeconds * 1000 / distanceMeters,
                             heartRateBPM: nil, norwegian: norwegian, maximumHeartRateBPM: nil,
                             motivationSlot: motivationSlot, context: context, now: now)
                .map { (norwegian ? "Gjennomsnitt. " : "Average. ") + $0 }
        case .speed:
            guard let pace = paceSecondsPerKilometer, pace.isFinite, (30...3_600).contains(pace) else { return nil }
            let speed = (3600 / pace).formatted(.number.precision(.fractionLength(1)))
            return norwegian ? "Hastighet \(speed) kilometer i timen" : "Speed \(speed) kilometers per hour"
        case .clockTime:
            let time = now.formatted(.dateTime.hour().minute().locale(Locale(identifier: norwegian ? "nb_NO" : "en_US")))
            return norwegian ? "Klokken er \(time)" : "The time is \(time)"
        case .date:
            return now.formatted(.dateTime.weekday(.wide).day().month(.wide)
                .locale(Locale(identifier: norwegian ? "nb_NO" : "en_US")))
        case .stepName:
            return context.stepName
        case .stepRemainingTime:
            return context.stepRemainingSeconds.flatMap {
                Self.remaining($0, label: norwegian ? "Igjen av deløvelsen" : "Time left in this phase", norwegian: norwegian)
            }
        case .groupRemainingTime:
            return context.groupRemainingSeconds.flatMap {
                Self.remaining($0, label: norwegian ? "Estimert igjen av gruppen" : "Estimated time left in group", norwegian: norwegian)
            }
        case .workoutRemainingTime:
            return context.workoutRemainingSeconds.flatMap {
                Self.remaining($0, label: norwegian ? "Estimert igjen av økten" : "Estimated time left in workout", norwegian: norwegian)
            }
        case .estimatedFinishTime:
            guard let seconds = context.workoutRemainingSeconds, seconds.isFinite,
                  (0...604_800).contains(seconds) else { return nil }
            let time = now.addingTimeInterval(seconds).formatted(.dateTime.hour().minute()
                .locale(Locale(identifier: norwegian ? "nb_NO" : "en_US")))
            return norwegian ? "Estimert ferdig klokken \(time)" : "Estimated finish at \(time)"
        case .routeRemainingDistance:
            guard let meters = context.routeRemainingMeters, meters.isFinite, meters >= 0 else { return nil }
            let km = (meters / 1000).formatted(.number.precision(.fractionLength(2)))
            return norwegian ? "\(km) kilometer igjen av ruten" : "\(km) kilometers left on route"
        case .estimatedRouteTime:
            guard let meters = context.routeRemainingMeters, let pace = paceSecondsPerKilometer,
                  pace.isFinite, (30...3_600).contains(pace) else { return nil }
            return Self.remaining(meters * pace / 1000,
                                  label: norwegian ? "Estimert igjen av ruten" : "Estimated route time left",
                                  norwegian: norwegian)
        case .hydrationReminder:
            // A short, optional reminder; never imply a fixed drinking dose
            // or pause the running workout/interval timers.
            return norwegian
                ? "Husk å ta en slurk vann når det passer."
                : "Remember to take a sip of water when convenient."
        case .motivation:
            return ATHLTHAudioCoachScheduledMotivation.phrase(
                slot: motivationSlot,
                style: encouragementStyle ?? .encouragement,
                norwegian: norwegian
            )
        }
    }

    private static func remaining(_ value: Double, label: String, norwegian: Bool) -> String? {
        guard value.isFinite, (0...604_800).contains(value) else { return nil }
        let seconds = Int(value.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let tail = seconds % 60
        let duration = norwegian ? "\(minutes) minutter og \(tail) sekunder"
            : "\(minutes) minutes and \(tail) seconds"
        let prefix = hours > 0 ? (norwegian ? "\(hours) timer, " : "\(hours) hours, ") : ""
        return "\(label): \(prefix)\(duration)"
    }
}

/// Deterministic, offline motivational cues. A rule generates one short phrase
/// per distance/time milestone, without waiting for a network coach service.
enum ATHLTHAudioCoachScheduledMotivation {
    static func phrase(
        slot: Int,
        style: ATHLTHCoachEncouragementStyle,
        norwegian: Bool
    ) -> String {
        let phrases: [String]
        switch (style, norwegian) {
        case (.praise, true):
            phrases = ["Bra jobbet! Du holder det gående.", "Sterk innsats. Fortsett slik!",
                       "Dette gjør du bra. Finn din rytme."]
        case (.praise, false):
            phrases = ["Great work! Keep going.", "Strong effort. Keep it up!",
                       "You're doing well. Find your rhythm."]
        case (.push, true):
            phrases = ["Hold fokus, du har mer å gi!", "Finn rytmen og jobb videre!",
                       "Fortsett å presse kontrollert, du klarer dette!"]
        case (.push, false):
            phrases = ["Stay focused, you've got more to give!", "Find your rhythm and keep going!",
                       "Keep pushing with control. You've got this!"]
        case (.encouragement, true):
            phrases = ["Du er i gang. Ett steg om gangen!", "Hold flyten, du gjør en god jobb!",
                       "Fortsett i ditt tempo. Du har dette!"]
        case (.encouragement, false):
            phrases = ["You're moving. One step at a time!", "Keep the flow, you're doing great!",
                       "Stay with your pace. You've got this!"]
        }
        return phrases[max(slot, 0) % phrases.count]
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
        for rule in rules where (rule.scope ?? .workout) == .workout {
            // One-shot finish cues use remaining time, not elapsed-time slots.
            // A nonzero elapsed slot would otherwise suppress the first cue.
            result[rule.id] = rule.trigger == .workoutStart && elapsedSeconds > 3
                ? 1
                : rule.trigger.isPeriodic && rule.beforeEndSeconds == nil
                    ? slot(
                        for: rule,
                        distanceMeters: distanceMeters,
                        elapsedSeconds: elapsedSeconds
                    ) : 0
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
        context: ATHLTHCoachReadoutContext = .init(),
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
            context: context,
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
        context: ATHLTHCoachReadoutContext = .init(),
        lastSlots: inout [UUID: Int]
    ) -> [ATHLTHAudioCoachDueAnnouncement] {
        var messages: [ATHLTHAudioCoachDueAnnouncement] = []
        var spokenByScope: [ATHLTHAudioCoachRule.Scope: Set<ATHLTHAudioCoachRule.Metric>] = [:]
        for rule in rules.prefix(20) {
            let scope = rule.scope ?? .workout
            let distance: Double
            let elapsed: Double
            let segment: Int?
            switch scope {
            case .workout:
                distance = distanceMeters
                elapsed = elapsedSeconds
                segment = nil
            case .effort:
                guard context.isEffort, let index = context.stepIndex else { continue }
                distance = context.stepDistanceMeters
                elapsed = context.stepElapsedSeconds
                segment = index
            case .group:
                guard let index = context.groupStartIndex else { continue }
                distance = context.groupDistanceMeters
                elapsed = context.groupElapsedSeconds
                segment = index
            }
            let milestone: Int
            var alreadyConsumed = false

            if rule.trigger.isHeartRateCondition {
                // Each threshold crossing is one event, with a new delivery
                // identity on later re-entry. Invalid HR samples do not reset
                // the condition or cause spurious zone-exit announcements.
                guard let active = heartRateCondition(
                    rule, bpm: heartRateBPM, maximumBPM: maximumHeartRateBPM
                ) else { continue }
                let previousState = lastSlots[rule.id] ?? 0
                let wasActive = previousState % 2 == 1
                guard active != wasActive else { continue }
                let updatedState = previousState + 1
                lastSlots[rule.id] = updatedState
                alreadyConsumed = true
                let shouldAnnounce = rule.trigger == .zoneExit
                    ? (wasActive && !active) : (!wasActive && active)
                guard shouldAnnounce else { continue }
                milestone = (updatedState + 1) / 2
            } else if rule.trigger.needsStructuredStep ||
                      rule.trigger == .workoutStart {
                guard let occurrence = eventOccurrence(
                    rule, context: context, elapsedSeconds: elapsedSeconds
                ) else { continue }
                milestone = occurrence
            } else if let beforeEnd = rule.beforeEndSeconds {
                guard let remaining = context.workoutRemainingSeconds,
                      remaining.isFinite, remaining >= 0 else { continue }
                milestone = remaining <= Double(max(1, beforeEnd)) ? 1 : 0
            } else {
                milestone = slot(for: rule, distanceMeters: distance, elapsedSeconds: elapsed)
            }
            guard milestone > 0 else { continue }
            let current = segment.map {
                ($0 + 1) * 100_000 + min(milestone, 99_999)
            } ?? milestone
            let previous = lastSlots[rule.id] ?? 0
            if !alreadyConsumed {
                guard current > previous else { continue }
            }
            // Consume the crossed milestone even if a sensor value is missing.
            // It must not be announced much later after that value recovers.
            if !alreadyConsumed {
                lastSlots[rule.id] = current
            }
            guard rule.isEnabled else { continue }
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
                default: return true
                }
            }
            let effective = available.filter { !(spokenByScope[scope] ?? []).contains($0) }
            guard !effective.isEmpty,
                  let message = rule.phrase(
                    distanceMeters: distance,
                    elapsedSeconds: elapsed,
                    paceSecondsPerKilometer: paceSecondsPerKilometer,
                    heartRateBPM: heartRateBPM,
                    norwegian: norwegian,
                    maximumHeartRateBPM: maximumHeartRateBPM,
                    context: context,
                    excluding: Set(rule.selectedMetrics).subtracting(effective)
                  ) else { continue }
            let covered = Set(effective)
            messages.append(ATHLTHAudioCoachDueAnnouncement(
                text: message,
                metrics: scope == .workout ? covered : covered.subtracting([.distance, .elapsedTime, .averagePace]),
                milestoneKey: rule.id.uuidString + ":" +
                    String(alreadyConsumed ? milestone : current)
            ))
            spokenByScope[scope, default: []].formUnion(covered)
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

    private static func heartRateCondition(
        _ rule: ATHLTHAudioCoachRule,
        bpm: Double?,
        maximumBPM: Double?
    ) -> Bool? {
        guard let bpm, bpm.isFinite, (35...250).contains(bpm) else {
            return nil
        }
        switch rule.trigger {
        case .heartRateAbove: return bpm >= Double(rule.validatedInterval)
        case .heartRateBelow: return bpm <= Double(rule.validatedInterval)
        case .zoneEnter, .zoneExit:
            guard let zone = ATHLTHHeartRateZones.measuredZone(
                heartRateBPM: bpm, maximumBPM: maximumBPM
            ) else { return nil }
            return zone == rule.validatedInterval
        default: return nil
        }
    }

    private static func eventOccurrence(
        _ rule: ATHLTHAudioCoachRule,
        context: ATHLTHCoachReadoutContext,
        elapsedSeconds: TimeInterval
    ) -> Int? {
        if rule.trigger == .workoutStart {
            return (0...3).contains(elapsedSeconds) ? 1 : nil
        }
        guard let index = context.stepIndex, index >= 0,
              context.stepCount > index else { return nil }

        let phase = context.stepPhase
        let previous = context.previousStepPhase
        let next = context.nextStepPhase
        let nearStart = context.stepElapsedSeconds <= 4
        let remaining = context.stepRemainingSeconds
        let nearEnd = remaining.map { $0.isFinite && $0 >= 0 && $0 <= 2 } == true
        let beforeBoundary = remaining.map {
            $0.isFinite && $0 >= 0 && $0 <= Double(rule.validatedInterval)
        } == true

        // Index of the step that caused the event (1-based). All event
        // milestones are monotonic even when the plan contains many intervals.
        switch rule.trigger {
        case .stepStart:
            return nearStart ? index + 1 : nil
        case .effortStart:
            return phase == "work" && nearStart ? index + 1 : nil
        case .effortEnd:
            if phase == "work" && nearEnd { return index + 1 }
            return previous == "work" && nearStart ? index : nil
        case .recoveryStart:
            return phase == "recovery" && nearStart ? index + 1 : nil
        case .recoveryEnd:
            if phase == "recovery" && nearEnd { return index + 1 }
            return previous == "recovery" && nearStart ? index : nil
        case .activeRecoveryStart:
            return context.isActiveRecovery && nearStart ? index + 1 : nil
        case .activeRecoveryEnd:
            if context.isActiveRecovery && nearEnd { return index + 1 }
            return context.previousWasActiveRecovery && nearStart ? index : nil
        case .warmupStart:
            return phase == "warmup" && nearStart && previous != "warmup"
                ? index + 1 : nil
        case .warmupEnd:
            if phase == "warmup" && nearEnd { return index + 1 }
            return previous == "warmup" && phase != "warmup" && nearStart
                ? index : nil
        case .mainStart:
            return (phase == "work" || phase == "recovery") && nearStart &&
                (index == 0 || previous == "warmup") ? index + 1 : nil
        case .mainEnd:
            if (phase == "work" || phase == "recovery") &&
               next == "cooldown" && nearEnd { return index + 1 }
            return phase == "cooldown" && nearStart &&
                (previous == "work" || previous == "recovery") ? index : nil
        case .cooldownStart:
            return phase == "cooldown" && nearStart && previous != "cooldown"
                ? index + 1 : nil
        case .cooldownEnd:
            return phase == "cooldown" &&
                index == context.stepCount - 1 && nearEnd ? index + 1 : nil
        case .beforeNextStep:
            return next != nil && beforeBoundary ? index + 1 : nil
        case .beforeMain:
            return phase == "warmup" &&
                (next == "work" || next == "recovery") &&
                beforeBoundary ? index + 1 : nil
        case .beforeCooldown:
            return (phase == "work" || phase == "recovery") &&
                next == "cooldown" && beforeBoundary ? index + 1 : nil
        default: return nil
        }
    }

    private static func slot(
        for rule: ATHLTHAudioCoachRule,
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Int {
        guard rule.trigger.isPeriodic else { return 0 }
        let value = rule.trigger == .distance ? distanceMeters : elapsedSeconds
        guard value.isFinite, value >= 0 else { return 0 }
        return Int(min(
            floor(value / Double(rule.validatedInterval)),
            Double(Int.max / 2)
        ))
    }
}

/// Athlete-named, ordered presentation groups. A group does not change the
/// scheduling model: every linked rule stays owned by the existing Watch and
/// iPhone voice engine. Optional groups in the transfer payload preserve older
/// saved workout and profile decoding.
struct ATHLTHAudioCoachGroup: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var ruleIDs: [UUID] = []
    /// Existing smart/structured Audio Coach options belonging to this group.
    var optionIDs: [String] = []
    /// One shared trigger for commands added to this group. Optional to
    /// preserve existing profiles and Watch transfers that predate v2.2.2.
    var trigger: ATHLTHAudioCoachRule.Trigger? = nil
    var interval: Int? = nil
}

struct ATHLTHAudioCoachRuleSet: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var rules: [ATHLTHAudioCoachRule]
}


/// Planned estimates and segment measurements supplied by the recording owner.
struct ATHLTHCoachReadoutContext: Codable, Hashable {
    var stepName: String?
    var stepIndex: Int?
    var isEffort = false
    var stepElapsedSeconds: Double = 0
    var stepDistanceMeters: Double = 0
    var groupStartIndex: Int?
    var groupElapsedSeconds: Double = 0
    var groupDistanceMeters: Double = 0
    var stepRemainingSeconds: Double?
    var groupRemainingSeconds: Double?
    var workoutRemainingSeconds: Double?
    var routeRemainingMeters: Double?
    // Optional computed plan context; older Watch/iPhone snapshots decode with nil.
    var stepPhase: String?
    var previousStepPhase: String?
    var nextStepPhase: String?
    var isActiveRecovery = false
    var previousWasActiveRecovery = false
    var nextIsActiveRecovery = false
    var stepCount: Int = 0

    static func needsSegmentData(_ rules: [ATHLTHAudioCoachRule]) -> Bool {
        rules.contains { rule in
            rule.isEnabled && (rule.beforeEndSeconds != nil ||
                rule.trigger.needsStructuredStep ||
                (rule.scope ?? .workout) != .workout ||
                rule.selectedMetrics.contains { metric in
                    switch metric {
                    case .stepName, .stepRemainingTime, .groupRemainingTime,
                         .workoutRemainingTime, .estimatedFinishTime: return true
                    default: return false
                    }
                })
        }
    }

    static func make(
        plan: WatchRunningWorkoutTransfer?, index: Int?,
        elapsed: Double, distance: Double,
        recorded: [ATHLTHRecordedRunningStep], routeRemainingMeters: Double?
    ) -> Self {
        var context = Self(routeRemainingMeters: routeRemainingMeters)
        guard let steps = plan?.steps, let index, steps.indices.contains(index) else { return context }
        let step = steps[index]
        context.stepName = step.title
        context.stepIndex = index
        context.stepCount = steps.count
        context.stepPhase = step.phase
        context.previousStepPhase = index > 0 ? steps[index - 1].phase : nil
        context.nextStepPhase = index + 1 < steps.count ? steps[index + 1].phase : nil
        context.isActiveRecovery = step.phase == "recovery" && step.recoveryStyle == .activeJog
        context.previousWasActiveRecovery = index > 0 &&
            steps[index - 1].phase == "recovery" &&
            steps[index - 1].recoveryStyle == .activeJog
        context.nextIsActiveRecovery = index + 1 < steps.count &&
            steps[index + 1].phase == "recovery" &&
            steps[index + 1].recoveryStyle == .activeJog
        context.isEffort = step.phase == "work"
        context.stepElapsedSeconds = max(0, elapsed)
        context.stepDistanceMeters = max(0, distance)
        context.stepRemainingSeconds = estimate(step, elapsed: elapsed, distance: distance)
        context.workoutRemainingSeconds = total(steps[index...], elapsed: elapsed, distance: distance)

        // Use explicit drag-group IDs where present. Older sessions group the
        // contiguous work/recovery phases of the main section.
        let inGroup: (WatchRunningWorkoutStep) -> Bool = { candidate in
            if let groupID = step.coachGroupID { return candidate.coachGroupID == groupID }
            return candidate.coachGroupID == nil &&
                (candidate.phase == "work" || candidate.phase == "recovery")
        }
        if inGroup(step) {
            var first = index
            while first > 0, inGroup(steps[first - 1]) { first -= 1 }
            var end = index + 1
            while end < steps.count, inGroup(steps[end]) { end += 1 }
            context.groupStartIndex = first
            context.groupRemainingSeconds = total(steps[index..<end], elapsed: elapsed, distance: distance)
            let previous = recorded.filter { (first..<index).contains($0.index) }
            context.groupElapsedSeconds = context.stepElapsedSeconds + previous.reduce(0) { $0 + $1.activeSeconds }
            context.groupDistanceMeters = context.stepDistanceMeters + previous.reduce(0) { $0 + $1.distanceMeters }
        }
        return context
    }

    private static func total(_ steps: ArraySlice<WatchRunningWorkoutStep>, elapsed: Double, distance: Double) -> Double? {
        var sum: Double = 0
        for index in steps.indices {
            let current = index == steps.startIndex
            guard let seconds = estimate(steps[index], elapsed: current ? elapsed : 0,
                                         distance: current ? distance : 0) else { return nil }
            sum += seconds
        }
        return sum
    }

    private static func estimate(_ step: WatchRunningWorkoutStep, elapsed: Double, distance: Double) -> Double? {
        switch step.measure {
        case .time:
            guard let duration = step.durationSeconds, duration.isFinite, duration > 0 else { return nil }
            return max(0, duration - elapsed)
        case .distance:
            guard let meters = step.distanceMeters, meters.isFinite, meters > 0,
                  let pace = step.targetPaceMinSecondsPerKilometer ?? step.targetPaceMaxSecondsPerKilometer,
                  pace.isFinite, (30...3_600).contains(pace) else { return nil }
            return max(0, meters - distance) * pace / 1000
        case .open:
            return nil
        }
    }
}
