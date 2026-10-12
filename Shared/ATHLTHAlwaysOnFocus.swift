import Foundation

/// Read-only Always-On priorities. Keeps phase decisions outside SwiftUI,
/// so Watch and iPhone can test the same rules without starting a workout.
enum ATHLTHAlwaysOnFocus: Equatable {
    case strengthRest
    case strengthTime
    case strengthReps
    case strengthComplete
    case intervalTime
    case intervalDistance
    case intervalOpen
    case paceAndDistance
    case distanceAndPace
    case elapsed
}

struct ATHLTHAlwaysOnContext {
    var kind: WatchWorkoutKind
    var hasStrengthSession = false
    var isStrengthResting = false
    var isTimedStrengthSet = false
    var isStrengthExerciseComplete = false
    var currentRunningStepMeasure: WatchRunningStepMeasure? = nil
}

enum ATHLTHAlwaysOnFocusResolver {
    static func resolve(_ context: ATHLTHAlwaysOnContext)
        -> ATHLTHAlwaysOnFocus {
        if context.kind == .strength && context.hasStrengthSession {
            if context.isStrengthResting { return .strengthRest }
            if context.isStrengthExerciseComplete { return .strengthComplete }
            if context.isTimedStrengthSet { return .strengthTime }
            return .strengthReps
        }

        if context.kind == .running || context.kind == .walking {
            if let measure = context.currentRunningStepMeasure {
                switch measure {
                case .time: return .intervalTime
                case .distance: return .intervalDistance
                case .open: return .intervalOpen
                }
            }
            return context.kind == .walking
                ? .distanceAndPace : .paceAndDistance
        }

        // Other sports do not pretend to have pace, distance or rep data
        // until that sport's recording/display engine explicitly supports it.
        return .elapsed
    }
}
