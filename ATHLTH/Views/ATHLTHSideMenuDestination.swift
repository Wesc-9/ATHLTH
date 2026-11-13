import Foundation

/// iPhone side navigation intentionally exposes deeper ATHLTH tools, not
/// duplicates of the five main tabs. Existing feature views remain canonical.
enum ATHLTHSideMenuDestination: String, Identifiable {
    case home
    case search
    case inbox
    case notifications
    case trainingLibrary
    case myExercises
    case myRoutes
    case myTrainingPlans
    case myWorkouts
    case trainTogether
    case ghostRace
    case challenges
    case arena
    case clubs
    case profile
    case settings

    var id: String { rawValue }
}
