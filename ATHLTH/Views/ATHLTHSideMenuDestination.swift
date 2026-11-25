import Foundation

/// Shared navigation identifiers; the phone drawer exposes only its static
/// approved shortcuts. Existing feature views remain canonical.
enum ATHLTHSideMenuDestination: String, Identifiable {
    case home
    case trainNow
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

    // Only these shortcuts are displayed in the iPhone drawer. Other
    // destinations remain valid for legacy links and iPad navigation.
    static let phoneUtilityRows: [Self] = [.search, .notifications, .inbox]
    static let phonePrimaryRows: [Self] = [.trainNow, .trainingLibrary, .clubs, .arena]
}
