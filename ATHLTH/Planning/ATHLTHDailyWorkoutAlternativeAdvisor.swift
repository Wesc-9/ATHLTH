import Foundation

/// Small snapshot, not a second calendar entry. Keeping the original values
/// makes a one-day alternative reversible without losing interval definitions.
struct ATHLTHOriginalPlannedWorkout: Codable, Hashable {
    let title: String
    let kind: WorkoutKind
    let durationMinutes: Int?
    let targetDistanceKilometers: Double?
    let targetPaceSecondsPerKilometer: Double?
    let routeID: UUID?
    let exercises: [PlannedExercise]
    let notes: String?
    let runningWorkout: RunningWorkoutTemplate?
    let runningWorkouts: [RunningWorkoutTemplate]?
    let workoutBlocks: [WorkoutTemplateBlock]?
    let workoutCategory: String?
    let workoutTemplateID: UUID?

    init(_ workout: PlannedSession) {
        title = workout.title
        kind = workout.kind
        durationMinutes = workout.durationMinutes
        targetDistanceKilometers = workout.targetDistanceKilometers
        targetPaceSecondsPerKilometer = workout.targetPaceSecondsPerKilometer
        routeID = workout.routeID
        exercises = workout.exercises
        notes = workout.notes
        runningWorkout = workout.runningWorkout
        runningWorkouts = workout.runningWorkouts
        workoutBlocks = workout.workoutBlocks
        workoutCategory = workout.workoutCategory
        workoutTemplateID = workout.workoutTemplateID
    }

    func restoring(_ workout: PlannedSession) -> PlannedSession {
        var result = workout
        result.title = title
        result.kind = kind
        result.durationMinutes = durationMinutes
        result.targetDistanceKilometers = targetDistanceKilometers
        result.targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer
        result.routeID = routeID
        result.exercises = exercises
        result.notes = notes
        result.runningWorkout = runningWorkout
        result.runningWorkouts = runningWorkouts
        result.workoutBlocks = workoutBlocks
        result.workoutCategory = workoutCategory
        result.workoutTemplateID = workoutTemplateID
        result.dailyAlternativeOriginal = nil
        return result
    }
}

/// Pure, on-device recommendation. Always distinguish measured recovery
/// from self-reported discomfort. Never invent pain, injury or a diagnosis.
enum ATHLTHDailyWorkoutAlternativeAdvisor {
    enum Choice: String, CaseIterable, Identifiable {
        case mobility, rest, gentleWalk, shorterRun, lighterStrength
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .mobility: return "figure.flexibility"
            case .rest: return "moon.stars.fill"
            case .gentleWalk: return "figure.walk"
            case .shorterRun: return "figure.run"
            case .lighterStrength: return "dumbbell.fill"
            }
        }
        var title: String {
            switch self {
            case .mobility:
                return ATHLTHLocalization.choose(
                    english: "15 min gentle mobility",
                    norwegian: "15 min rolig mobilitet")
            case .rest:
                return ATHLTHLocalization.choose(
                    english: "Recovery day", norwegian: "Restitusjonsdag")
            case .gentleWalk:
                return ATHLTHLocalization.choose(
                    english: "20 min easy walk", norwegian: "20 min rolig gåtur")
            case .shorterRun:
                return ATHLTHLocalization.choose(
                    english: "Shorter easy run", norwegian: "Kortere rolig løp")
            case .lighterStrength:
                return ATHLTHLocalization.choose(
                    english: "Lighter strength session", norwegian: "Lettere styrkeøkt")
            }
        }
    }

    struct Suggestion: Identifiable {
        let choice: Choice
        let reason: String
        let distanceKilometers: Double?
        var id: Choice { choice }
        var title: String {
            if choice == .shorterRun, let distanceKilometers {
                return ATHLTHLocalization.choose(
                    english: String(format: "%.1f km easy running", distanceKilometers),
                    norwegian: String(format: "%.1f km rolig løping", distanceKilometers))
            }
            return choice.title
        }
    }

    /// Today's check-in is voluntary; nil means unknown, not "normal".
    struct Signals {
        let energy: Int?
        let stress: Int?
        let overallSoreness: Int?
        let muscleRatings: [String: RecoverySorenessLevel]
        let readiness: RecoveryReadinessSummary?

        var lowerLimbFatigue: Bool {
            // Feet must be explicitly reported. Calves and shins are not
            // silently translated into a claim about foot pain.
            ["Feet", "Shins", "Calves"].contains { key in
                (muscleRatings[key]?.rawValue ?? 0) >= 2
            }
        }
        var strongFatigue: Bool {
            (energy.map { $0 <= 2 } ?? false) ||
            (overallSoreness.map { $0 >= 4 } ?? false)
        }
        var highStress: Bool { stress.map { $0 >= 4 } ?? false }
        var lowWearableReadiness: Bool {
            guard let readiness, readiness.score != nil,
                  readiness.baselineDays >= 5 else { return false }
            return readiness.state == .recover || readiness.state == .takeItEasy
        }
        var needsAlternative: Bool {
            lowerLimbFatigue || strongFatigue || highStress ||
            lowWearableReadiness
        }
        var reason: String {
            if lowerLimbFatigue {
                return ATHLTHLocalization.choose(
                    english: "You reported sore feet or lower legs. A low-impact activity avoids adding the planned running load.",
                    norwegian: "Du har registrert ømme føtter eller legger. En skånsom aktivitet unngår den planlagte løpebelastningen.")
            }
            if energy.map({ $0 <= 2 }) == true {
                return ATHLTHLocalization.choose(
                    english: "You reported low energy today. Consider another type of activity instead of pushing through the original session.",
                    norwegian: "Du har oppgitt lav energi i dag. Vurder en annen aktivitet fremfor å presse gjennom hele den planlagte økten.")
            }
            if overallSoreness.map({ $0 >= 4 }) == true {
                return ATHLTHLocalization.choose(
                    english: "You reported pronounced soreness. Gentler movement or a recovery day may fit better.",
                    norwegian: "Du har rapportert betydelig ømhet. Roligere bevegelse eller restitusjon kan passe bedre.")
            }
            if highStress {
                return ATHLTHLocalization.choose(
                    english: "You reported elevated stress. A lighter activity may be preferable today.",
                    norwegian: "Du har rapportert høyt stress. En lettere aktivitet kan passe bedre i dag.")
            }
            return ATHLTHLocalization.choose(
                english: "Your recent Watch recovery signals suggest reducing training load today.",
                norwegian: "Nylige restitusjonssignaler fra klokken tilsier at det kan være klokt å redusere belastningen i dag.")
        }
    }

    static func suggestions(
        for original: PlannedSession, signals: Signals
    ) -> [Suggestion] {
        guard !original.isExplicitRestDay,
              original.dailyAlternativeOriginal == nil,
              signals.needsAlternative else { return [] }

        let reason = signals.reason
        let legFatigue = signals.lowerLimbFatigue ||
            (signals.overallSoreness.map { $0 >= 4 } ?? false)
        let significantMuscleSoreness =
            signals.muscleRatings.values.contains { $0 == .high } ||
            (signals.overallSoreness.map { $0 >= 4 } ?? false)
        var choices: [Choice]
        switch original.kind {
        case .running:
            // When legs or feet are sore, don't recommend another impact
            // session. Otherwise show the actual reduced-distance suggestion
            // first; it must not be hidden behind another menu.
            choices = legFatigue
                ? [.mobility, .rest]
                : [.shorterRun, .rest, .gentleWalk, .mobility]
        case .walking:
            choices = [.mobility, .rest]
        case .strength:
            // We cannot safely infer an alternative exercise from generic
            // soreness without an exercise-to-muscle assessment. Offer a
            // lighter version of the existing plan only when muscles are not
            // explicitly marked highly sore and set targets can be reduced.
            choices = significantMuscleSoreness || signals.lowerLimbFatigue
                ? [.mobility, .rest]
                : [.lighterStrength, .rest, .mobility]
        case .mobility, .recovery, .custom:
            return []
        }
        let reducedDistance = original.targetDistanceKilometers.map {
            max(1.0, (min($0 * 0.4, 5.0) * 2).rounded() / 2)
        }
        return choices.compactMap { choice in
            if choice == .shorterRun {
                guard let reducedDistance,
                      reducedDistance < (original.targetDistanceKilometers ?? 0)
                else { return nil }
            }
            if choice == .lighterStrength &&
                (!(original.workoutBlocks ?? []).isEmpty ||
                 ATHLTHTrainRecoveryAdvisor.lighterStrengthSession(original) == nil) {
                return nil
            }
            return Suggestion(
                choice: choice, reason: reason,
                distanceKilometers: choice == .shorterRun
                    ? reducedDistance : nil
            )
        }
    }

    /// This is only invoked after the athlete confirms. Preserve identity
    /// for plan history and Watch sync; clear incompatible route/interval/
    /// strength steps rather than passing an old running block into mobility.
    static func replacing(
        _ original: PlannedSession, with suggestion: Suggestion
    ) -> PlannedSession {
        var proposed = original
        proposed.dailyAlternativeOriginal = ATHLTHOriginalPlannedWorkout(original)
        proposed.title = suggestion.title
        proposed.exercises = []
        proposed.runningWorkout = nil
        proposed.runningWorkouts = nil
        proposed.routeID = nil
        proposed.targetDistanceKilometers = nil
        proposed.targetPaceSecondsPerKilometer = nil
        proposed.workoutTemplateID = nil
        proposed.workoutBlocks = nil
        proposed.workoutCategory = nil
        proposed.notes = ATHLTHLocalization.choose(
            english: "Athlete-approved alternative to: \(original.title). \(suggestion.reason)",
            norwegian: "Brukergodkjent alternativ til: \(original.title). \(suggestion.reason)"
        )

        switch suggestion.choice {
        case .mobility:
            proposed.kind = .mobility
            proposed.durationMinutes = 15
            proposed.workoutCategory = "mobility"
            var block = WorkoutTemplateBlock(
                sequence: 1, kind: .note,
                title: ATHLTHLocalization.choose(
                    english: "Gentle mobility without loading the feet",
                    norwegian: "Rolig mobilitet uten belastning på føttene"),
                exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: 900,
                targetWeightKilograms: nil, loadNote: nil,
                notes: ATHLTHLocalization.choose(
                    english: "Choose comfortable seated or lying movements. Stop if pain increases.",
                    norwegian: "Velg behagelige bevegelser sittende eller liggende. Stopp dersom smerter øker."),
                phase: .recovery
            )
            block.wellnessKind = .mobility
            proposed.workoutBlocks = [block]
        case .rest:
            proposed.kind = .recovery
            proposed.durationMinutes = nil
            proposed.workoutCategory = "rest_day"
        case .gentleWalk:
            proposed.kind = .walking
            proposed.durationMinutes = 20
            proposed.workoutCategory = "walking"
        case .shorterRun:
            proposed.kind = .running
            proposed.durationMinutes = nil
            proposed.targetDistanceKilometers = suggestion.distanceKilometers
            proposed.workoutCategory = "running"
            // Use the existing iPhone/Watch running-template pipeline,
            // NOT workoutBlocks: the latter would launch the phone-only
            // structured-session view instead of the normal Watch run flow.
            // The original interval targets, route and ghost are not carried
            // into this low-intensity substitute.
            if let distance = suggestion.distanceKilometers {
                let easyName = ATHLTHLocalization.choose(
                    english: "Easy running · zone 2",
                    norwegian: "Rolig løping · sone 2")
                let zoneTwo = RunningIntensityTarget(
                    kind: .heartRateZone,
                    paceMinSecondsPerKilometer: nil,
                    paceMaxSecondsPerKilometer: nil,
                    heartRateZone: 2,
                    rpe: nil
                )
                var template = RunningWorkoutTemplate(
                    id: UUID(), title: easyName, type: .recovery,
                    summary: ATHLTHLocalization.choose(
                        english: "Reduced easy run in heart-rate zone 2",
                        norwegian: "Kortere, rolig løp i pulssone 2"),
                    blocks: [RunningWorkoutBlock(
                        kind: .steady, title: easyName,
                        work: .distance(distance * 1_000, intensity: zoneTwo)
                    )],
                    routeID: nil, isBuiltIn: false,
                    createdAt: Date(), updatedAt: Date()
                )
                template.coachBrief = ATHLTHLocalization.choose(
                    english: "Keep an easy conversational effort in zone 2.",
                    norwegian: "Hold en rolig pratetempo-intensitet i pulssone 2."
                )
                proposed.runningWorkout = template
            }
        case .lighterStrength:
            proposed.kind = .strength
            proposed.workoutCategory = "strength"
            if let reduced = ATHLTHTrainRecoveryAdvisor
                .lighterStrengthSession(original) {
                proposed.exercises = reduced.exercises
            }
        }
        return proposed
    }
}
