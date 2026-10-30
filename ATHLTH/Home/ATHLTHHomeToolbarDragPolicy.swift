import CoreGraphics

/// A horizontal drag starting on the Home toolbar handle opens to the left
/// and collapses to the right. Vertical gestures are reserved for scrolling.
enum ATHLTHHomeToolbarDragPolicy {
    static func expanded(
        currentlyExpanded: Bool,
        translation: CGSize
    ) -> Bool {
        let horizontal = translation.width
        guard abs(horizontal) >= 36,
              abs(horizontal) > abs(translation.height) * 1.35
        else { return currentlyExpanded }

        // The capsule is trailing-aligned: extending it moves its leading
        // edge to the left, while collapsing it moves that edge rightward.
        return horizontal < 0
    }
}
