import Foundation

enum ATHLTHTrainNavigationRequest: Identifiable {
    case today
    case plan
    case workout(planID: UUID, workoutID: UUID)
    // iPad Studio shortcuts reuse Train's existing validated launch actions.
    case startPlannedWorkout(planID: UUID, workoutID: UUID)
    case sendPlannedWorkoutToWatch(planID: UUID, workoutID: UUID)
    case delayPlannedWorkout(planID: UUID, workoutID: UUID, seconds: TimeInterval)
    case startPlannedWorkout(planID: UUID, workoutID: UUID)
    case sendPlannedWorkoutToWatch(planID: UUID, workoutID: UUID)
    case startPlannedWorkoutAfter(planID: UUID, workoutID: UUID, seconds: TimeInterval)
    case quick(WorkoutKind)
    case customQuick
    case ghost
    case library
    case personalLibrary(ATHLTHPersonalLibrarySection)

    var id: String {
        switch self {
        case .today:
            return "today"
        case .plan:
            return "plan"
        case let .workout(planID, workoutID):
            return "workout:\(planID.uuidString):\(workoutID.uuidString)"
        case let .startPlannedWorkout(planID, workoutID):
            return "start:\(planID.uuidString):\(workoutID.uuidString)"
        case let .sendPlannedWorkoutToWatch(planID, workoutID):
            return "send-watch:\(planID.uuidString):\(workoutID.uuidString)"
        case let .delayPlannedWorkout(planID, workoutID, seconds):
            return "delay:\(planID.uuidString):\(workoutID.uuidString):\(seconds)"
        case let .startPlannedWorkout(planID, workoutID):
            return "start:\(planID.uuidString):\(workoutID.uuidString)"
        case let .sendPlannedWorkoutToWatch(planID, workoutID):
            return "watch:\(planID.uuidString):\(workoutID.uuidString)"
        case let .startPlannedWorkoutAfter(planID, workoutID, seconds):
            return "delayed:\(planID.uuidString):\(workoutID.uuidString):\(Int(seconds))"
        case let .quick(kind):
            return "quick:\(kind.title)"
        case .customQuick:
            return "quick:custom"
        case .ghost:
            return "ghost"
        case .library:
            return "library"
        case let .personalLibrary(section):
            return "personalLibrary:\(section.rawValue)"
        }
    }
}
