import CoreGraphics
import Foundation

/// Ephemeral drag hit-test geometry. Scrolling changes frames continuously;
/// those measurements must not invalidate the entire SwiftUI workout tree.
/// The view reads them only when a long-press reorder gesture is active.
final class ATHLTHStudioDragGeometry {
    var rowFrames: [UUID: CGRect] = [:]
    var phaseFrames: [WorkoutPhaseKind: CGRect] = [:]
}
