import Foundation

/// Offline ATHLTH strength sessions. The same complete recipes are offered
/// by Workouts, the plan wizard and the standalone workout picker.
/// Prescriptions are starting points, not personalized load recommendations.
enum ATHLTHCuratedStrengthWorkouts {
    private struct Move {
        let title: String
        let sets: Int
        let reps: Int
        let rest: Int
        let cue: String?
    }

    private static func exercise(
        _ title: String, _ sets: Int, _ reps: Int,
        _ rest: Int = 90, cue: String? = nil
    ) -> Move {
        Move(title: title, sets: sets, reps: reps, rest: rest, cue: cue)
    }

    private static func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private static func entry(
        _ number: Int, _ englishTitle: String, _ norwegianTitle: String,
        _ englishSummary: String, _ norwegianSummary: String,
        minutes: Int, difficulty: String, tags: [String],
        moves: [Move]
    ) -> WorkoutTemplateCatalogEntry {
        let blocks: [WorkoutTemplateBlock] = [
            WorkoutTemplateBlock(
                sequence: 1, kind: .note,
                title: tr("Prepare for the session", "Forbered økten"),
                exerciseSlug: nil, distanceMeters: nil, repetitions: nil,
                durationSeconds: 300, targetWeightKilograms: nil,
                loadNote: nil,
                notes: tr(
                    "5 minutes of easy movement and dynamic mobility. Add light warm-up sets before the first heavy lift.",
                    "5 minutter lett bevegelse og dynamisk mobilitet. Ta lette oppvarmingssett før første tunge løft."
                ),
                phase: .warmup
            )
        ] + moves.enumerated().map { index, move in
            WorkoutTemplateBlock(
                sequence: index + 2, kind: .exercise, title: move.title,
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: move.reps, durationSeconds: nil,
                targetWeightKilograms: nil, loadNote: nil,
                notes: move.cue ?? tr(
                    "Choose a manageable load and leave about 2 reps in reserve. Adjust sets and reps to your level.",
                    "Velg en håndterbar belastning og behold omtrent 2 repetisjoner i reserve. Tilpass sett og reps til nivået ditt."
                ),
                phase: .main, setCount: move.sets,
                restBetweenSetsSeconds: TimeInterval(move.rest)
            )
        }
        return WorkoutTemplateCatalogEntry(
            id: UUID(uuidString: String(
                format: "C4000000-0000-0000-0000-%012d", number
            ))!,
            slug: String(format: "athlth-strength-%02d", number),
            title: tr(englishTitle, norwegianTitle),
            summary: tr(englishSummary, norwegianSummary),
            category: "strength",
            difficulty: tr(
                difficulty,
                difficulty == "Beginner" ? "Nybegynner" :
                    (difficulty == "Advanced" ? "Avansert" : "Middels")
            ),
            estimatedDurationMinutes: minutes,
            tags: ["strength", "styrke"] + tags,
            sourceLabel: "ATHLTH",
            sourceURL: nil,
            blocks: blocks,
            sortOrder: 100 + number
        )
    }

    static var entries: [WorkoutTemplateCatalogEntry] {
        [
            entry(1, "Full Body Foundation", "Fullkropp – grunnøkt",
                  "A simple introduction to training the whole body.",
                  "En oversiktlig økt som trener hele kroppen.",
                  minutes: 45, difficulty: "Beginner",
                  tags: ["full body", "fullkropp", "beginner"],
                  moves: [
                    exercise("Goblet Squat", 3, 10, 90),
                    exercise("Dumbbell Bench Press", 3, 10, 90),
                    exercise("Seated Cable Row", 3, 10, 90),
                    exercise("Romanian Deadlift", 2, 10, 90),
                    exercise("Plank", 3, 30, 45, cue: tr(
                        "Hold 30 seconds per set; stop before losing trunk control.",
                        "Hold 30 sekunder per sett; stopp før du mister kontrollen."
                    ))
                  ]),
            entry(2, "Full Body Strength", "Fullkropp – styrke",
                  "Compound lifts with longer recovery between heavy sets.",
                  "Baseøvelser med lengre pauser mellom tunge sett.",
                  minutes: 65, difficulty: "Intermediate",
                  tags: ["full body", "fullkropp", "compound"],
                  moves: [
                    exercise("Barbell Back Squat", 4, 6, 150),
                    exercise("Bench Press", 4, 6, 150),
                    exercise("Bent Over Row", 3, 8, 120),
                    exercise("Romanian Deadlift", 3, 8, 120),
                    exercise("Lat Pulldown", 3, 10, 75)
                  ]),
            entry(3, "Chest & Triceps", "Bryst og triceps",
                  "Pressing volume for chest and triceps.",
                  "Pressøvelser med fokus på bryst og triceps.",
                  minutes: 50, difficulty: "Intermediate",
                  tags: ["chest", "triceps", "bryst"],
                  moves: [
                    exercise("Bench Press", 4, 8, 120),
                    exercise("Incline Dumbbell Press", 3, 10, 90),
                    exercise("Cable Fly", 3, 12, 60),
                    exercise("Triceps Pushdown", 3, 12, 60),
                    exercise("Overhead Triceps Extension", 2, 12, 60)
                  ]),
            entry(4, "Back & Biceps", "Rygg og biceps",
                  "Vertical and horizontal pulling with direct arm work.",
                  "Vertikale og horisontale draøvelser med bicepsarbeid.",
                  minutes: 55, difficulty: "Intermediate",
                  tags: ["back", "rygg", "biceps"],
                  moves: [
                    exercise("Lat Pulldown", 4, 10, 90),
                    exercise("Seated Cable Row", 3, 10, 90),
                    exercise("One Arm Dumbbell Row", 3, 10, 75),
                    exercise("Barbell Curl", 3, 10, 60),
                    exercise("Hammer Curl", 3, 12, 60)
                  ]),
            entry(5, "Shoulders & Core", "Skuldre og kjerne",
                  "Shoulder strength, stability and controlled trunk work.",
                  "Skulderstyrke, stabilitet og kontrollert kjernetrening.",
                  minutes: 45, difficulty: "Intermediate",
                  tags: ["shoulders", "skuldre", "core", "kjerne"],
                  moves: [
                    exercise("Dumbbell Shoulder Press", 4, 8, 90),
                    exercise("Lateral Raise", 3, 12, 60),
                    exercise("Face Pull", 3, 12, 60),
                    exercise("Dead Bug", 3, 10, 45),
                    exercise("Side Plank", 3, 30, 45, cue: tr(
                        "Hold for 30 seconds on each side.",
                        "Hold 30 sekunder på hver side."
                    ))
                  ]),
            entry(6, "Quad-Focused Legs", "Bein – fremside lår",
                  "Squat-focused session for quads and knee strength.",
                  "Knebøydominert økt for fremside lår.",
                  minutes: 60, difficulty: "Intermediate",
                  tags: ["legs", "bein", "quads", "quadriceps"],
                  moves: [
                    exercise("Barbell Back Squat", 4, 8, 150),
                    exercise("Leg Press", 3, 10, 120),
                    exercise("Bulgarian Split Squat", 3, 10, 90),
                    exercise("Leg Extension", 3, 12, 75),
                    exercise("Standing Calf Raise", 3, 15, 60)
                  ]),
            entry(7, "Glutes & Hamstrings", "Sete og bakside lår",
                  "Hip hinges and unilateral work for the posterior chain.",
                  "Hoftedominante øvelser og ettbeinsarbeid for baksiden.",
                  minutes: 55, difficulty: "Intermediate",
                  tags: ["glutes", "setemuskler", "hamstrings", "bakside"],
                  moves: [
                    exercise("Romanian Deadlift", 4, 8, 120),
                    exercise("Hip Thrust", 4, 10, 90),
                    exercise("Lying Leg Curl", 3, 12, 75),
                    exercise("Reverse Lunge", 3, 10, 90),
                    exercise("Seated Calf Raise", 3, 15, 60)
                  ]),
            entry(8, "Push Day", "Push – pressøkt",
                  "Chest, shoulders and triceps in one session.",
                  "Bryst, skuldre og triceps i samme økt.",
                  minutes: 60, difficulty: "Intermediate",
                  tags: ["push", "chest", "bryst", "shoulders", "triceps"],
                  moves: [
                    exercise("Bench Press", 4, 8, 120),
                    exercise("Incline Dumbbell Press", 3, 10, 90),
                    exercise("Dumbbell Shoulder Press", 3, 10, 90),
                    exercise("Lateral Raise", 3, 12, 60),
                    exercise("Triceps Pushdown", 3, 12, 60)
                  ]),
            entry(9, "Pull Day", "Pull – draøkt",
                  "Back, rear shoulders and biceps in one session.",
                  "Rygg, bakside skuldre og biceps i samme økt.",
                  minutes: 60, difficulty: "Intermediate",
                  tags: ["pull", "back", "rygg", "biceps"],
                  moves: [
                    exercise("Pull Up", 3, 6, 120, cue: tr(
                        "Use assistance if needed; choose a controlled rep range.",
                        "Bruk assistanse ved behov, og hold god kontroll."
                    )),
                    exercise("Bent Over Row", 4, 8, 120),
                    exercise("Seated Cable Row", 3, 10, 90),
                    exercise("Face Pull", 3, 12, 60),
                    exercise("Hammer Curl", 3, 12, 60)
                  ]),
            entry(10, "Leg Day", "Legs – komplett beinøkt",
                  "Balanced squat, hinge, single-leg and calf work.",
                  "Balansert økt for hele underkroppen.",
                  minutes: 65, difficulty: "Intermediate",
                  tags: ["legs", "bein", "lower body"],
                  moves: [
                    exercise("Barbell Back Squat", 4, 8, 150),
                    exercise("Romanian Deadlift", 3, 10, 120),
                    exercise("Leg Press", 3, 12, 90),
                    exercise("Lying Leg Curl", 3, 12, 75),
                    exercise("Standing Calf Raise", 3, 15, 60)
                  ]),
            entry(11, "Core & Stability", "Kjerne og stabilitet",
                  "Short trunk-strength workout with movement control.",
                  "Kort økt med fokus på stabilitet og kontroll.",
                  minutes: 30, difficulty: "Beginner",
                  tags: ["core", "kjerne", "abs", "mage"],
                  moves: [
                    exercise("Dead Bug", 3, 10, 45),
                    exercise("Bird Dog", 3, 10, 45),
                    exercise("Pallof Press", 3, 12, 60),
                    exercise("Plank", 3, 30, 45, cue: tr(
                        "30 seconds per set.", "30 sekunder per sett."
                    )),
                    exercise("Side Plank", 2, 30, 45, cue: tr(
                        "30 seconds on each side.", "30 sekunder på hver side."
                    ))
                  ]),
            entry(12, "Upper Body", "Overkropp – komplett",
                  "Balanced push and pull session for the upper body.",
                  "Balansert press- og draøkt for overkroppen.",
                  minutes: 60, difficulty: "Intermediate",
                  tags: ["upper body", "overkropp"],
                  moves: [
                    exercise("Bench Press", 3, 8, 120),
                    exercise("Lat Pulldown", 3, 10, 90),
                    exercise("Dumbbell Shoulder Press", 3, 10, 90),
                    exercise("Seated Cable Row", 3, 10, 90),
                    exercise("Triceps Pushdown", 2, 12, 60),
                    exercise("Dumbbell Curl", 2, 12, 60)
                  ]),
            entry(13, "Lower Body", "Underkropp – komplett",
                  "Squat and hip-hinge movement patterns with core support.",
                  "Knebøy- og hoftemønstre med ekstra kjernestabilitet.",
                  minutes: 60, difficulty: "Intermediate",
                  tags: ["lower body", "underkropp", "legs", "bein"],
                  moves: [
                    exercise("Goblet Squat", 3, 10, 90),
                    exercise("Romanian Deadlift", 3, 10, 90),
                    exercise("Reverse Lunge", 3, 10, 90),
                    exercise("Hip Thrust", 3, 12, 75),
                    exercise("Standing Calf Raise", 3, 15, 60),
                    exercise("Dead Bug", 2, 10, 45)
                  ]),
            entry(14, "Home Strength", "Hjemmestyrke – uten utstyr",
                  "A practical whole-body workout without gym equipment.",
                  "En tilgjengelig fullkroppsøkt uten treningsapparater.",
                  minutes: 35, difficulty: "Beginner",
                  tags: ["home", "hjemme", "bodyweight", "kroppsvekt"],
                  moves: [
                    exercise("Bodyweight Squat", 3, 12, 60),
                    exercise("Push Up", 3, 8, 60, cue: tr(
                        "Use an elevated surface or knees if needed.",
                        "Bruk en benk eller knærne ved behov."
                    )),
                    exercise("Glute Bridge", 3, 12, 60),
                    exercise("Reverse Lunge", 3, 10, 60),
                    exercise("Bird Dog", 3, 10, 45)
                  ]),
            entry(15, "Arms", "Armer – biceps og triceps",
                  "Focused upper-arm accessories with controlled tempo.",
                  "Fokusert armøkt for biceps og triceps.",
                  minutes: 40, difficulty: "Intermediate",
                  tags: ["arms", "armer", "biceps", "triceps"],
                  moves: [
                    exercise("Barbell Curl", 3, 10, 75),
                    exercise("Triceps Pushdown", 3, 12, 60),
                    exercise("Incline Dumbbell Curl", 3, 10, 60),
                    exercise("Overhead Triceps Extension", 3, 12, 60),
                    exercise("Hammer Curl", 2, 12, 60)
                  ])
        ]
    }
}

extension RunningWorkoutTemplate {
    /// Keep the native running prescription intact, including repetitions,
    /// recoveries, per-rep overrides and the route. All plan pickers use this.
    func plannedSession() -> PlannedSession {
        var result = PlannedSession(
            id: UUID(), title: title, kind: .running, scheduledStart: nil,
            durationMinutes: estimatedDurationSeconds.map {
                Int(($0 / 60).rounded(.up))
            },
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: routeID,
            exercises: [], notes: summary
        )
        result.runningWorkout = self
        return result
    }
}
