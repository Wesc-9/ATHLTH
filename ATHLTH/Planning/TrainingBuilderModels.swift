import Foundation

enum StrengthProgressionKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case addWeight
    case addReps
    case doubleProgression
    case percentage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return ATHLTHLocalization.string( "No automatic progression")
        case .addWeight: return ATHLTHLocalization.string( "Add weight")
        case .addReps: return ATHLTHLocalization.string( "Add reps")
        case .doubleProgression: return ATHLTHLocalization.string( "Double progression")
        case .percentage: return ATHLTHLocalization.string( "Percentage")
        }
    }
}

struct StrengthProgressionRule: Codable, Hashable {
    var kind: StrengthProgressionKind
    var amount: Double
    var minimumReps: Int?
    var maximumReps: Int?
    var applyWhenAllSetsCompleted: Bool

    static let none = StrengthProgressionRule(
        kind: .none,
        amount: 0,
        minimumReps: nil,
        maximumReps: nil,
        applyWhenAllSetsCompleted: true
    )
}

enum RunningWorkoutType: String, CaseIterable, Identifiable, Codable, Hashable {
    case easy
    case recovery
    case longRun
    case tempo
    case threshold
    case intervals
    case fartlek
    case hills
    case racePace
    case progression
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return ATHLTHLocalization.string( "Easy Run")
        case .recovery: return ATHLTHLocalization.string( "Recovery Run")
        case .longRun: return ATHLTHLocalization.string( "Long Run")
        case .tempo: return ATHLTHLocalization.string( "Tempo")
        case .threshold: return ATHLTHLocalization.string( "Threshold")
        case .intervals: return ATHLTHLocalization.string( "Intervals")
        case .fartlek: return ATHLTHLocalization.string( "Fartlek")
        case .hills: return ATHLTHLocalization.string( "Hill Repeats")
        case .racePace: return ATHLTHLocalization.string( "Race Pace")
        case .progression: return ATHLTHLocalization.string( "Progression Run")
        case .custom: return ATHLTHLocalization.string( "Custom")
        }
    }

    var systemImage: String {
        switch self {
        case .easy, .recovery: return "figure.run"
        case .longRun: return "road.lanes"
        case .tempo, .threshold, .racePace: return "speedometer"
        case .intervals: return "repeat"
        case .fartlek: return "waveform.path"
        case .hills: return "mountain.2.fill"
        case .progression: return "chart.line.uptrend.xyaxis"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum RunningBlockKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case warmup
    case work
    case recovery
    case steady
    case cooldown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmup: return ATHLTHLocalization.string( "Warm-up")
        case .work: return ATHLTHLocalization.string( "Work")
        case .recovery: return ATHLTHLocalization.string( "Recovery")
        case .steady: return ATHLTHLocalization.string( "Steady")
        case .cooldown: return ATHLTHLocalization.string( "Cool-down")
        }
    }
}

enum RunningMeasureKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case distance
    case time
    case open

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return ATHLTHLocalization.string( "Distance")
        case .time: return ATHLTHLocalization.string( "Time")
        case .open: return ATHLTHLocalization.string( "Open")
        }
    }
}

enum RunningIntensityKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case easy
    case pace
    case heartRateZone
    case rpe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return ATHLTHLocalization.string( "No target")
        case .easy: return ATHLTHLocalization.string( "Easy effort")
        case .pace: return ATHLTHLocalization.string( "Pace")
        case .heartRateZone: return ATHLTHLocalization.string( "Heart-rate zone")
        case .rpe: return ATHLTHLocalization.string( "RPE")
        }
    }
}

struct RunningIntensityTarget: Codable, Hashable {
    var kind: RunningIntensityKind
    var paceMinSecondsPerKilometer: Double?
    var paceMaxSecondsPerKilometer: Double?
    var heartRateZone: Int?
    var rpe: Double?

    static let easy = RunningIntensityTarget(
        kind: .easy,
        paceMinSecondsPerKilometer: nil,
        paceMaxSecondsPerKilometer: nil,
        heartRateZone: nil,
        rpe: nil
    )

    static let none = RunningIntensityTarget(
        kind: .none,
        paceMinSecondsPerKilometer: nil,
        paceMaxSecondsPerKilometer: nil,
        heartRateZone: nil,
        rpe: nil
    )
}

struct RunningStepTarget: Codable, Hashable {
    var measure: RunningMeasureKind
    var distanceMeters: Double?
    var durationSeconds: TimeInterval?
    var intensity: RunningIntensityTarget
    /// A prescribed treadmill setting, not a sensor measurement.
    var treadmillInclinePercent: Double? = nil

    static func distance(
        _ meters: Double,
        intensity: RunningIntensityTarget = .none
    ) -> RunningStepTarget {
        RunningStepTarget(
            measure: .distance,
            distanceMeters: meters,
            durationSeconds: nil,
            intensity: intensity
        )
    }

    static func time(
        _ seconds: TimeInterval,
        intensity: RunningIntensityTarget = .none
    ) -> RunningStepTarget {
        RunningStepTarget(
            measure: .time,
            distanceMeters: nil,
            durationSeconds: seconds,
            intensity: intensity
        )
    }

    static let open = RunningStepTarget(
        measure: .open,
        distanceMeters: nil,
        durationSeconds: nil,
        intensity: .none
    )
}


/// Planning estimates only. Never treat a speed target as GPS/HealthKit evidence.
/// A complete distance estimate requires every time-based movement phase,
/// including active recoveries and cool-downs, to have an explicit pace.
enum ATHLTHRunningEstimate {
    static func distanceMeters(for target: RunningStepTarget) -> Double? {
        switch target.measure {
        case .distance:
            guard let meters = target.distanceMeters,
                  meters.isFinite, meters > 0 else { return nil }
            return meters
        case .time:
            guard let seconds = target.durationSeconds,
                  seconds.isFinite, seconds > 0,
                  let pace = target.intensity.paceMinSecondsPerKilometer,
                  pace.isFinite, pace > 0 else { return nil }
            let meters = seconds / pace * 1_000
            return meters.isFinite && meters > 0 ? meters : nil
        case .open:
            return nil
        }
    }

    static func durationSeconds(for target: RunningStepTarget) -> Double? {
        switch target.measure {
        case .time:
            guard let seconds = target.durationSeconds,
                  seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        case .distance:
            guard let meters = target.distanceMeters,
                  meters.isFinite, meters > 0,
                  let pace = target.intensity.paceMinSecondsPerKilometer,
                  pace.isFinite, pace > 0 else { return nil }
            let seconds = meters / 1_000 * pace
            return seconds.isFinite && seconds > 0 ? seconds : nil
        case .open:
            return nil
        }
    }

    static func distanceMeters(for blocks: [WorkoutTemplateBlock]) -> Double? {
        let steps = blocks.expandedForExecution().filter {
            $0.kind == .run || $0.kind == .rest
        }
        guard !steps.isEmpty, steps.count <= 1_000 else { return nil }
        var meters = 0.0
        for step in steps {
            if let distance = step.distanceMeters, distance > 0,
               distance.isFinite {
                meters += distance
            } else if let duration = step.durationSeconds, duration > 0,
                      duration.isFinite,
                      let pace = step.targetPaceSecondsPerKilometer,
                      pace > 0, pace.isFinite {
                meters += duration / pace * 1_000
            } else {
                return nil
            }
        }
        return meters.isFinite && meters > 0 ? meters : nil
    }
}

/// Individual effort plus its following recovery (pause 3 belongs to drag 3).
/// Legacy templates keep using the block defaults when no override is present.
struct RunningRepetitionOverride: Codable, Hashable {
    var repetition: Int
    var work: RunningStepTarget? = nil
    var recovery: RunningStepTarget? = nil
    var skipRecovery: Bool? = nil
    var ghostPaceSecondsPerKilometer: Double? = nil
    var notes: String? = nil
}

struct RunningWorkoutBlock: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: RunningBlockKind
    var title: String
    var repetitions: Int
    var work: RunningStepTarget
    var recovery: RunningStepTarget?
    var notes: String?
    var repetitionOverrides: [RunningRepetitionOverride]? = nil
    // Planning-only cue for this phase. Playback changes require explicit
    // runtime authorization and must not start music from a preview.
    var spotifyPlaylist: SpotifyPlaylistReference? = nil

    func override(for repetition: Int) -> RunningRepetitionOverride? {
        repetitionOverrides?.first { $0.repetition == repetition }
    }

    func resolvedWork(at repetition: Int) -> RunningStepTarget {
        override(for: repetition)?.work ?? work
    }

    func resolvedRecovery(after repetition: Int) -> RunningStepTarget? {
        guard repetition < max(repetitions, 1),
              override(for: repetition)?.skipRecovery != true else { return nil }
        return override(for: repetition)?.recovery ?? recovery
    }

    init(
        id: UUID = UUID(),
        kind: RunningBlockKind,
        title: String,
        repetitions: Int = 1,
        work: RunningStepTarget,
        recovery: RunningStepTarget? = nil,
        notes: String? = nil,
        repetitionOverrides: [RunningRepetitionOverride]? = nil,
        spotifyPlaylist: SpotifyPlaylistReference? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.repetitions = repetitions
        self.work = work
        self.recovery = recovery
        self.notes = notes
        self.repetitionOverrides = repetitionOverrides
        self.spotifyPlaylist = spotifyPlaylist
    }
}

struct RunningWorkoutTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var type: RunningWorkoutType
    var summary: String
    var blocks: [RunningWorkoutBlock]
    var routeID: UUID?
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date
    var sharedSourceOwnerID: UUID? = nil
    var sharedSourceWorkoutID: UUID? = nil

    /// Virtual interval pacer, active only during work reps (not recovery).
    /// This is independent of route-matched Ghost Race.
    var intervalGhostPaceSecondsPerKilometer: Double? = nil
    /// When enabled, Ghost matches measured reduced running pace in recoveries
    /// instead of remaining hidden. Recovery never causes a pace penalty.
    var intervalGhostFollowRecovery: Bool? = nil
    var intervalGhostRecoverySlowdownPercent: Int? = nil
    /// Optional instructions set before the workout for Audio Coach.
    var coachBrief: String? = nil
    /// Nil preserves automatic progression for existing workout templates.
    /// When false, timed running phases advance via the athlete's Next action.
    var autoAdvanceTimedSteps: Bool? = nil
    /// Default: finish warm-up, then explicitly start the main section.
    var autoStartMainAfterWarmup: Bool? = nil
    /// Optional per-interval spoken progress, independent of global distance/time cues.
    var intervalCoachCueEverySeconds: TimeInterval? = nil
    /// One spoken heads-up this many seconds before a timed interval ends.
    var intervalCoachCountdownSeconds: TimeInterval? = nil

    /// Recalculates from every resolved drag and pause, including overrides.
    private var estimateSteps: [RunningStepTarget] {
        blocks.flatMap { block in
            (1...min(max(block.repetitions, 1), 60)).flatMap { repetition in
                [block.resolvedWork(at: repetition)] +
                    (block.resolvedRecovery(after: repetition).map { [$0] } ?? [])
            }
        }
    }

    var estimatedDistanceMeters: Double? {
        let steps = estimateSteps
        guard !steps.isEmpty, steps.count <= 1_000 else { return nil }
        var total = 0.0
        for step in steps {
            guard let meters = ATHLTHRunningEstimate.distanceMeters(for: step)
            else { return nil }
            total += meters
        }
        return total.isFinite && total > 0 ? total : nil
    }

    var estimatedDurationSeconds: TimeInterval? {
        let steps = estimateSteps
        guard !steps.isEmpty, steps.count <= 1_000 else { return nil }
        var total = 0.0
        for step in steps {
            guard let seconds = ATHLTHRunningEstimate.durationSeconds(for: step)
            else { return nil }
            total += seconds
        }
        return total.isFinite && total > 0 ? total : nil
    }
}


/// Planning-only duration and distance estimates from the same resolved interval
/// repetitions that the workout/Watch engine uses. No planned value is a
/// measured distance. Unpaced recoveries are stationary unless explicitly
/// given a recovery pace; open-ended blocks keep totals unknown.
enum ATHLTHRunningPlanningEstimate {
    static func totals(
        for workouts: [RunningWorkoutTemplate],
        defaultPaceSecondsPerKilometer: Double = 360
    ) -> (distanceMeters: Double?, durationSeconds: Double?) {
        guard !workouts.isEmpty,
              defaultPaceSecondsPerKilometer.isFinite,
              defaultPaceSecondsPerKilometer > 0
        else { return (nil, nil) }

        var meters = 0.0
        var seconds = 0.0
        var completeDistance = true
        var completeDuration = true
        var count = 0

        for workout in workouts {
            for block in workout.blocks {
                let repetitions = min(max(block.repetitions, 1), 60)
                for repetition in 1...repetitions {
                    var steps: [(target: RunningStepTarget, isRecovery: Bool)] = [
                        (block.resolvedWork(at: repetition), block.kind == .recovery)
                    ]
                    if let recovery = block.resolvedRecovery(after: repetition) {
                        steps.append((recovery, true))
                    }
                    for step in steps {
                        count += 1
                        guard count <= 1_000 else { return (nil, nil) }
                        let explicitPace = step.target.intensity.paceMinSecondsPerKilometer
                        let pace = explicitPace ?? defaultPaceSecondsPerKilometer
                        guard pace.isFinite, pace > 0 else { return (nil, nil) }

                        switch step.target.measure {
                        case .time:
                            guard let duration = step.target.durationSeconds,
                                  duration.isFinite, duration > 0 else {
                                completeDistance = false
                                completeDuration = false
                                continue
                            }
                            seconds += duration
                            if !step.isRecovery || explicitPace != nil {
                                meters += duration / pace * 1_000
                            }
                        case .distance:
                            guard let distance = step.target.distanceMeters,
                                  distance.isFinite, distance > 0 else {
                                completeDistance = false
                                completeDuration = false
                                continue
                            }
                            meters += distance
                            seconds += distance / 1_000 * pace
                        case .open:
                            completeDistance = false
                            completeDuration = false
                        }
                    }
                }
            }
        }
        return (
            completeDistance && meters > 0 ? meters : nil,
            completeDuration && seconds > 0 ? seconds : nil
        )
    }
}

enum ExerciseLibrarySource: String, Codable, Hashable {
    case athlthCatalog
    case repDB
    case custom
}

struct ExerciseLibraryEntry: Identifiable, Hashable {
    let id: UUID
    let exercise: Exercise
    let source: ExerciseLibrarySource
    let sourceIdentifier: String?
    let summary: String?
    let tips: [String]
    let category: String?
    let difficulty: String?
    let bodyPart: String?
    let imageStartURL: URL?
    let imagePeakURL: URL?

    var name: String { exercise.displayName }
    var canonicalName: String { exercise.name }
}


// MARK: - Coach plan adaptation proposals

enum CoachPlanChangeKind: String, Codable, CaseIterable, Hashable {
    case moveWorkout
    case replaceWorkout
    case adjustDuration
    case adjustIntensity
    case addRecovery
    case removeWorkout
}

enum CoachPlanProposalStatus: String, Codable, Hashable {
    case proposed
    case accepted
    case dismissed
    case reverted
}

struct CoachPlanChange: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: CoachPlanChangeKind
    let sessionID: UUID?
    let sourceDate: Date?
    let targetDate: Date?
    let title: String
    let summary: String
    let reason: String
    let replacementTitle: String?
    let durationMinutes: Int?
    let intensityNote: String?

    init(
        id: UUID = UUID(),
        kind: CoachPlanChangeKind,
        sessionID: UUID? = nil,
        sourceDate: Date? = nil,
        targetDate: Date? = nil,
        title: String,
        summary: String,
        reason: String,
        replacementTitle: String? = nil,
        durationMinutes: Int? = nil,
        intensityNote: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sessionID = sessionID
        self.sourceDate = sourceDate
        self.targetDate = targetDate
        self.title = title
        self.summary = summary
        self.reason = reason
        self.replacementTitle = replacementTitle
        self.durationMinutes = durationMinutes
        self.intensityNote = intensityNote
    }
}

struct CoachPlanChangeProposal: Identifiable, Codable, Hashable {
    let id: UUID
    let planID: UUID
    let planVersion: Int
    let createdAt: Date
    var status: CoachPlanProposalStatus
    let headline: String
    let rationale: String
    let changes: [CoachPlanChange]

    init(
        id: UUID = UUID(),
        planID: UUID,
        planVersion: Int,
        createdAt: Date = Date(),
        status: CoachPlanProposalStatus = .proposed,
        headline: String,
        rationale: String,
        changes: [CoachPlanChange]
    ) {
        self.id = id
        self.planID = planID
        self.planVersion = planVersion
        self.createdAt = createdAt
        self.status = status
        self.headline = headline
        self.rationale = rationale
        self.changes = changes
    }

    func isStillValid(for plan: TrainingPlan) -> Bool {
        plan.id == planID && plan.version == planVersion
    }
}


struct CoachPlanAdaptationRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var proposal: CoachPlanChangeProposal
    let planBefore: TrainingPlan
    let planAfter: TrainingPlan
    let appliedAt: Date
    var revertedAt: Date?

    init(
        id: UUID = UUID(),
        proposal: CoachPlanChangeProposal,
        planBefore: TrainingPlan,
        planAfter: TrainingPlan,
        appliedAt: Date = Date(),
        revertedAt: Date? = nil
    ) {
        self.id = id
        self.proposal = proposal
        self.planBefore = planBefore
        self.planAfter = planAfter
        self.appliedAt = appliedAt
        self.revertedAt = revertedAt
    }
}


// Exercise-level warm-up is represented using the existing per-set targets.
// This keeps saved plans, invites and Watch workouts backward compatible.
extension PlannedExercise {
    var isWarmUpExercise: Bool {
        let targets = resolvedSetTargets
        return !targets.isEmpty && targets.allSatisfy {
            $0.isWarmUp == true || $0.setType == .warmUp
        }
    }

    mutating func setEntireExerciseWarmUp(_ warmUp: Bool) {
        setTargets = resolvedSetTargets.map { target in
            var updated = target
            updated.isWarmUp = warmUp
            updated.setType = warmUp ? .warmUp : .work
            return updated
        }
    }
}


/// Static bodyweight holds are measured in seconds, not repetitions.
enum StrengthTimedBodyweightDefaults {
    static let durationSeconds = 30

    static func isBodyweightHold(_ name: String) -> Bool {
        let normalized = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "nb_NO")
        ).lowercased().replacingOccurrences(of: "-", with: " ")
        return normalized.contains("hanging l sit") ||
            normalized.contains("l sit hold") ||
            normalized.contains("l sit") ||
            normalized.contains("plank") ||
            normalized.contains("hollow hold")
    }
}

/// Cardio movements inside Strength use one Watch workout and preserve
/// per-set cardio metrics. Do not start a separate HealthKit running workout.
enum StrengthCardioExercisePolicy {
    static func isCardio(_ name: String) -> Bool {
        let value = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "nb_NO")
        ).lowercased()
        // A rowing *machine* is cardio, but resistance rows such as
        // "Dumbbell Rowing" and "Seated Cable Row" remain strength.
        // Broad substring "rowing" previously misclassified them and
        // excluded real lifting volume / personal records.
        let resistanceRow = [
            "cable", "seated", "bench", "chest supported", "dumbbell",
            "barbell", "landmine", "low row", "single arm", "one arm"
        ].contains { token in value.contains(token) }
        // A seated cable/weight-stack "row machine" is resistance training,
        // whereas an ergometer is cardio. Generic "rowing" alone is only
        // cardio when it is the whole exercise label.
        if resistanceRow { return false }
        return StrengthTreadmillWarmUpDefaults.isTreadmill(value) ||
            value == "rowing" || value == "roing" ||
            value == "rower" || value == "row machine" ||
            value.hasPrefix("rowing machine") ||
            value.contains("rowing erg") || value.contains("row erg") ||
            value.contains("rowerg") || value.contains("romaskin") ||
            value.contains("roapparat") || value.contains("rowing cardio") ||
            value.contains("concept2") || value.contains("concept 2")
    }
}

// Keep treadmill warm-ups consistent whether an exercise is added before
// starting Strength or during an active Strength workout. A new choice must
// always show its editable setup; these are only the initial values.
enum StrengthTreadmillWarmUpDefaults {
    static let sets = 1
    static let durationSeconds = 10 * 60

    static func isTreadmill(_ name: String) -> Bool {
        let normalized = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "nb_NO")
        ).lowercased()
        return normalized.contains("treadmill") ||
            normalized.contains("tredemølle") ||
            normalized.contains("tredemolle")
    }

    static func plannedExercise(for exercise: Exercise) -> PlannedExercise {
        let treadmill = isTreadmill(exercise.snapshot.name) ||
            isTreadmill(exercise.snapshot.displayName)
        let bodyweightHold =
            StrengthTimedBodyweightDefaults.isBodyweightHold(exercise.snapshot.name) ||
            StrengthTimedBodyweightDefaults.isBodyweightHold(exercise.snapshot.displayName)
        var planned = PlannedExercise(
            id: UUID(),
            exerciseID: exercise.id,
            embeddedExercise: exercise.snapshot,
            sets: treadmill ? sets : 3,
            reps: treadmill || bodyweightHold ? nil : 8,
            targetWeightKilograms: nil,
            targetRPE: nil,
            restSeconds: treadmill ? 0 : 90,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: StrengthProgressionRule.none
        )
        if treadmill || bodyweightHold {
            planned.targetKind = .time
            planned.targetDurationSeconds = treadmill
                ? durationSeconds : StrengthTimedBodyweightDefaults.durationSeconds
            if treadmill {
                planned.setEntireExerciseWarmUp(true)
            }
        }
        return planned
    }
}
