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
    /// Explicit permission for Coach to vary each session's length.
    var aiChoosesDuration: Bool = false
    /// If true, Coach varies the weekly workout mix and progression.
    var varyWeeks: Bool = false
    /// Only the language code is sent; no locale-specific personal data.
    var language: String = Locale.current.language.languageCode?.identifier ?? "no"
    let userNotes: String
    // Defaults preserve existing non-injury plan-generation call sites.
    var injurySafetyNotes: String? = nil
    var excludedMovements: [String]? = nil
    /// Non-sensitive equipment exclusions must reach the generator
    /// independently of the truncated notes field.
    var unavailableEquipment: [String]? = nil
    // Optional, explicitly consented training-derived signals. Nothing is uploaded
    // until Coach History access is enabled by the athlete.
    var coachStrengthContext: ATHLTHCoachStrengthIntelligence.Snapshot? = nil
    /// Only public, bundled ATHLTH exercise names may be supplied. Never send
    /// account-owned/private exercise names without the user's permission.
    var allowedExerciseNames: [String]? = nil
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
        visibility: ProfileVisibility = .privateOnly,
        exerciseLibrary: [ExerciseLibraryEntry] = []
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
                        $0.makePlannedSession(exerciseLibrary: exerciseLibrary)
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
                    exercises: sameKind ? (proposed?.exercises ?? []) : [],
                    blocks: sameKind ? proposed?.blocks : nil
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
    /// Optional for older deployed Coach functions and stored drafts.
    var blocks: [AIProgramDraftStep]? = nil
    /// Full ATHLTH engine recipe saved by the shared Basic/Advanced editor.
    /// The AI proposal is still private until the whole plan is approved.
    /// Keeping the real PlannedSession preserves groups, sets, audio, route
    /// and exercise IDs that AIProgramDraftStep cannot represent losslessly.
    var authoredWorkout: PlannedSession? = nil

    var visibleExerciseCount: Int {
        if let authoredWorkout {
            let blocks = authoredWorkout.resolvedWorkoutBlocks
            return Set(blocks.filter { $0.kind == .exercise }
                .map { $0.exerciseID?.uuidString ??
                    ATHLTHExerciseReferenceResolver.key($0.title) }).count
        }
        return exercises.count
    }

    func makePlannedSession(
        exerciseLibrary: [ExerciseLibraryEntry] = []
    ) -> PlannedSession {
        // User-authored Basic/Advanced edits are already a validated ATHLTH
        // workout. Do not downgrade them through the compact AI contract.
        if let authoredWorkout { return authoredWorkout }
        var workout = PlannedSession(
            id: UUID(),
            title: title,
            kind: WorkoutKind(rawValue: kind) ?? .custom,
            scheduledStart: nil,
            durationMinutes: durationMinutes,
            targetDistanceKilometers: targetDistanceKilometers,
            targetPaceSecondsPerKilometer: targetPaceSecondsPerKilometer,
            routeID: nil,
            exercises: exercises.map {
                $0.makePlannedExercise(in: exerciseLibrary)
            },
            notes: notes
        )
        let resolved = (blocks ?? []).prefix(100).enumerated().compactMap {
            index, step in step.plannedBlock(
                sequence: index + 1, kind: workout.kind
            )
        }

        // ATHLTH Advanced executes a single ordered timeline. AI strength
        // responses may provide exercise sets without per-set blocks. Project
        // these through the SAME bridge used by manually planned sessions
        // so sets, rests, exercise references and RPE are not discarded.
        // Avoid executing both the AI exercise list and its projected copy.
        if workout.kind == .strength, !workout.exercises.isEmpty {
            let strengthBlocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
            if strengthBlocks.contains(where: { $0.kind == .exercise }) {
                ATHLTHUnifiedWorkout.apply(
                    blocks: strengthBlocks, title: workout.title,
                    routeID: workout.routeID,
                    estimatedMinutes: workout.durationMinutes, to: &workout
                )
            }
            return workout
        }

        let compatibleBlocks = resolved.filter { block in
            if workout.kind == .running || workout.kind == .walking {
                return block.kind == .run || block.kind == .rest ||
                    block.kind == .note
            }
            return true
        }
        if compatibleBlocks.contains(where: {
            $0.kind == .run || $0.kind == .exercise
        }) {
            ATHLTHUnifiedWorkout.apply(
                blocks: compatibleBlocks, title: workout.title,
                routeID: workout.routeID,
                estimatedMinutes: workout.durationMinutes, to: &workout
            )
        } else if workout.kind == .running || workout.kind == .walking {
            // A steady/easy run without explicit AI blocks is a valid Basic
            // prescription. Convert its real duration/distance into a
            // single runnable ATHLTH main block, not an empty placeholder.
            let steady = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
            if steady.contains(where: { $0.kind == .run }) {
                ATHLTHUnifiedWorkout.apply(
                    blocks: steady, title: workout.title,
                    routeID: workout.routeID,
                    estimatedMinutes: workout.durationMinutes, to: &workout
                )
            }
        }
        return workout
    }
}

/// A validated, explicit chronological AI workout step. The model never has
/// to invent a UUID or an exercise weight; missing targets remain nil.
struct AIProgramDraftStep: Codable, Hashable {
    let title: String
    let kind: String
    let phase: String
    let durationSeconds: Double?
    let distanceMeters: Double?
    let repetitions: Int?
    let targetPaceSecondsPerKilometer: Double?
    let treadmillInclinePercent: Double?
    let targetHeartRateZone: Int?
    let targetEffortRPE: Int?
    let notes: String?

    func plannedBlock(sequence: Int, kind workoutKind: WorkoutKind) -> WorkoutTemplateBlock? {
        guard let blockKind = WorkoutTemplateBlockKind(rawValue: kind),
              let resolvedPhase = WorkoutPhaseKind(rawValue: phase),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        var block = WorkoutTemplateBlock(
            sequence: sequence, kind: blockKind,
            title: String(title.prefix(120)), exerciseSlug: nil,
            distanceMeters: distanceMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            repetitions: repetitions.flatMap { (1...100).contains($0) ? $0 : nil },
            durationSeconds: durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            targetWeightKilograms: nil, loadNote: nil,
            notes: notes.map { String($0.prefix(500)) }, phase: resolvedPhase,
            targetPaceSecondsPerKilometer: targetPaceSecondsPerKilometer.flatMap {
                $0.isFinite && (120...1200).contains($0) ? $0 : nil
            },
            targetHeartRateZone: targetHeartRateZone.flatMap {
                (1...5).contains($0) ? $0 : nil
            }
        )
        block.targetEffortRPE = targetEffortRPE.flatMap {
            (1...10).contains($0) ? $0 : nil
        }
        block.treadmillInclinePercent = treadmillInclinePercent.flatMap {
            $0.isFinite && (0...20).contains($0) ? $0 : nil
        }
        if blockKind == .run {
            block.cardioActivity = workoutKind == .walking ? .walking : .running
            block.isIndoor = block.treadmillInclinePercent != nil
        } else if blockKind == .exercise {
            // The unified editor/executor needs exercise identity for AI
            // strength blocks just as it does for manually added exercises.
            // Preserve the generated name without inventing a library ID.
            block.exerciseSnapshot = ExerciseSnapshot(
                name: String(title.prefix(120)),
                instructions: [], primaryMuscles: [],
                equipment: [], imageURL: nil
            )
        }
        return block
    }
}

struct AIProgramDraftExercise: Codable, Hashable {
    let name: String
    let sets: Int
    let reps: Int?
    let targetRPE: Double?
    let restSeconds: Int?
    let notes: String?

    func makePlannedExercise(
        in library: [ExerciseLibraryEntry] = []
    ) -> PlannedExercise {
        // Match canonical licensed/ATHLTH exercises only when unambiguous.
        // Never guess a user-created movement from a similar title or
        // substitute equipment variants based on fuzzy name similarity.
        let normalized = ATHLTHExerciseReferenceResolver.key(name)
        let exact = library.filter {
            ($0.source == .repDB || $0.source == .athlthCatalog) &&
            ATHLTHExerciseReferenceResolver.key($0.canonicalName) == normalized
        }
        let alias = ATHLTHExerciseReferenceResolver.nativeSourceIdentifier(
            for: name
        )
        let native = exact.isEmpty ? library.filter {
            $0.source == .athlthCatalog && $0.sourceIdentifier == alias
        } : []
        let matched = exact.count == 1 ? exact[0] :
            native.count == 1 ? native[0] : nil
        let snapshot: ExerciseSnapshot
        if let matched {
            snapshot = ExerciseSnapshot(
                name: matched.canonicalName,
                instructions: matched.exercise.instructions,
                primaryMuscles: matched.exercise.primaryMuscles,
                secondaryMuscles: matched.exercise.secondaryMuscles,
                equipment: matched.exercise.equipment,
                imageURL: matched.exercise.imageURL
            )
        } else {
            snapshot = ExerciseSnapshot(
                name: name, instructions: [], primaryMuscles: [],
                equipment: [], imageURL: nil
            )
        }

        return PlannedExercise(
            id: UUID(), exerciseID: matched?.id,
            embeddedExercise: snapshot,
            sets: max(sets, 1), reps: reps, targetWeightKilograms: nil,
            targetRPE: targetRPE, restSeconds: restSeconds, notes: notes
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
        // Only program *drafts* are generated here; no plan is saved until
        // the athlete accepts it. One automatic retry on temporary 5xx is
        // therefore safe and avoids asking the athlete to re-enter answers.
        for attempt in 0..<2 {
            do {
                return try await client.functions.invoke(
                    "generate-training-program",
                    options: FunctionInvokeOptions(body: request, timeoutInterval: 120)
                )
            } catch FunctionsError.httpError(let status, let data) {
                // Invalid AI plans are deterministic failures, not transport
                // problems. Retrying their 502 immediately can exhaust Groq's
                // token-per-minute quota and turn a 502 into a 429.
                let code = (try? JSONDecoder().decode(
                    CoachServerError.self, from: data
                ))?.code
                let transient = status == 503 || status == 504 ||
                    (status == 502 && code == "AI_PROVIDER_UNAVAILABLE")
                if transient && attempt == 0 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                throw Self.userFacingError(status: status, data: data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The underlying SDK may include raw transport details.
                // Do not present those or potentially private responses.
                throw AIProgramError.unavailable
            }
        }
        throw AIProgramError.unavailable
    }

    static func userFacingError(status: Int, data: Data) -> AIProgramError {
        let code = (try? JSONDecoder().decode(CoachServerError.self, from: data))?.code
        switch status {
        case 401: return .sessionExpired
        case 403: return .premiumRequired
        case 422 where code == "AI_COACH_INJURY_CONFLICT": return .unsafeProgram
        case 429:
            let delay = min(3600, max(1, (
                try? JSONDecoder().decode(CoachServerError.self, from: data)
            )?.retryAfterSeconds ?? 60))
            return .rateLimited(retryAfterSeconds: delay)
        case 502 where code == "AI_INVALID_PROGRAM": return .invalidProgram
        case 502, 503, 504: return .unavailable
        case 400: return .invalidRequest
        default: return .unavailable
        }
    }

    private struct CoachServerError: Decodable {
        let code: String?
        let retryAfterSeconds: Int?
    }
}

enum AIProgramError: LocalizedError, Equatable {
    case noGoals
    case unavailable
    case rateLimited(retryAfterSeconds: Int)
    case premiumRequired
    case sessionExpired
    case unsafeProgram
    case invalidProgram
    case invalidRequest

    var canRetry: Bool {
        self == .unavailable || self == .invalidProgram
    }

    var cooldownSeconds: Int? {
        guard case .rateLimited(let seconds) = self else { return nil }
        return seconds
    }

    var errorDescription: String? {
        switch self {
        case .noGoals:
            return ATHLTHLocalization.choose(
                english: "Choose at least one goal before generating a program.",
                norwegian: "Velg minst ett mål før treningsplanen lages."
            )
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "ATHLTH Coach is temporarily unavailable. Your choices are saved in this form. Please try again.",
                norwegian: "ATHLTH Coach er midlertidig utilgjengelig. Valgene dine er fortsatt her. Prøv igjen."
            )
        case .rateLimited(let seconds):
            let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
            return ATHLTHLocalization.choose(
                english: "ATHLTH Coach is temporarily busy. Try again in about \(minutes) min. Your choices are preserved.",
                norwegian: "ATHLTH Coach er midlertidig opptatt. Prøv igjen om omtrent \(minutes) min. Valgene dine er beholdt."
            )
        case .premiumRequired:
            return ATHLTHLocalization.choose(
                english: "An active ATHLTH+ subscription or trial is needed to use Coach.",
                norwegian: "Du trenger aktivt ATHLTH+-abonnement eller prøveperiode for å bruke Coach."
            )
        case .sessionExpired:
            return ATHLTHLocalization.choose(
                english: "Your sign-in session has expired. Sign in again and retry.",
                norwegian: "Innloggingen din har utløpt. Logg inn på nytt og prøv igjen."
            )
        case .unsafeProgram:
            return ATHLTHLocalization.choose(
                english: "Coach suggested an exercise you excluded. No plan was saved. Review the restrictions and try again.",
                norwegian: "Coach foreslo en øvelse du har utelukket. Ingen plan ble lagret. Kontroller begrensningene og prøv igjen."
            )
        case .invalidProgram:
            return ATHLTHLocalization.choose(
                english: "Coach could not finish a valid plan. Your choices are preserved. Please try again.",
                norwegian: "Coach klarte ikke å fullføre en gyldig treningsplan. Valgene dine er beholdt. Prøv igjen."
            )
        case .invalidRequest:
            return ATHLTHLocalization.choose(
                english: "Some plan choices need checking before Coach can continue.",
                norwegian: "Kontroller planvalgene før Coach kan fortsette."
            )
        }
    }
}
