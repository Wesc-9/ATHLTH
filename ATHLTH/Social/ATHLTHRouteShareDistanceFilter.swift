import Foundation

/// Route distance chips are single-choice; thresholds intentionally overlap.
enum ATHLTHRouteShareDistanceFilter: String, CaseIterable, Identifiable {
    case underTwo, twoToFive, overFive, overTen, overTwenty
    var id: String { rawValue }

    var title: String {
        switch self {
        case .underTwo: return "< 2 km"
        case .twoToFive: return "2–5 km"
        case .overFive: return "> 5 km"
        case .overTen: return "> 10 km"
        case .overTwenty: return "> 20 km"
        }
    }

    func matches(_ km: Double) -> Bool {
        guard km.isFinite, km >= 0 else { return false }
        switch self {
        case .underTwo: return km < 2
        case .twoToFive: return km >= 2 && km <= 5
        case .overFive: return km > 5
        case .overTen: return km > 10
        case .overTwenty: return km > 20
        }
    }
}
