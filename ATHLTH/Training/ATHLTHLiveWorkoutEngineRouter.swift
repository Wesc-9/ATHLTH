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

/// Pure routing contract shared by the planner, live views and eventual
/// iPhone/Watch capture coordinator. It never owns a HealthKit session,
/// starts a timer or publishes a second workout.
enum ATHLTHLiveWorkoutEngineRouter {
    static func engine(for block: WorkoutTemplateBlock)
        -> ATHLTHLiveWorkoutEngine {
        switch block.kind {
        case .run:
            return .endurance
        case .exercise:
            return .strength
        case .rest:
            return .recovery
        case .note:
            if block.activityTag == "cycling" {
                // Display-only timed cycling phase within the same workout;
                // no invented speed, cadence or separate HealthKit session.
                return .cycling
            }
            if block.wellnessKind != nil {
                return .mobility
            }
            return .instructions
        }
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

    static func transition(
        from previous: ATHLTHLiveWorkoutRoute,
        to next: ATHLTHLiveWorkoutRoute
    ) -> ATHLTHLiveWorkoutTransition? {
        // Moving between two different workout IDs is not a motor switch.
        // It would require an explicitly separate recording lifecycle.
        guard previous.workoutID == next.workoutID else { return nil }
        return ATHLTHLiveWorkoutTransition(
            previous: previous,
            next: next
        )
    }
}
