import Foundation

/// Lightweight, offline interpretation of a runner's pre-workout coach brief.
/// Never treats a request as an AI-generated performance assessment: only
/// deterministic advice is added when a new work interval starts.
enum ATHLTHIntervalCoachCue {
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
