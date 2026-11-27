import AppIntents
import Foundation

enum ATHLTHWatchActionWorkout: String, AppEnum {
    case running
    case walking
    case strength

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Workout" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .running: DisplayRepresentation(title: "Running", subtitle: "Outdoor run"),
            .walking: DisplayRepresentation(title: "Walking", subtitle: "Outdoor walk"),
            .strength: DisplayRepresentation(title: "Strength", subtitle: "Free strength")
        ]
    }

    var kind: WatchWorkoutKind {
        switch self {
        case .running: return .running
        case .walking: return .walking
        case .strength: return .strength
        }
    }
}

private enum ATHLTHWatchActionButtonError: LocalizedError {
    case authorization
    case unavailable

    var errorDescription: String? {
        switch self {
        case .authorization:
            return ATHLTHLocalization.choose(
                english: "Open ATHLTH and start a workout to review Health permissions first.",
                norwegian: "Åpne ATHLTH og start en økt for å godkjenne helsetilgang først."
            )
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "A workout could not be started. Check ATHLTH for an active workout.",
                norwegian: "Økten kunne ikke startes. Sjekk om du har en aktiv økt i ATHLTH."
            )
        }
    }
}

/// Hardware start uses the same admission, ownership and HealthKit recorder
/// as tapping a Quick Start tile; never creates an independent HK session.
struct ATHLTHWatchStartWorkoutIntent: StartWorkoutIntent {
    static var title: LocalizedStringResource { "Start ATHLTH Workout" }
    static var suggestedWorkouts: [Self] {
        [Self(style: .running), Self(style: .walking), Self(style: .strength)]
    }

    @Parameter(title: "Workout")
    var workoutStyle: ATHLTHWatchActionWorkout

    init() { workoutStyle = .running }
    init(style: ATHLTHWatchActionWorkout) { workoutStyle = style }

    var displayRepresentation: DisplayRepresentation {
        ATHLTHWatchActionWorkout.caseDisplayRepresentations[workoutStyle] ??
            DisplayRepresentation(title: "Workout")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = WatchWorkoutManager.shared
        guard manager.canAcceptPreparedWorkout() else { throw ATHLTHWatchActionButtonError.unavailable }
        guard await manager.actionButtonAuthorizationReady() else { throw ATHLTHWatchActionButtonError.authorization }
        await manager.start(kind: workoutStyle.kind)
        guard manager.state == .running, manager.kind == workoutStyle.kind else {
            throw ATHLTHWatchActionButtonError.unavailable
        }
        return .result()
    }
}

/// Use the existing guarded manual-advance policy; a repeated press must
/// never skip an automatically advancing interval or end the workout.
struct ATHLTHWatchNextWorkoutActionIntent: AppIntent {
    static var title: LocalizedStringResource { "Next interval or lap" }

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = WatchWorkoutManager.shared
        guard manager.state == .running,
              manager.kind == .running || manager.kind == .walking else { return .result() }
        if manager.currentStructuredRunningStep != nil {
            manager.advanceStructuredRunningWorkoutManually()
        } else {
            manager.markLap()
        }
        return .result()
    }
}

struct ATHLTHWatchPauseWorkoutIntent: PauseWorkoutIntent {
    static var title: LocalizedStringResource { "Pause ATHLTH Workout" }

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchWorkoutManager.shared.pause()
        return .result()
    }
}

struct ATHLTHWatchResumeWorkoutIntent: ResumeWorkoutIntent {
    static var title: LocalizedStringResource { "Resume ATHLTH Workout" }

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchWorkoutManager.shared.resume()
        return .result()
    }
}

@MainActor
enum ATHLTHWatchActionButtonBridge {
    static func donateNextActionIfActive() async {
        let manager = WatchWorkoutManager.shared
        guard manager.state == .running,
              manager.kind == .running || manager.kind == .walking else { return }
        let start = ATHLTHWatchStartWorkoutIntent(style: manager.kind == .running ? .running : .walking)
        try? await start.donate(result: .result(actionButtonIntent: ATHLTHWatchNextWorkoutActionIntent()))
    }
}
