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
        let draft: CoachPlanAdaptationDraft = try await client.functions.invoke(
            "generate-plan-adaptation",
            options: FunctionInvokeOptions(body: request)
        )

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let changes = draft.changes.compactMap { change -> CoachPlanChange? in
            guard let kind = CoachPlanChangeKind(rawValue: change.kind) else {
                return nil
            }

            return CoachPlanChange(
                kind: kind,
                sessionID: change.sessionID,
                sourceDate: change.sourceDate.flatMap {
                    dayFormatter.date(from: $0)
                },
                targetDate: change.targetDate.flatMap {
                    dayFormatter.date(from: $0)
                },
                title: change.title,
                summary: change.summary,
                reason: change.reason,
                replacementTitle: change.replacementTitle,
                durationMinutes: change.durationMinutes,
                intensityNote: change.intensityNote
            )
        }

        return CoachPlanChangeProposal(
            planID: request.planID,
            planVersion: request.planVersion,
            headline: draft.headline,
            rationale: draft.rationale,
            changes: changes
        )
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
