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
    case cyclingDistance
    case elapsed
}

struct ATHLTHAlwaysOnContext {
    var kind: WatchWorkoutKind
    var hasStrengthSession = false
    var isStrengthResting = false
    var isTimedStrengthSet = false
    var isStrengthExerciseComplete = false
    var currentRunningStepMeasure: WatchRunningStepMeasure? = nil
    var recordedDistanceMeters: Double = 0
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

        // Cycling may be distance-first when recorded distance exists;
        // other activities never synthesize stroke count, pace or steps.
        if context.kind == .cycling,
           ATHLTHOtherSportLiveResolver.resolve(
               kind: .cycling,
               distanceMeters: context.recordedDistanceMeters
           ) == .measuredDistance {
            return .cyclingDistance
        }
        return .elapsed
    }
}
