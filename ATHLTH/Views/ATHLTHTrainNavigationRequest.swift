import Foundation

enum ATHLTHTrainNavigationRequest: Identifiable {
    case today
    case plan
    case workout(planID: UUID, workoutID: UUID)
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
