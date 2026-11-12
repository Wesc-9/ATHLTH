import Foundation

enum ATHLTHIntervalHalfwayMessage: String, CaseIterable, Codable, Hashable {
    case motivation, praise, heartRateZone, custom
}

enum ATHLTHRunningRecoveryStyle: String, CaseIterable, Codable, Hashable {
    case passive, activeJog
}

struct ATHLTHIntervalSpokenReport: Codable, Hashable {
    var effortPace: Bool
    var groupDistance: Bool
}

struct ATHLTHRunningCoachReport: Codable, Hashable {
    var stepIndex: Int
    var capturedAt: Date
    var paceSecondsPerKilometer: Double?
    var groupDistanceMeters: Double?

    static func make(
        steps: [WatchRunningWorkoutStep], finishedIndex: Int,
        recorded: [ATHLTHRecordedRunningStep], now: Date = .now
    ) -> ATHLTHRunningCoachReport? {
        guard steps.indices.contains(finishedIndex),
              let groupID = steps[finishedIndex].coachGroupID,
              let options = steps[finishedIndex].spokenReport else { return nil }
        let finished = steps[finishedIndex]
        let measurement = recorded.last { $0.index == finishedIndex }
        let pace: Double? = if options.effortPace, finished.phase == "work",
                               let measurement, measurement.distanceMeters > 0,
                               measurement.activeSeconds > 0 {
            measurement.activeSeconds / measurement.distanceMeters * 1000
        } else { nil }

        var groupDistance: Double?
        let nextIndex = finishedIndex + 1
        if options.groupDistance,
           !steps.indices.contains(nextIndex) || steps[nextIndex].coachGroupID != groupID {
            var first = finishedIndex
            while first > 0, steps[first - 1].coachGroupID == groupID { first -= 1 }
            groupDistance = recorded.filter {
                (first...finishedIndex).contains($0.index) && steps[$0.index].phase == "work"
            }.reduce(0) { $0 + max(0, $1.distanceMeters) }
        }
        guard pace != nil || (groupDistance ?? 0) > 0 else { return nil }
        return ATHLTHRunningCoachReport(stepIndex: finishedIndex, capturedAt: now,
                                        paceSecondsPerKilometer: pace,
                                        groupDistanceMeters: groupDistance)
    }

    var event: ATHLTHCoachEvent {
        ATHLTHCoachEvent(kind: .runningStep, key: "effort-report:\(stepIndex)",
                        priority: .structuredStep, createdAt: capturedAt, validFor: 8)
    }

    func text(norwegian: Bool) -> String {
        var parts: [String] = []
        if let pace = paceSecondsPerKilometer, pace.isFinite, (30...3_600).contains(pace) {
            let seconds = Int(pace.rounded())
            parts.append(norwegian
                ? "Tempo på draget: \(seconds / 60) minutter og \(seconds % 60) sekunder per kilometer."
                : "Effort pace: \(seconds / 60) minutes and \(seconds % 60) seconds per kilometer.")
        }
        if let meters = groupDistanceMeters, meters.isFinite, meters > 0 {
            let distance = (meters / 1000).formatted(.number.precision(.fractionLength(2)))
            parts.append(norwegian
                ? "Gruppen er ferdig. \(distance) kilometer på dragene."
                : "Group complete. \(distance) kilometers across the efforts.")
        }
        return parts.joined(separator: " ")
    }
}

struct ATHLTHIntervalMotivationSettings: Codable, Hashable {
    var halfway: Bool
    var finalSeconds: Int?
    var halfwayMessage: ATHLTHIntervalHalfwayMessage? = nil
    var customHalfwayText: String? = nil
}

/// Lightweight, offline interpretation of a runner's pre-workout coach brief.
/// Never treats a request as an AI-generated performance assessment: only
/// deterministic advice is added when a new work interval starts.
enum ATHLTHIntervalCoachCue {
    struct Motivation {
        let key: String
        let text: String
    }

    static func motivation(
        _ settings: ATHLTHIntervalMotivationSettings?,
        phase: String?, elapsed: TimeInterval, remaining: TimeInterval,
        norwegian: Bool, measuredZone: Int? = nil
    ) -> Motivation? {
        guard phase == "work", let settings,
              elapsed.isFinite, remaining.isFinite, elapsed >= 0, remaining > 0
        else { return nil }
        let duration = elapsed + remaining
        let window: TimeInterval = 2
        if let seconds = settings.finalSeconds, (5...60).contains(seconds),
           Double(seconds) < duration, remaining <= Double(seconds),
           remaining > Double(seconds) - window {
            let left = Int(ceil(remaining))
            return Motivation(key: "finish", text: norwegian
                ? "\(left) sekunder igjen. Hold trykket helt inn!"
                : "\(left) seconds left. Keep pushing to the finish!")
        }
        if settings.halfway, duration >= 10,
           elapsed >= duration / 2, elapsed < duration / 2 + window {
            let text: String
            switch settings.halfwayMessage ?? .motivation {
            case .motivation:
                text = norwegian ? "Halvveis. Hold rytmen, du klarer dette!"
                    : "Halfway. Stay smooth, you've got this!"
            case .praise:
                text = norwegian ? "Bra jobbet, du er halvveis!" : "Nice work, you're halfway!"
            case .heartRateZone:
                text = measuredZone.map { zone in
                    norwegian ? "Halvveis. Du er i pulssone \(zone)." : "Halfway. You're in heart rate zone \(zone)."
                } ?? (norwegian ? "Halvveis. Pulssone er ikke tilgjengelig."
                      : "Halfway. Heart rate zone is unavailable.")
            case .custom:
                let message = settings.customHalfwayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !message.isEmpty else { return nil }
                text = String(message.prefix(120))
            }
            return Motivation(key: "halfway", text: text)
        }
        return nil
    }

    static func phrase(
        for step: WatchRunningWorkoutStep,
        norwegian: Bool
    ) -> String? {
        phrase(brief: step.coachBrief, phase: step.phase,
               zone: step.targetHeartRateZone, norwegian: norwegian)
    }

    static func phrase(
        brief: String?, phase: String?, zone: Int?, norwegian: Bool
    ) -> String? {
        guard phase == "work",
              let brief = brief?.lowercased(),
              !brief.isEmpty else { return nil }

        var cues: [String] = []
        if brief.contains("motiv") || brief.contains("oppmuntr") ||
            brief.contains("push me") || brief.contains("encourag") {
            cues.append(norwegian
                ? "Du er i gang. Hold rytmen, du klarer dette."
                : "You're in it. Stay smooth and keep going.")
        }
        if brief.contains("tempo") || brief.contains("pace") ||
            brief.contains("fart") || brief.contains("speed") {
            cues.append(norwegian
                ? "Finn måltempoet, og prøv å holde et jevnt drag."
                : "Find your target pace and keep the effort steady.")
        }
        if (brief.contains("puls") || brief.contains("heart") ||
            brief.contains("sone") || brief.contains("zone")),
           let zone {
            cues.append(norwegian
                ? "Følg med på pulsen. Målet er sone \(zone)."
                : "Watch your heart rate. Your target is zone \(zone).")
        }
        if brief.contains("rolig") || brief.contains("kontroll") ||
            brief.contains("relax") || brief.contains("techni") {
            cues.append(norwegian
                ? "Slapp av i skuldrene og løp kontrollert."
                : "Relax your shoulders and run under control.")
        }
        return cues.isEmpty ? nil : cues.prefix(2).joined(separator: " ")
    }

    static func appendToStepAnnouncement(
        _ announcement: String,
        step: WatchRunningWorkoutStep,
        norwegian: Bool
    ) -> String {
        guard let cue = phrase(for: step, norwegian: norwegian) else {
            return announcement
        }
        return announcement + " " + cue
    }
}


/// What Audio Coach says after a timed countdown reaches the real boundary.
/// Optional fields on saved workouts keep old configurations decoding.
enum ATHLTHCoachCountdownAfter: String, Codable, CaseIterable, Identifiable {
    case numbersOnly
    case shortAlert
    case nextStep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .numbersOnly:
            return ATHLTHLocalization.choose(english: "Numbers only", norwegian: "Bare tallene")
        case .shortAlert:
            return ATHLTHLocalization.choose(english: "Short announcement", norwegian: "Kort beskjed")
        case .nextStep:
            return ATHLTHLocalization.choose(english: "Announce what is next", norwegian: "Fortell hva som er neste")
        }
    }
}

/// One-second deadlines always win over routine coach messages. A delayed tick
/// SKIPS a number instead of speaking a stale one; no countdown is inferred
/// from a distance-only or open-ended target.
enum ATHLTHCoachSecondCountdown {
    static let offeredLengths = [3, 5, 10, 15, 20, 30]

    static func dueNumber(
        remaining: TimeInterval,
        length: Int?,
        previousNumber: Int?
    ) -> Int? {
        guard let length, (1...30).contains(length),
              remaining.isFinite, remaining > 0 else { return nil }
        let number = Int(ceil(remaining))
        guard number >= 1, number <= length else { return nil }
        if let previousNumber, number >= previousNumber { return nil }
        return number
    }
}


/// Running/walking recovery speech is configured solely in Audio Coach.
/// An explicit numbers-only selection suppresses the legacy step announcement.
enum ATHLTHCoachRecoveryBoundary {
    static func afterAction(
        finishedPhase: String?,
        nextPhase: String?,
        configuration: WatchAudioCoachConfiguration
    ) -> ATHLTHCoachCountdownAfter? {
        if finishedPhase == "work", nextPhase == "recovery",
           configuration.resolvedIntervalCountdownToRecovery != nil {
            return configuration.resolvedIntervalAfterCountdownToRecovery
        }
        if finishedPhase == "recovery",
           configuration.resolvedIntervalCountdownFromRecovery != nil {
            return configuration.resolvedIntervalAfterCountdownFromRecovery
        }
        return nil
    }

    static func shortMessage(
        finishedPhase: String?,
        norwegian: Bool
    ) -> String {
        if finishedPhase == "work" {
            return norwegian ? "Pausen starter." : "Recovery starts."
        }
        return norwegian ? "Pausen er ferdig." : "Recovery complete."
    }
}


/// A named, reusable Audio Coach countdown, independent of the workout editor.
/// The 'starts' boundary is counted during the preceding timed unit; the start
/// of the recording itself has no preceding timer and is deliberately excluded.
struct ATHLTHCoachBoundaryCountdownRule: Codable, Hashable, Identifiable {
    enum Scope: String, Codable, CaseIterable, Identifiable {
        case step, section, group, plannedWorkout
        var id: String { rawValue }
        var title: String {
            switch self {
            case .step: return ATHLTHLocalization.choose(english: "Each step / effort", norwegian: "Hvert drag / delsteg")
            case .section: return ATHLTHLocalization.choose(english: "Workout section", norwegian: "Deløkt")
            case .group: return ATHLTHLocalization.choose(english: "Interval group", norwegian: "Draggruppe")
            case .plannedWorkout: return ATHLTHLocalization.choose(english: "Whole planned workout", norwegian: "Hele planlagte økten")
            }
        }
    }

    enum Boundary: String, Codable, CaseIterable, Identifiable {
        case starts, ends
        var id: String { rawValue }
        var title: String {
            switch self {
            case .starts: return ATHLTHLocalization.choose(english: "Before it starts", norwegian: "Før den starter")
            case .ends: return ATHLTHLocalization.choose(english: "Before it ends", norwegian: "Før den avsluttes")
            }
        }
    }

    var id = UUID()
    var scope: Scope = .step
    var boundary: Boundary = .ends
    var seconds = 10
    var after: ATHLTHCoachCountdownAfter = .numbersOnly
    /// nil = every section; warmup/main/cooldown limit a rule to that part.
    var sectionFilter: String? = nil
    var enabled = true

    var resolvedSeconds: Int? {
        guard enabled, (1...30).contains(seconds) else { return nil }
        return seconds
    }
}

/// Pure boundary resolver: one deadline gets one set of spoken numbers.
/// Longest selected countdown wins; on a tie prefer the more specific rule.
/// Without an actual timed deadline callers must never ask for spoken numbers.
enum ATHLTHCoachBoundaryCountdown {
    /// Strength: only an actual timed set can trigger an ending cue. Ending
    /// a time target does NOT mark the set as completed by the athlete.
    static func forStrengthTimedSet(
        _ rules: [ATHLTHCoachBoundaryCountdownRule],
        exerciseIndex: Int, exerciseCount: Int,
        setIndex: Int, setCount: Int
    ) -> ATHLTHCoachBoundaryCountdownRule? {
        guard exerciseIndex >= 0, exerciseIndex < exerciseCount,
              setIndex >= 0, setIndex < setCount else { return nil }
        let lastSet = setIndex == setCount - 1
        let lastExercise = exerciseIndex == exerciseCount - 1
        return best(rules.filter { rule in
            guard rule.resolvedSeconds != nil, rule.boundary == .ends else { return false }
            switch rule.scope {
            case .step: return true
            case .section: return lastSet
            case .group: return false // requires a real timed group anchor
            case .plannedWorkout: return lastSet && lastExercise
            }
        })
    }

    /// Strength: a finite rest deadline is also a known start for the next
    /// set, or for the next exercise if the current one is complete.
    static func forStrengthAfterRest(
        _ rules: [ATHLTHCoachBoundaryCountdownRule],
        nextExercise: Bool,
        nextGroup: Bool = false
    ) -> ATHLTHCoachBoundaryCountdownRule? {
        best(rules.filter { rule in
            guard rule.resolvedSeconds != nil, rule.boundary == .starts else { return false }
            switch rule.scope {
            case .step: return true
            case .section: return nextExercise
            case .group: return nextGroup
            case .plannedWorkout: return false
            }
        })
    }

    /// A time-capped group can have a precise spoken ending even when the
    /// individual repetitions inside it are open-ended.
    static func forStrengthTimedGroup(
        _ rules: [ATHLTHCoachBoundaryCountdownRule]
    ) -> ATHLTHCoachBoundaryCountdownRule? {
        best(rules.filter {
            $0.scope == .group && $0.boundary == .ends &&
                $0.resolvedSeconds != nil
        })
    }

    private static func best(
        _ rules: [ATHLTHCoachBoundaryCountdownRule]
    ) -> ATHLTHCoachBoundaryCountdownRule? {
        let rank: [ATHLTHCoachBoundaryCountdownRule.Scope: Int] = [
            .step: 0, .section: 1, .group: 2, .plannedWorkout: 3
        ]
        return rules.sorted {
            if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
            if rank[$0.scope] != rank[$1.scope] {
                return (rank[$0.scope] ?? 0) > (rank[$1.scope] ?? 0)
            }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }

    static func forRunningStep(
        _ steps: [WatchRunningWorkoutStep],
        at index: Int,
        configuration: WatchAudioCoachConfiguration
    ) -> ATHLTHCoachBoundaryCountdownRule? {
        guard steps.indices.contains(index) else { return nil }
        return chosenRule(
            configuration.effectiveBoundaryCountdownRules,
            currentPhase: steps[index].phase,
            nextPhase: steps.indices.contains(index + 1) ? steps[index + 1].phase : nil,
            currentGroupID: steps[index].coachGroupID,
            nextGroupID: steps.indices.contains(index + 1) ? steps[index + 1].coachGroupID : nil,
            stepIndex: index,
            stepCount: steps.count
        )
    }

    static func shortMessage(
        for rule: ATHLTHCoachBoundaryCountdownRule,
        norwegian: Bool
    ) -> String {
        let started = rule.boundary == .starts
        switch rule.scope {
        case .step:
            return norwegian
                ? (started ? "Neste drag starter." : "Delsteget er ferdig.")
                : (started ? "Next effort starts." : "Step completed.")
        case .section:
            return norwegian
                ? (started ? "Neste deløkt starter." : "Deløkten er ferdig.")
                : (started ? "Next section starts." : "Section complete.")
        case .group:
            return norwegian
                ? (started ? "Neste gruppe starter." : "Gruppen er ferdig.")
                : (started ? "Next group starts." : "Group complete.")
        case .plannedWorkout:
            return norwegian ? "Den planlagte økten er ferdig." : "Planned workout complete."
        }
    }

    static func section(for phase: String?) -> String? {
        switch phase {
        case "warmup": return "warmup"
        case "cooldown": return "cooldown"
        case "work", "recovery", "main": return "main"
        default: return phase
        }
    }

    static func chosenRule(
        _ rules: [ATHLTHCoachBoundaryCountdownRule],
        currentPhase: String?,
        nextPhase: String?,
        currentGroupID: UUID?,
        nextGroupID: UUID?,
        stepIndex: Int,
        stepCount: Int
    ) -> ATHLTHCoachBoundaryCountdownRule? {
        guard stepIndex >= 0, stepIndex < stepCount else { return nil }
        let currentSection = section(for: currentPhase)
        let nextSection = section(for: nextPhase)
        let isLast = stepIndex == stepCount - 1
        let isSectionBoundary = isLast || currentSection != nextSection
        // Legacy plans with no group IDs have one contiguous main section.
        let currentInGroup = currentGroupID != nil || currentSection == "main"
        let nextInGroup = nextGroupID != nil || nextSection == "main"
        let changesGroup = currentGroupID != nil || nextGroupID != nil
            ? currentGroupID != nextGroupID
            : currentSection != nextSection
        let eligible = rules.filter { rule in
            guard rule.resolvedSeconds != nil else { return false }
            let targetSection = rule.boundary == .starts ? nextSection : currentSection
            if let filter = rule.sectionFilter, rule.scope == .section,
               filter != targetSection { return false }
            switch (rule.scope, rule.boundary) {
            case (.step, .ends): return true
            case (.step, .starts): return !isLast
            case (.section, .ends): return isSectionBoundary
            case (.section, .starts): return !isLast && isSectionBoundary
            case (.group, .ends): return currentInGroup && changesGroup
            case (.group, .starts): return !isLast && nextInGroup && changesGroup
            case (.plannedWorkout, .ends): return isLast
            case (.plannedWorkout, .starts): return false
            }
        }
        let rank: [ATHLTHCoachBoundaryCountdownRule.Scope: Int] = [
            .step: 0, .section: 1, .group: 2, .plannedWorkout: 3
        ]
        return eligible.sorted {
            if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
            if rank[$0.scope] != rank[$1.scope] {
                return (rank[$0.scope] ?? 0) > (rank[$1.scope] ?? 0)
            }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
}
