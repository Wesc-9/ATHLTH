import Foundation
import Supabase

enum AIProgramGenerationMode: String, Codable, CaseIterable, Identifiable {
    case generate
    case complete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: return "Generate from Goals"
        case .complete: return "Complete Program"
        }
    }

    var actionTitle: String {
        switch self {
        case .generate: return "Generate Program"
        case .complete: return "Complete Program"
        }
    }
}

struct AIProgramGoalInput: Codable, Hashable {
    let id: UUID
    let title: String
    let category: String
    let deadline: String?
    let targetSummary: String?
    let whyItMatters: String?
    let notes: String?
    let milestones: [String]

    init(goal: ATHLTHGoal) {
        id = goal.id
        title = goal.title
        category = goal.category.rawValue
        deadline = goal.deadline.map {
            ISO8601DateFormatter().string(from: $0)
        }

        if let target = goal.target {
            var parts = [
                target.metric.rawValue,
                String(target.targetValue),
                target.unit
            ]
            if let activity = target.activity {
                parts.append(activity.rawValue)
            }
            if let exerciseName = target.exerciseName,
               !exerciseName.isEmpty {
                parts.append(exerciseName)
            }
            targetSummary = parts.joined(separator: " · ")
        } else {
            targetSummary = nil
        }

        whyItMatters = goal.whyItMatters
        notes = goal.notes
        milestones = goal.milestones.map {
            "\($0.title): \($0.targetDescription)"
        }
    }
}

struct AIProgramExistingDay: Codable, Hashable {
    let weekNumber: Int
    let dayIndex: Int
    let dayTitle: String
    let existingSessions: [String]
}

struct AIProgramRequest: Encodable {
    let mode: String
    let startDate: String
    let weekCount: Int
    let sessionsPerWeek: Int
    let preferredDays: [Int]
    let sessionDurationMinutes: Int
    let userNotes: String
    let goals: [AIProgramGoalInput]
    let existingDays: [AIProgramExistingDay]
}

struct AIProgramDraft: Codable, Hashable {
    let title: String
    let summary: String
    let weeks: [AIProgramDraftWeek]

    var sessionCount: Int {
        weeks.reduce(0) { total, week in
            total + week.days.reduce(0) { $0 + $1.sessions.count }
        }
    }

    func makeTrainingPlan(
        ownerID: UUID,
        startDate: Date,
        visibility: ProfileVisibility = .privateOnly
    ) -> TrainingPlan {
        let dayTitles = [
            "Monday", "Tuesday", "Wednesday", "Thursday",
            "Friday", "Saturday", "Sunday"
        ]

        let normalizedWeeks = weeks.enumerated().map { weekOffset, week in
            let byDayIndex = Dictionary(
                uniqueKeysWithValues: week.days.map {
                    ($0.dayIndex, $0)
                }
            )

            let days = (1...7).map { dayIndex -> TrainingPlanDay in
                let generatedDay = byDayIndex[dayIndex]

                return TrainingPlanDay(
                    id: UUID(),
                    dayIndex: dayIndex,
                    title: generatedDay?.title ?? dayTitles[dayIndex - 1],
                    sessions: generatedDay?.sessions.map {
                        $0.makePlannedSession()
                    } ?? []
                )
            }

            return TrainingPlanWeek(
                id: UUID(),
                weekNumber: weekOffset + 1,
                title: week.title.isEmpty
                    ? "Week \(weekOffset + 1)"
                    : week.title,
                days: days
            )
        }

        return TrainingPlan(
            id: UUID(),
            ownerID: ownerID,
            title: title,
            summary: summary,
            visibility: visibility,
            version: 1,
            weeks: normalizedWeeks,
            tags: ["ai-generated"],
            createdAt: Date(),
            updatedAt: Date(),
            startDate: Calendar.current.startOfDay(for: startDate)
        )
    }
}

struct AIProgramDraftWeek: Codable, Hashable {
    let weekNumber: Int
    let title: String
    let days: [AIProgramDraftDay]
}

struct AIProgramDraftDay: Codable, Hashable {
    let dayIndex: Int
    let title: String
    let sessions: [AIProgramDraftSession]
}

struct AIProgramDraftSession: Codable, Hashable {
    let title: String
    let kind: String
    let durationMinutes: Int?
    let targetDistanceKilometers: Double?
    let targetPaceSecondsPerKilometer: Double?
    let notes: String?
    let exercises: [AIProgramDraftExercise]

    func makePlannedSession() -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: title,
            kind: WorkoutKind(rawValue: kind) ?? .custom,
            scheduledStart: nil,
            durationMinutes: durationMinutes,
            targetDistanceKilometers: targetDistanceKilometers,
            targetPaceSecondsPerKilometer: targetPaceSecondsPerKilometer,
            routeID: nil,
            exercises: exercises.map { $0.makePlannedExercise() },
            notes: notes
        )
    }
}

struct AIProgramDraftExercise: Codable, Hashable {
    let name: String
    let sets: Int
    let reps: Int?
    let targetRPE: Double?
    let restSeconds: Int?
    let notes: String?

    func makePlannedExercise() -> PlannedExercise {
        PlannedExercise(
            id: UUID(),
            exerciseID: nil,
            embeddedExercise: ExerciseSnapshot(
                name: name,
                instructions: [],
                primaryMuscles: [],
                equipment: [],
                imageURL: nil
            ),
            sets: max(sets, 1),
            reps: reps,
            targetWeightKilograms: nil,
            targetRPE: targetRPE,
            restSeconds: restSeconds,
            notes: notes
        )
    }
}

final class AIProgramService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    func generate(_ request: AIProgramRequest) async throws -> AIProgramDraft {
        try await client.functions.invoke(
            "generate-training-program",
            options: FunctionInvokeOptions(body: request)
        )
    }
}

enum AIProgramError: LocalizedError {
    case noGoals
    case unavailable

    var errorDescription: String? {
        switch self {
        case .noGoals:
            return "Choose at least one goal before generating a program."
        case .unavailable:
            return "AI program generation is temporarily unavailable."
        }
    }
}
