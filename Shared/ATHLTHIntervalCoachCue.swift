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
