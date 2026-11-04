import Foundation

/// The four existing personal library collections reachable from the iPhone side menu.
enum ATHLTHPersonalLibrarySection: String, Hashable, Identifiable {
    case exercises
    case routes
    case trainingPlans
    case workouts

    var id: String { rawValue }
}
