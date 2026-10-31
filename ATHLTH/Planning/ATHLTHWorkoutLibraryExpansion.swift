import Foundation

/// A single-open accordion in the workout catalog: tapping an expanded card
/// closes it; tapping a different card switches to that card.
enum ATHLTHWorkoutLibraryExpansion {
    static func toggled(current: String?, selecting identifier: String) -> String? {
        current == identifier ? nil : identifier
    }
}
