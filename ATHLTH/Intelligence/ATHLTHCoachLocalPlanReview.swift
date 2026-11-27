import Foundation

struct ATHLTHCoachLocalPlanReview: Codable, Hashable, Identifiable {
    let id: UUID
    let planID: UUID
    let version: Int
    let title: String

    init(plan: TrainingPlan) {
        id = UUID()
        planID = plan.id
        version = plan.version
        title = plan.title
    }

    func matches(_ plan: TrainingPlan) -> Bool {
        plan.id == planID && plan.version == version
    }

    static func isReviewRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        let requests = ["vurder", "gjennomgå", "gjennomgang", "evaluer", "review", "analyse", "analyser", "optimaliser", "optimize"]
        let plans = ["planen", "treningsplan", "training plan", "my plan", "active plan"]
        return requests.contains { text.contains($0) } && plans.contains { text.contains($0) }
    }

    static func isMoveRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        return ["flytt", "utsett", "move ", "reschedule", "postpone"].contains { text.contains($0) } &&
            ["økt", "plan", "intervall", "workout", "session", "tomorrow", "morgen"].contains { text.contains($0) }
    }
}

enum ATHLTHCoachLocalGoalReview {
    static func isRequest(_ source: String) -> Bool {
        let text = source.lowercased()
        let goal = ["mål", "goal"].contains { text.contains($0) }
        let check = ["hvordan", "fremgang", "framgang", "progresjon", "vis ", "status", "oppfølging",
                     "progress", "how", "review", "check"].contains { text.contains($0) }
        return goal && check && !ATHLTHCoachChatPlanIntake.isCreationRequest(source) &&
            !ATHLTHCoachLocalPlanReview.isReviewRequest(source)
    }

    static func render(goals: [ATHLTHGoal], profile: ATHLTHTrainingProfile, norwegian: Bool,
                       now: Date = Date(), calendar: Calendar = .current) -> String {
        func tr(_ en: String, _ no: String) -> String { norwegian ? no : en }
        let active = goals.filter { $0.status == .active }.sorted {
            if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
            return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
        }
        guard !active.isEmpty else {
            return tr("You have no active goals. Create a goal in ATHLTH to track it.",
                      "Du har ingen aktive mål. Opprett et mål i ATHLTH for å følge utviklingen.")
        }
        var lines = [tr("Your active goals · \(active.count)", "Dine aktive mål · \(active.count)")]
        for goal in active.prefix(8) {
            var row = goal.title
            // Only display evidence-based progress where a known mechanism
            // exists. Zero milestones alone is not evidence of zero progress.
            if goal.bodyMeasurementGoal != nil {
                let progress = ATHLTHGoalProgressPolicy.progress(for: goal, profile: profile)
                if progress.isFinite {
                    row += " · \(Int((min(1, max(0, progress)) * 100).rounded()))%"
                }
            } else if !goal.milestones.isEmpty {
                row += " · \(goal.completedMilestones)/\(goal.milestones.count) " + tr("milestones", "delmål")
            } else {
                row += " · " + tr("No milestone progress available", "Ingen delmålsstatus tilgjengelig")
            }
            if let deadline = goal.deadline {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                    to: calendar.startOfDay(for: deadline)).day ?? 0
                row += " · " + (days < 0 ? tr("Deadline passed", "Fristen er passert") :
                    days == 0 ? tr("Deadline today", "Frist i dag") :
                    tr("\(days) days left", "\(days) dager igjen"))
            }
            lines.append(row)
        }
        if active.count > 8 { lines.append(tr("Showing 8 active goals.", "Viser 8 aktive mål.")) }
        lines.append(tr("Review your goals and choose realistic next milestones. Nothing has been changed.",
                        "Gjennomgå målene og velg realistiske neste delmål. Ingenting er endret."))
        return lines.joined(separator: "\n")
    }
}
