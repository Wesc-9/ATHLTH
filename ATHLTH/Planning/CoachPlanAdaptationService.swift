import Foundation
import Supabase

struct CoachPlanAdaptationDayInput: Encodable {
    let weekNumber: Int
    let dayIndex: Int
    let date: String?
    let title: String
    let sessions: [CoachPlanAdaptationSessionInput]
}

struct CoachPlanAdaptationSessionInput: Encodable {
    let id: UUID
    let title: String
    let kind: String
    let durationMinutes: Int?
    let scheduledStart: String?
    let notes: String?
}

struct CoachPlanAdaptationRequest: Encodable {
    let planID: UUID
    let planVersion: Int
    let planTitle: String
    let planStartDate: String?
    let planEndDate: String?
    let today: String
    let days: [CoachPlanAdaptationDayInput]
    let goals: [AIProgramGoalInput]
    let recentTraining: [String]
    let userNotes: String
}

private struct CoachPlanAdaptationDraft: Decodable {
    let headline: String
    let rationale: String
    let changes: [CoachPlanAdaptationDraftChange]
}

private struct CoachPlanAdaptationDraftChange: Decodable {
    let kind: String
    let sessionID: UUID?
    let sourceDate: String?
    let targetDate: String?
    let title: String
    let summary: String
    let reason: String
    let replacementTitle: String?
    let durationMinutes: Int?
    let intensityNote: String?
}

@MainActor
final class CoachPlanAdaptationService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func generate(
        request: CoachPlanAdaptationRequest
    ) async throws -> CoachPlanChangeProposal {
        // Restrict edits to future, existing sessions. Do not generate a
        // replacement exercise or change training intensity from free text.
        let notes = request.userNotes.lowercased()
        let asksForLess = ["shorter", "reduce", "less", "easier", "lighter",
                           "kortere", "reduser", "roligere", "lettere", "mindre"]
            .contains { notes.contains($0) }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let future = request.days.filter { ($0.date ?? "") >= request.today }.sorted {
            ($0.date ?? "") < ($1.date ?? "")
        }
        var candidates: [CoachPlanChange] = []
        if asksForLess {
            for day in future.prefix(7) {
                for workout in day.sessions {
                    guard let duration = workout.durationMinutes, duration >= 20 else { continue }
                    let shortened = max(15, Int(Double(duration) * 0.8))
                    candidates.append(CoachPlanChange(
                        kind: .adjustDuration, sessionID: workout.id,
                        sourceDate: day.date.flatMap { dayFormatter.date(from: $0) },
                        title: workout.title,
                        summary: ATHLTHLocalization.choose(
                            english: "Review a shorter scheduled duration: \(shortened) min",
                            norwegian: "Vurder kortere planlagt varighet: \(shortened) min"),
                        reason: ATHLTHLocalization.choose(
                            english: "Requested a lighter or shorter schedule. Review the actual exercise prescription separately.",
                            norwegian: "Du ba om en lettere eller kortere plan. Kontroller selve øktinnholdet separat."),
                        durationMinutes: shortened))
                }
            }
        }
        candidates = Array(candidates.prefix(24))
        let labels = candidates.map { $0.title + " · " + $0.summary }
        let ranked = try await ATHLTHIntelligenceEngine.localPlanningOrder(options: labels, context: request.userNotes)
        let chosen = (ranked ?? Array(candidates.indices)).first.map { [candidates[$0]] } ?? []
        return CoachPlanChangeProposal(
            planID: request.planID, planVersion: request.planVersion,
            headline: ATHLTHLocalization.choose(english: "Local plan review", norwegian: "Lokal plangjennomgang"),
            rationale: ATHLTHLocalization.choose(
                english: "Only existing workouts are eligible. Review any change before accepting.",
                norwegian: "Kun eksisterende økter kan endres. Kontroller endringen før du godkjenner."),
            changes: chosen)
    }

    static func makeRequest(
        plan: TrainingPlan,
        goals: [ATHLTHGoal],
        recentTraining: [String],
        userNotes: String
    ) -> CoachPlanAdaptationRequest {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let days = plan.weeks.flatMap { week in
            week.days.map { day in
                let date: Date?
                if let start = plan.startDate {
                    let offset =
                        max(week.weekNumber - 1, 0) * 7 +
                        max(day.dayIndex - 1, 0)
                    date = calendar.date(
                        byAdding: .day,
                        value: offset,
                        to: calendar.startOfDay(for: start)
                    )
                } else {
                    date = nil
                }

                return CoachPlanAdaptationDayInput(
                    weekNumber: week.weekNumber,
                    dayIndex: day.dayIndex,
                    date: date.map { dayFormatter.string(from: $0) },
                    title: day.title,
                    sessions: day.sessions.map { session in
                        CoachPlanAdaptationSessionInput(
                            id: session.id,
                            title: session.title,
                            kind: session.kind.rawValue,
                            durationMinutes: session.durationMinutes,
                            scheduledStart: session.scheduledStart.map {
                                ISO8601DateFormatter().string(from: $0)
                            },
                            notes: session.notes
                        )
                    }
                )
            }
        }

        return CoachPlanAdaptationRequest(
            planID: plan.id,
            planVersion: plan.version,
            planTitle: plan.title,
            planStartDate: plan.startDate.map {
                dayFormatter.string(from: $0)
            },
            planEndDate: plan.endDate.map {
                dayFormatter.string(from: $0)
            },
            today: dayFormatter.string(from: Date()),
            days: days,
            goals: goals.prefix(8).map(AIProgramGoalInput.init),
            recentTraining: Array(recentTraining.prefix(20)),
            userNotes: String(userNotes.prefix(1200))
        )
    }
}

enum CoachPlanAdaptationError: LocalizedError {
    case noActivePlan
    case noChanges

    var errorDescription: String? {
        switch self {
        case .noActivePlan:
            return "You need an active training plan before Coach can adapt it."
        case .noChanges:
            return "Coach did not find a useful plan change right now."
        }
    }
}
