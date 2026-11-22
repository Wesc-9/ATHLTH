import Foundation

/// Plans use one ordered recipe; only the active live experience changes.
/// The workout's source ID must remain stable across every motor transition.
enum ATHLTHLiveWorkoutEngine: String, Codable, Hashable {
    case endurance
    case cycling
    case strength
    case recovery
    case mobility
    case instructions

    var title: String {
        switch self {
        case .endurance:
            return ATHLTHLocalization.choose(
                english: "Run / endurance", norwegian: "Løping / utholdenhet")
        case .cycling:
            return ATHLTHLocalization.choose(
                english: "Cycling", norwegian: "Sykling")
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength", norwegian: "Styrke")
        case .recovery:
            return ATHLTHLocalization.choose(
                english: "Recovery", norwegian: "Pause")
        case .mobility:
            return ATHLTHLocalization.choose(
                english: "Mobility", norwegian: "Bevegelighet")
        case .instructions:
            return ATHLTHLocalization.choose(
                english: "Instructions", norwegian: "Veiledning")
        }
    }

    var systemImage: String {
        switch self {
        case .endurance: return "figure.run"
        case .cycling: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .recovery: return "timer"
        case .mobility: return "figure.cooldown"
        case .instructions: return "text.alignleft"
        }
    }

    var nextActionTitle: String {
        switch self {
        case .endurance:
            return ATHLTHLocalization.choose(
                english: "Finish interval & next", norwegian: "Fullfør drag og neste")
        case .cycling:
            return ATHLTHLocalization.choose(
                english: "Finish cycling & next", norwegian: "Fullfør sykling og neste")
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Finish set & next", norwegian: "Fullfør sett og neste")
        case .recovery:
            return ATHLTHLocalization.choose(
                english: "End rest & next", norwegian: "Avslutt pause og neste")
        case .mobility, .instructions:
            return ATHLTHLocalization.choose(
                english: "Next step", norwegian: "Neste del")
        }
    }
}

struct ATHLTHLiveWorkoutRoute: Hashable {
    let workoutID: UUID
    let blockIndex: Int
    let blockID: String
    let engine: ATHLTHLiveWorkoutEngine
    let phase: WorkoutPhaseKind
}

struct ATHLTHLiveWorkoutTransition: Hashable {
    let previous: ATHLTHLiveWorkoutRoute
    let next: ATHLTHLiveWorkoutRoute

    var switchesEngine: Bool {
        previous.engine != next.engine
    }

    /// One planned workout stays one training history item. Switching
    /// controls must not start or save an additional HealthKit session.
    var preservesWorkoutIdentity: Bool {
        previous.workoutID == next.workoutID
    }
}

/// One immutable execution recipe for every creation path (Quick Train,
/// standalone planning, a plan day, or a library workout).
/// This is not a new timer, HealthKit owner or saved exercise graph. Older
/// workouts are projected in memory; the original source and identifiers
/// remain untouched.
struct ATHLTHUniversalWorkoutExecutionRecipe {
    let workoutID: UUID
    let activityCategory: String
    let blocks: [WorkoutTemplateBlock]

    init(workout: PlannedSession) {
        workoutID = workout.id
        activityCategory = ATHLTHUnifiedActivityProfile.category(for: workout)
        blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
    }

    var hasStructuredSteps: Bool { !blocks.isEmpty }

    /// The current stage determines which controls appear, not which
    /// recorder owns the activity. One workout ID survives every transition.
    func activeRoute(at index: Int) -> ATHLTHLiveWorkoutRoute? {
        ATHLTHLiveWorkoutEngineRouter.route(
            workoutID: workoutID, blocks: blocks, index: index
        )
    }

    func transition(after index: Int) -> ATHLTHLiveWorkoutTransition? {
        ATHLTHLiveWorkoutEngineRouter.advance(
            workoutID: workoutID, blocks: blocks, from: index
        )
    }
}

/// Pure routing contract shared by the planner, live views and eventual
/// iPhone/Watch capture coordinator. It never owns a HealthKit session,
/// starts a timer or publishes a second workout.
enum ATHLTHLiveWorkoutEngineRouter {
    static func engine(for block: WorkoutTemplateBlock)
        -> ATHLTHLiveWorkoutEngine {
        ATHLTHWorkoutSportMode.forBlock(block).engine
    }

    static func route(
        workoutID: UUID,
        blocks: [WorkoutTemplateBlock],
        index: Int
    ) -> ATHLTHLiveWorkoutRoute? {
        guard blocks.indices.contains(index) else { return nil }
        let block = blocks[index]
        return ATHLTHLiveWorkoutRoute(
            workoutID: workoutID,
            blockIndex: index,
            blockID: block.id,
            engine: engine(for: block),
            phase: block.resolvedPhase
        )
    }

    /// Capture-aware routing entry point. The read-only UI router must not
    /// silently hand a recording from Watch to iPhone (or vice versa).
    /// A real owner transfer requires a separate explicit capture protocol.
    /// Runtime route validation against the real stores, not a caller-built
    /// projection. Rejects conflicting concurrent checkpoints and never
    /// changes which device owns the HealthKit recording.
    @MainActor
    static func transition(
        from previous: ATHLTHLiveWorkoutRoute,
        to next: ATHLTHLiveWorkoutRoute,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore
    ) throws -> ATHLTHLiveWorkoutTransition? {
        guard let active = try ATHLTHWorkoutSessionFoundation.currentSession(
            phone: phone, strength: strength
        ), active.workoutID == previous.workoutID,
           active.workoutID == next.workoutID else { return nil }
        return transition(from: previous, to: next)
    }

    static func transition(
        from previous: ATHLTHLiveWorkoutRoute,
        to next: ATHLTHLiveWorkoutRoute,
        previousSession: ATHLTHWorkoutSessionState,
        nextSession: ATHLTHWorkoutSessionState
    ) -> ATHLTHLiveWorkoutTransition? {
        guard previous.workoutID == previousSession.workoutID,
              next.workoutID == nextSession.workoutID,
              ATHLTHWorkoutSessionFoundation.preservesRecordingOwnership(
                  previousSession, nextSession
              ) else { return nil }
        return transition(from: previous, to: next)
    }

    /// The original ordered structured recipe is the only valid source
    /// for moving the live cursor. Rest, technique, warmup and cooldown
    /// are normal stages, not new workout recordings. Never skip a stage,
    /// move backwards, or accidentally enter a duplicate/ambiguous block ID.
    static func advance(
        workoutID: UUID,
        blocks: [WorkoutTemplateBlock],
        from index: Int
    ) -> ATHLTHLiveWorkoutTransition? {
        guard let stageDecision = ATHLTHWorkoutStagePolicy.afterStage(
                  at: index, totalStages: blocks.count
              ),
              case .advance(let nextIndex) = stageDecision,
              let previous = route(
                workoutID: workoutID, blocks: blocks, index: index
              ),
              let next = route(
                workoutID: workoutID, blocks: blocks, index: nextIndex
              ),
              !previous.blockID.isEmpty, !next.blockID.isEmpty,
              previous.blockID != next.blockID,
              blocks.filter({ $0.id == previous.blockID }).count == 1,
              blocks.filter({ $0.id == next.blockID }).count == 1
        else { return nil }
        return transition(from: previous, to: next)
    }

    static func transition(
        from previous: ATHLTHLiveWorkoutRoute,
        to next: ATHLTHLiveWorkoutRoute
    ) -> ATHLTHLiveWorkoutTransition? {
        // Moving between two different workout IDs is not a motor switch.
        // It would require an explicitly separate recording lifecycle.
        guard ATHLTHWorkoutSessionFoundation.preservesWorkoutID(
            previous.workoutID, next.workoutID
        ) else { return nil }
        return ATHLTHLiveWorkoutTransition(
            previous: previous,
            next: next
        )
    }
}
