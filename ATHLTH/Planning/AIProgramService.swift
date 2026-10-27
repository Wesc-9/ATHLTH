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

    init(focus: TrainingFocus) {
        id = UUID()
        title = "Build a sustainable \(focus.title.lowercased()) routine"
        category = "generalFitness"
        deadline = nil
        targetSummary = nil
        whyItMatters = nil
        notes = "Use the confirmed experience, equipment and availability. No performance target has been selected."
        milestones = []
    }

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
    let aiChoosesFrequency: Bool
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

        // AI draft day indices are selected calendar weekdays (Mon=1),
        // whereas persisted plan indices are relative to the start date.
        // The same translation is already used by the manual plan builder.
        let normalizedWeeks = weeks.enumerated().map { weekOffset, week in
            let byDayIndex = Dictionary(
                uniqueKeysWithValues: week.days.map { day in
                    (
                        ATHLTHTrainingPlanSchedule.relativeDayIndex(
                            forCalendarWeekday: day.dayIndex,
                            planStart: startDate
                        ),
                        day
                    )
                }
            )

            let days = (1...7).map { dayIndex -> TrainingPlanDay in
                let generatedDay = byDayIndex[dayIndex]
                let weekday = ATHLTHTrainingPlanSchedule.calendarWeekdayIndex(
                    forRelativeDayIndex: dayIndex, planStart: startDate
                )

                return TrainingPlanDay(
                    id: UUID(),
                    dayIndex: dayIndex,
                    title: generatedDay?.title ?? dayTitles[weekday - 1],
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

extension AIProgramDraft {
    /// An AI proposal must show the same user-authored sessions that will be
    /// saved. This is only a readable preview projection: structured blocks
    /// themselves are applied to the TrainingPlan before persistence.
    /// The weekly structure was selected *before* opening Coach. Retain it
    /// even when the model returns a different title/activity or extra slots.
    /// For a matching activity, preserve AI-generated exercise suggestions.
    /// For a mismatched activity, never attach incompatible strength exercises
    /// to an athlete-selected run (or vice versa).
    func honoringWeekdayChoices(
        _ choices: [Int: ATHLTHPlanDayPreference],
        protectedDays: Set<Int> = []
    ) -> AIProgramDraft {
        guard !choices.isEmpty else { return self }
        let updated = weeks.map { week -> AIProgramDraftWeek in
            let days = week.days.map { day -> AIProgramDraftDay in
                guard let preference = choices[day.dayIndex],
                      !protectedDays.contains(day.dayIndex) else {
                    return day
                }
                let proposed = day.sessions.first
                let sameKind = proposed?.kind == preference.kind.rawValue
                let matched = AIProgramDraftSession(
                    title: preference.title,
                    kind: preference.kind.rawValue,
                    durationMinutes: min(max(preference.durationMinutes, 5), 240),
                    targetDistanceKilometers: sameKind
                        ? proposed?.targetDistanceKilometers : nil,
                    targetPaceSecondsPerKilometer: sameKind
                        ? proposed?.targetPaceSecondsPerKilometer : nil,
                    notes: sameKind ? proposed?.notes : nil,
                    exercises: sameKind ? (proposed?.exercises ?? []) : []
                )
                return AIProgramDraftDay(
                    dayIndex: day.dayIndex, title: day.title,
                    sessions: [matched]
                )
            }
            return AIProgramDraftWeek(
                weekNumber: week.weekNumber, title: week.title, days: days
            )
        }
        return AIProgramDraft(title: title, summary: summary, weeks: updated)
    }

    func displayingLockedWorkouts(
        _ locked: [Int: ATHLTHPlanStructuredWorkoutBlueprint]
    ) -> AIProgramDraft {
        guard !locked.isEmpty else { return self }
        let updated = weeks.map { week -> AIProgramDraftWeek in
            let days = week.days.map { day -> AIProgramDraftDay in
                guard let workout = locked[day.dayIndex], workout.isValid else {
                    return day
                }
                let planned = AIProgramDraftSession(
                    title: workout.title,
                    kind: workout.kind.rawValue,
                    durationMinutes: workout.durationMinutes,
                    targetDistanceKilometers: nil,
                    targetPaceSecondsPerKilometer: nil,
                    notes: ATHLTHLocalization.choose(
                        english: "Detailed ATHLTH Studio workout is kept when saving.",
                        norwegian: "Detaljert ATHLTH Studio-økt beholdes ved lagring."
                    ),
                    exercises: []
                )
                return AIProgramDraftDay(
                    dayIndex: day.dayIndex,
                    title: day.title,
                    sessions: [planned]
                )
            }
            return AIProgramDraftWeek(
                weekNumber: week.weekNumber,
                title: week.title,
                days: days
            )
        }
        return AIProgramDraft(title: title, summary: summary, weeks: updated)
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

@MainActor
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
