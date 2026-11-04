import Foundation

/// Destinations supported by ATHLTH's Home side navigation.
/// Route through the existing root tabs and training request engine.
enum ATHLTHSideMenuDestination: String, Identifiable {
    case home
    case calendar
    case train
    case plans
    case insights
    case explore
    case community
    case profile
    case settings

    var id: String { rawValue }
}
