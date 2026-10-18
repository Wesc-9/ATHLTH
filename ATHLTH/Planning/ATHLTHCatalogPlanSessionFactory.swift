import Foundation

/// Converts catalog plan blueprints into real, editable workouts.
/// Load is intentionally unspecified: previous performance, injury history,
/// available equipment and technique must govern weight selection.
enum ATHLTHCatalogPlanSessionFactory {
    private static func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    static func session(
        entry: TrainingPlanCatalogEntry,
        blueprint: TrainingPlanCatalogSessionBlueprint,
        week: Int
    ) -> PlannedSession {
        let weekNumber = max(week, 1)
        let competitionTaper = entry.usesCompetitionTaper &&
            weekNumber >= max(entry.durationWeeks - 1, 1)
        let recoveryWeek = weekNumber.isMultiple(of: 4) &&
            weekNumber < entry.durationWeeks && !competitionTaper

        let original = strengthRecipe(for: blueprint)
        var blocks: [WorkoutTemplateBlock]
        var category: String

        if let original {
            blocks = original.blocks
            category = "strength"
            for index in blocks.indices where blocks[index].kind == .exercise {
                if let sets = blocks[index].setCount {
                    blocks[index].setCount = max(1, sets -
                        (competitionTaper ? 2 : recoveryWeek ? 1 : 0))
                }
                if competitionTaper {
                    // Reduce fatigue, keep comfortable technical practice.
                    blocks[index].notes = tr(
                        "Competition week: practice light, crisp reps. No maximal attempts in training.",
                        "Konkurranseuke: lette, kontrollerte løft. Ingen maksløft på trening."
                    )
                }
            }
        } else if [.powerSquat, .powerBench, .powerDeadlift].contains(blueprint) {
            blocks = powerliftingBlocks(
                blueprint, week: weekNumber, recovery: recoveryWeek,
                taper: competitionTaper
            )
            category = "strength"
        } else if blueprint == .hyroxSkills || blueprint == .hyroxCircuit {
            blocks = hybridBlocks(blueprint, recovery: recoveryWeek,
                                  taper: competitionTaper)
            category = "hybrid"
        } else {
            blocks = enduranceBlocks(
                blueprint, entry: entry, week: weekNumber,
                recovery: recoveryWeek, taper: competitionTaper
            )
            category = blueprint.kind == .walking ? "walking" : "running"
        }

        // All blocks are portable and ordered. Do not generate additional
        // parallel exercise or running data that could execute twice.
        blocks = blocks.enumerated().map { index, step in
            WorkoutTemplateBlock(
                sequence: index + 1, kind: step.kind, title: step.title,
                exerciseSlug: step.exerciseSlug,
                distanceMeters: step.distanceMeters,
                repetitions: step.repetitions,
                durationSeconds: step.durationSeconds,
                targetWeightKilograms: step.targetWeightKilograms,
                loadNote: step.loadNote, notes: step.notes,
                phase: step.phase,
                targetPaceSecondsPerKilometer: step.targetPaceSecondsPerKilometer,
                targetHeartRateZone: step.targetHeartRateZone,
                setCount: step.setCount,
                restBetweenSetsSeconds: step.restBetweenSetsSeconds,
                groupID: step.groupID, groupKind: step.groupKind,
                groupRounds: step.groupRounds,
                cardioActivity: step.cardioActivity, isIndoor: step.isIndoor
            )
        }

        let baselineMinutes = original?.estimatedDurationMinutes ??
            blueprint.durationMinutes(week: weekNumber, totalWeeks: entry.durationWeeks)
        let factor = competitionTaper ? 0.60 : recoveryWeek ? 0.80 : 1.0
        let minutes = max(15, Int((Double(baselineMinutes) * factor).rounded()))

        let stage: String
        if competitionTaper {
            stage = tr(
                "Final phase: reduce volume, preserve technique and arrive rested. Move workouts to match your actual event date.",
                "Sluttfase: reduser mengden, behold teknikken og møt uthvilt. Flytt økter etter faktisk konkurransedato."
            )
        } else if recoveryWeek {
            stage = tr(
                "Recovery week: fewer sets or shorter efforts. Resist the urge to compensate with heavier work.",
                "Roligere uke: færre sett eller kortere drag. Ikke kompenser med tyngre belastning."
            )
        } else {
            stage = tr(
                "Progress only when technique and recovery allow; leave around 2 reps in reserve on strength sets.",
                "Øk gradvis kun når teknikk og restitusjon tillater det. Behold omtrent 2 reps i reserve på styrkesett."
            )
        }
        let notes = [
            tr("ATHLTH training plan: ", "ATHLTH treningsplan: ") + entry.title,
            tr("Week ", "Uke ") + "\(weekNumber)/\(entry.durationWeeks)",
            stage,
            blueprint.note(week: weekNumber, totalWeeks: entry.durationWeeks)
        ].compactMap { $0 }.joined(separator: "\n")

        var workout = PlannedSession(
            id: UUID(),
            title: original?.title ?? blueprint.title,
            kind: category == "hybrid" ? .custom : blueprint.kind,
            scheduledStart: nil,
            durationMinutes: minutes,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil, exercises: [],
            notes: notes
        )
        workout.workoutBlocks = blocks
        workout.workoutCategory = category
        workout.workoutTemplateID = original?.id
        return workout
    }

    private static func strengthRecipe(
        for blueprint: TrainingPlanCatalogSessionBlueprint
    ) -> WorkoutTemplateCatalogEntry? {
        let number: Int
        switch blueprint {
        case .strength, .fullBodyA: number = 1
        case .fullBodyB: number = 13
        case .fullBodyC: number = 2
        case .upperBody: number = 12
        case .lowerBody: number = 13
        case .push: number = 8
        case .pull: number = 9
        case .legs: number = 10
        case .chest: number = 3
        case .back: number = 4
        case .shouldersCore: number = 5
        case .quads: number = 6
        case .glutes: number = 7
        case .arms: number = 15
        case .core: number = 11
        case .home: number = 14
        default: return nil
        }
        return ATHLTHCuratedStrengthWorkouts.entries[number - 1]
    }

    private static func block(
        _ kind: WorkoutTemplateBlockKind, _ title: String,
        phase: WorkoutPhaseKind, seconds: TimeInterval? = nil,
        reps: Int? = nil, sets: Int? = nil, rest: TimeInterval? = nil,
        meters: Double? = nil, notes: String? = nil,
        walking: Bool = false
    ) -> WorkoutTemplateBlock {
        WorkoutTemplateBlock(
            sequence: 1, kind: kind, title: title, exerciseSlug: nil,
            distanceMeters: meters, repetitions: reps,
            durationSeconds: seconds, targetWeightKilograms: nil,
            loadNote: nil, notes: notes, phase: phase,
            setCount: sets, restBetweenSetsSeconds: rest,
            cardioActivity: kind == .run ? (walking ? .walking : .running) : nil
        )
    }

    private static func powerliftingBlocks(
        _ blueprint: TrainingPlanCatalogSessionBlueprint,
        week: Int, recovery: Bool, taper: Bool
    ) -> [WorkoutTemplateBlock] {
        let main: String
        let supporting: [String]
        switch blueprint {
        case .powerBench:
            main = "Bench Press"
            supporting = ["Dumbbell Bench Press", "Seated Cable Row", "Triceps Pushdown"]
        case .powerDeadlift:
            main = "Deadlift"
            supporting = ["Romanian Deadlift", "Lat Pulldown", "Dead Bug"]
        default:
            main = "Barbell Back Squat"
            supporting = ["Goblet Squat", "Romanian Deadlift", "Plank"]
        }
        let primarySets = taper ? 2 : recovery ? 2 : 4
        // Practice sets of 5 initially; fewer reps at controlled heavy
        // effort later in the cycle. Never specify an unmeasured 1RM%.
        let primaryReps = week < 5 ? 5 : 3
        var output = [block(
            .note, tr("Warm up for the main lift", "Oppvarming til hovedløftet"),
            phase: .warmup, seconds: 480,
            notes: tr("Move gradually from empty bar to comfortable warm-up sets.",
                      "Øk gradvis fra tom stang til kontrollerte oppvarmingssett.")
        )]
        output.append(block(
            .exercise, main, phase: .main,
            reps: primaryReps, sets: primarySets, rest: 180,
            notes: tr("Leave at least 2 reps in reserve; never grind maximal reps.",
                      "Ha minst 2 reps i reserve. Unngå maksløft og løft med dårlig teknikk.")
        ))
        for title in supporting {
            output.append(block(
                .exercise, title, phase: .main, reps: 8,
                sets: taper ? 1 : recovery ? 2 : 3, rest: 90,
                notes: tr("Controlled, submaximal assistance work.",
                          "Kontrollert støttearbeid uten maksimal belastning.")
            ))
        }
        return output
    }

    private static func enduranceBlocks(
        _ blueprint: TrainingPlanCatalogSessionBlueprint,
        entry: TrainingPlanCatalogEntry, week: Int,
        recovery: Bool, taper: Bool
    ) -> [WorkoutTemplateBlock] {
        let factor = taper
            ? (week == entry.durationWeeks ? 0.45 : 0.65)
            : recovery ? 0.75 : 1.0
        func minutes(_ value: Int) -> TimeInterval {
            TimeInterval(max(5, Int((Double(value) * factor).rounded())) * 60)
        }
        func easy(_ title: String, duration: TimeInterval, walking: Bool = false) -> WorkoutTemplateBlock {
            block(.run, title, phase: .main, seconds: duration,
                  notes: tr("Comfortable conversation pace; slow down if needed.",
                            "Rolig pratetempo. Senk farten ved behov."),
                  walking: walking)
        }

        switch blueprint {
        case .walking:
            return [block(
                .run, tr("Comfortable walk", "Rolig gåtur"),
                phase: .main, seconds: minutes(30 + min(week * 2, 20)),
                notes: tr("Choose a pace that allows normal conversation.",
                          "Gå i et tempo hvor du kan prate normalt."),
                walking: true
            )]

        case .walkRun:
            let runs = min(3 + max(0, (week - 1) / 2), 7)
            var steps = [block(.run, tr("Easy walking warm-up", "Rolig gangoppvarming"),
                               phase: .warmup, seconds: 5 * 60, walking: true)]
            for attempt in 0..<runs {
                steps.append(block(.run, tr("Easy jog", "Rolig jogg"),
                                   phase: .main, seconds: TimeInterval(min(2 + week / 3, 6) * 60),
                                   notes: tr("Easy, relaxed effort.", "Rolig og avslappet tempo.")))
                if attempt < runs - 1 {
                    steps.append(block(.run, tr("Walk recovery", "Gåpause"),
                                       phase: .recovery, seconds: 90, walking: true))
                }
            }
            steps.append(block(.run, tr("Cool-down walk", "Nedtrapping med gange"),
                               phase: .cooldown, seconds: 5 * 60, walking: true))
            return steps

        case .intervalRun, .racePaceRun, .hillRun, .tempoRun:
            let warm = block(.run, tr("Easy warm-up", "Rolig oppvarming"),
                             phase: .warmup, seconds: 10 * 60)
            let cool = block(.run, tr("Easy cool-down", "Rolig nedjogg"),
                             phase: .cooldown, seconds: 7 * 60)
            var steps: [WorkoutTemplateBlock] = [warm]
            if blueprint == .tempoRun {
                steps.append(block(
                    .run, tr("Controlled tempo", "Kontrollert tempo"),
                    phase: .main, seconds: minutes(12 + min(week, 14)),
                    notes: tr("Comfortably hard (RPE 6–7/10), not a time trial.",
                              "Kontrollert hardt (RPE 6–7/10), ikke makstest.")
                ))
            } else {
                let reps = taper ? 3 : recovery ? 3 : min(4 + (week - 1) / 3, 6)
                let isHill = blueprint == .hillRun
                let isPace = blueprint == .racePaceRun
                for index in 0..<reps {
                    steps.append(block(
                        .run, isHill ? tr("Uphill effort", "Motbakkedrag") :
                            isPace ? tr("Race-pace practice", "Øv på konkurransetempo") :
                            tr("Interval effort", "Intervall"),
                        phase: .main,
                        seconds: TimeInterval(isHill ? 60 : isPace ? 5 * 60 : 3 * 60),
                        notes: isHill
                            ? tr("Run uphill with controlled mechanics; walk or jog downhill.",
                                 "Løp kontrollert oppover, gå eller jogg rolig ned.")
                            : tr("Controlled hard effort, adjusted to current fitness.",
                                 "Kontrollert hardt; tilpass nivå og dagsform.")
                    ))
                    if index < reps - 1 {
                        steps.append(block(
                            .rest, tr("Easy recovery", "Rolig pause"),
                            phase: .recovery, seconds: TimeInterval(isHill ? 90 : 2 * 60)
                        ))
                    }
                }
            }
            steps.append(cool)
            return steps

        case .longRun:
            // For competition, entry prerequisites explicitly require a
            // running base. Use time, not an invented pace or distance target.
            let initial = entry.slug.contains("marathon") ? 75 : 50
            let perWeek = entry.slug.contains("marathon") ? 7 : 4
            let maximum = entry.slug.contains("marathon") ? 150 : 100
            let duration = min(initial + (week - 1) * perWeek, maximum)
            return [easy(tr("Easy long run", "Rolig langtur"), duration: minutes(duration))]

        case .recovery:
            return [easy(tr("Recovery walk", "Restitusjonsgåtur"),
                         duration: minutes(25), walking: true)]

        case .mobility:
            return [block(
                .note, tr("Mobility practice", "Bevegelighet"),
                phase: .main, seconds: 20 * 60,
                notes: tr("Gentle range-of-motion work. Stop if painful.",
                          "Rolige bevegelighetsøvelser. Stopp ved smerte.")
            )]

        default:
            return [easy(
                tr("Easy aerobic run", "Rolig løpetur"),
                duration: minutes(30 + min((week - 1) * 2, 22))
            )]
        }
    }

    private static func hybridBlocks(
        _ blueprint: TrainingPlanCatalogSessionBlueprint,
        recovery: Bool, taper: Bool
    ) -> [WorkoutTemplateBlock] {
        let reduced = recovery || taper
        let skill = blueprint == .hyroxSkills
        let distance = reduced ? 300.0 : skill ? 400.0 : 600.0
        let reps = reduced ? 8 : 12
        return [
            block(.run, tr("Warm-up jog", "Rolig oppvarming"),
                  phase: .warmup, seconds: 8 * 60),
            block(.run, tr("Controlled run", "Kontrollert løping"),
                  phase: .main, meters: distance),
            block(.exercise, "SkiErg", phase: .main, meters: distance,
                  notes: tr("Smooth strokes; technique before speed.",
                            "Jevne drag; teknikk før fart.")),
            block(.rest, tr("Transition", "Overgang"), phase: .recovery,
                  seconds: 90),
            block(.run, tr("Controlled run", "Kontrollert løping"),
                  phase: .main, meters: distance),
            block(.exercise, "Row", phase: .main, meters: distance,
                  notes: tr("Maintain controlled rowing technique.",
                            "Behold kontrollert roteknikk.")),
            block(.exercise, "Wall Balls", phase: .main, reps: reps,
                  notes: tr("Choose a light, manageable ball.",
                            "Velg en lett og håndterbar ball.")),
            block(.exercise, skill ? "Farmers Carry" : "Sandbag Lunges",
                  phase: .main, meters: reduced ? 30 : 50,
                  notes: tr("Use a manageable load and prioritize form.",
                            "Velg håndterbar belastning og prioriter teknikk.")),
            block(.run, tr("Easy cool-down", "Rolig nedjogg"),
                  phase: .cooldown, seconds: 5 * 60)
        ]
    }
}
