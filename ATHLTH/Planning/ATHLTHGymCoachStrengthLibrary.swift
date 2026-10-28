import Foundation

/// Offline strength training library derived from attributed GymCoach program
/// templates. These are editable, repeatable training microcycles, NOT a claim
/// that all trademarked source programs' numerical periodization is implemented.
/// No exercise load or training max is guessed from a program name.
enum ATHLTHGymCoachStrengthLibrary {
    struct Exercise: Decodable, Sendable {
        let name: String
        let muscleGroup: String
        let category: String
        let targetSets: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let targetRIR: Int
        let restSec: Int
        let notes: String?
        let tempo: String?
        let equipmentType: String?
        let supersetGroup: Int?
    }

    struct Workout: Decodable, Sendable {
        let name: String
        let dayOfWeek: Int?
        let exercises: [Exercise]
    }

    struct Definition: Decodable, Sendable {
        let name: String
        let description: String?
        let phase: String
        let workouts: [Workout]
    }

    struct Program: Decodable, Sendable {
        let slug: String
        let name: String
        let summary: String
        let attribution: String
        let program: Definition
    }

    static let programs: [Program] = {
        guard let url = Bundle.main.url(
            forResource: "GymCoachStrengthPrograms", withExtension: "json"
        ), let data = try? Data(contentsOf: url),
           let result = try? JSONDecoder().decode([Program].self, from: data)
        else { return [] }
        return result
    }()

    static func program(for slug: String) -> Program? {
        guard slug.hasPrefix("gymcoach-") else { return nil }
        let id = String(slug.dropFirst("gymcoach-".count))
        return programs.first(where: { $0.slug == id })
    }

    /// A/B plans require three sessions per week, alternating A-B-A then B-A-B.
    /// For other templates every source workout is scheduled once per week.
    static func sessionsPerWeek(_ program: Program) -> Int {
        switch program.slug {
        case "starting-strength-3day", "stronglifts-5x5-3day": return 3
        default: return max(2, min(program.program.workouts.count, 6))
        }
    }

    static func sourceWorkouts(for program: Program, week: Int) -> [Workout] {
        let list = program.program.workouts
        guard !list.isEmpty else { return [] }
        let count = sessionsPerWeek(program)
        if list.count == 2 && count == 3 {
            let base = (max(week, 1) - 1) * 3
            return (0..<3).map { list[(base + $0) % 2] }
        }
        return Array(list.prefix(count))
    }

    static var catalogEntries: [TrainingPlanCatalogEntry] {
        programs.enumerated().map { index, p in
            let count = sessionsPerWeek(p)
            let advanced = ["nsuns-4day", "phat-5day", "531-bbb-4day", "madcow-5x5-3day"]
                .contains(p.slug)
            let goal = ATHLTHLocalization.choose(
                english: "Strength and muscle development",
                norwegian: "Styrke og muskelvekst"
            )
            return TrainingPlanCatalogEntry(
                id: UUID(uuidString: String(format: "C5000000-0000-0000-0000-%012d", index + 1))!,
                slug: "gymcoach-\(p.slug)",
                title: p.name,
                summary: ATHLTHLocalization.choose(
                    english: p.summary + " Editable repeatable weeks; load is individualized.",
                    norwegian: "Strukturert styrkeprogram med \(count) økter i uken. Sett, repetisjoner, pauser og RIR følger kildemalen. Belastning tilpasses individuelt."
                ),
                category: "strength",
                goal: goal,
                level: ATHLTHLocalization.choose(
                    english: advanced ? "Advanced" : "Intermediate",
                    norwegian: advanced ? "Avansert" : "Middels"
                ),
                durationWeeks: 8,
                sessionsPerWeek: count,
                workoutPattern: Array(repeating: "strength", count: count),
                tags: ["strength", "styrke", "gymcoach", "source:GymCoach",
                       advanced ? "advanced" : "intermediate", "editable-microcycle"],
                sortOrder: 86 + index,
                catalogVersion: 1
            )
        }
    }

    static var workoutCatalogEntries: [WorkoutTemplateCatalogEntry] {
        var entries: [WorkoutTemplateCatalogEntry] = []
        for (programIndex, plan) in programs.enumerated() {
            for (workoutIndex, workout) in plan.program.workouts.enumerated() {
                entries.append(WorkoutTemplateCatalogEntry(
                    id: UUID(uuidString: String(
                        format: "C6000000-0000-0000-0000-%012d",
                        programIndex * 10 + workoutIndex + 1
                    ))!,
                    slug: "gymcoach-\(plan.slug)-\(workoutIndex + 1)",
                    title: "\(plan.name) · \(localizedWorkoutTitle(workout.name))",
                    summary: ATHLTHLocalization.choose(
                        english: "Structured strength workout with sets, reps, RIR and recoveries.",
                        norwegian: "Styrkeøkt med sett, repetisjoner, RIR og pauser."
                    ),
                    category: "strength",
                    difficulty: ATHLTHLocalization.choose(
                        english: "Intermediate", norwegian: "Middels"
                    ),
                    estimatedDurationMinutes: estimatedMinutes(workout),
                    tags: ["strength", "gymcoach", "sets", "RIR"],
                    sourceLabel: "GymCoach · MIT",
                    sourceURL: "https://github.com/gymcoach-app/gymcoach",
                    blocks: blocks(for: workout),
                    sortOrder: 850 + programIndex * 10 + workoutIndex
                ))
            }
        }
        return entries
    }

    static func plannedSession(
        _ workout: Workout, program: Program, week: Int
    ) -> PlannedSession {
        let title = localizedWorkoutTitle(workout.name)
        let isDeloadSuggestion = week.isMultiple(of: 4)
        var steps = blocks(for: workout)
        if isDeloadSuggestion {
            // Explicitly optional: the original source template does not
            // encode a deload week. Do not silently lower planned loads.
            let explanation = ATHLTHLocalization.choose(
                english: "Week \(week): review whether a lighter week is appropriate. This is not an automatic load adjustment.",
                norwegian: "Uke \(week): vurder om en lettere uke passer. Ingen belastning endres automatisk."
            )
            if !steps.isEmpty { steps[0].notes = explanation }
        }
        let caveat = ATHLTHLocalization.choose(
            english: "GymCoach template · \(program.name). Repeating eight-week schedule for editing; 5/3/1, nSuns and other percentage waves require a personally entered training max and individual review. No weight prescriptions are assumed.",
            norwegian: "GymCoach-mal · \(program.name). Åtte ukers redigerbart oppsett. Prosentbaserte programmer som 5/3/1 og nSuns krever individuelt oppgitt treningsmaks og egen gjennomgang. Ingen vekter er antatt."
        )
        var result = PlannedSession(
            id: UUID(), title: title, kind: .strength,
            scheduledStart: nil, durationMinutes: estimatedMinutes(workout),
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [], notes: caveat
        )
        ATHLTHUnifiedWorkout.apply(
            blocks: steps,
            title: result.title,
            routeID: nil,
            estimatedMinutes: result.durationMinutes,
            to: &result
        )
        result.workoutCategory = "strength"
        return result
    }

    static func blocks(for workout: Workout) -> [WorkoutTemplateBlock] {
        var blocks: [WorkoutTemplateBlock] = [
            WorkoutTemplateBlock(
                sequence: 1, kind: .note,
                title: ATHLTHLocalization.choose(
                    english: "Warm up before working sets", norwegian: "Varm opp før arbeidssettene"
                ),
                exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
                durationSeconds: 300, targetWeightKilograms: nil,
                loadNote: nil,
                notes: ATHLTHLocalization.choose(
                    english: "Prepare joints and technique, then use lighter warm-up sets before your first heavy lift.",
                    norwegian: "Klargjør ledd og teknikk, og ta lettere oppvarmingssett før første tunge løft."
                ),
                phase: .warmup
            )
        ]
        for exercise in workout.exercises.prefix(20) {
            guard (1...20).contains(exercise.targetSets),
                  (1...50).contains(exercise.targetRepsMin),
                  exercise.targetRepsMax >= exercise.targetRepsMin,
                  exercise.targetRepsMax <= 50,
                  (0...5).contains(exercise.targetRIR),
                  (15...600).contains(exercise.restSec) else { continue }

            let slug = ATHLTHExerciseReferenceResolver.nativeSourceIdentifier(
                for: exercise.name
            )
            let title = NorwegianExerciseText.name(for: slug) ??
                exercise.name
            let loadDescription = ATHLTHLocalization.choose(
                english: "\(exercise.targetRepsMin)–\(exercise.targetRepsMax) reps · \(exercise.targetRIR) reps in reserve",
                norwegian: "\(exercise.targetRepsMin)–\(exercise.targetRepsMax) repetisjoner · \(exercise.targetRIR) i reserve"
            )
            var block = WorkoutTemplateBlock(
                sequence: blocks.count + 1, kind: .exercise,
                title: title,
                exerciseSlug: slug,
                distanceMeters: nil,
                repetitions: exercise.targetRepsMin,
                durationSeconds: nil,
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: loadDescription,
                phase: .main,
                targetEffortRPE: 10 - exercise.targetRIR,
                setCount: exercise.targetSets,
                restBetweenSetsSeconds: Double(exercise.restSec)
            )
            block.exerciseSnapshot = ExerciseSnapshot(
                name: exercise.name, instructions: [],
                primaryMuscles: [exercise.muscleGroup.lowercased()],
                equipment: exercise.equipmentType.map { [$0] } ?? [],
                imageURL: nil
            )
            blocks.append(block)
        }
        return blocks
    }

    private static func estimatedMinutes(_ workout: Workout) -> Int {
        let totalSeconds = workout.exercises.reduce(300) { partial, x in
            partial + (x.targetSets * 45) +
                (max(x.targetSets - 1, 0) * x.restSec)
        }
        return max(20, min(150, (totalSeconds + 59) / 60))
    }

    private static func localizedWorkoutTitle(_ title: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return title }
        return title
            .replacingOccurrences(of: "Day ", with: "Dag ")
            .replacingOccurrences(of: "Workout ", with: "Økt ")
            .replacingOccurrences(of: "Upper", with: "Overkropp")
            .replacingOccurrences(of: "Lower", with: "Underkropp")
            .replacingOccurrences(of: "Strength", with: "Styrke")
            .replacingOccurrences(of: "Hypertrophy", with: "Muskelvekst")
            .replacingOccurrences(of: "Squat", with: "Knebøy")
            .replacingOccurrences(of: "Bench", with: "Benkpress")
            .replacingOccurrences(of: "Deadlift", with: "Markløft")
            .replacingOccurrences(of: "Press", with: "Press")
    }
}
