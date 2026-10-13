import Foundation

/// Events and competitive challenges are different workflows, but Club
/// members should discover and browse them in one Activities destination.
enum CommunityGroupActivityCategory: String, CaseIterable, Identifiable {
    case events
    case challenges

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .events:
            ATHLTHLocalization.choose(
                english: "Events", norwegian: "Arrangementer"
            )
        case .challenges:
            ATHLTHLocalization.choose(
                english: "Challenges", norwegian: "Utfordringer"
            )
        }
    }
}
