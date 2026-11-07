import CoreGraphics

/// Only a deliberate left-edge, rightward swipe opens the Home side menu.
/// Vertical scrolling, inward swipes and normal horizontal content gestures
/// must not open the drawer. The gesture is installed on Home's root content
/// rather than on pushed NavigationStack destinations.
enum ATHLTHHomeEdgeSwipePolicy {
    static let leadingEdgeWidth: CGFloat = 30
    static let minimumRightwardTravel: CGFloat = 72

    static func shouldOpen(
        startLocation: CGPoint,
        translation: CGSize
    ) -> Bool {
        guard startLocation.x >= 0,
              startLocation.x <= leadingEdgeWidth,
              translation.width >= minimumRightwardTravel
        else { return false }
        // Require a clearly horizontal drag, not an ordinary page scroll.
        return abs(translation.height) * 1.5 <= translation.width
    }
}
