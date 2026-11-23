import SwiftUI

/// Scene deactivation is never a user-initiated Back, Done or Discard.
/// UIKit/SwiftUI can write a false/nil presentation binding while the host
/// suspends. Keep the user's selection until they explicitly dismiss it in
/// foreground; the parent remains the sole presentation owner.
enum ATHLTHScenePresentationContinuityPolicy {
    static func acceptsDismissal(sceneIsActive: Bool) -> Bool {
        sceneIsActive
    }
}

extension Binding where Value == Bool {
    func keepingPresentedWhenInactive(
        _ phase: ScenePhase
    ) -> Binding<Bool> {
        Binding(
            get: { wrappedValue },
            set: { next in
                if !next &&
                   !ATHLTHScenePresentationContinuityPolicy.acceptsDismissal(
                       sceneIsActive: phase == .active
                   ) {
                    return
                }
                wrappedValue = next
            }
        )
    }
}

extension Binding {
    func keepingPresentedItemWhenInactive<Wrapped>(
        _ phase: ScenePhase
    ) -> Binding<Wrapped?> where Value == Wrapped? {
        Binding(
            get: { wrappedValue },
            set: { next in
                if next == nil &&
                   !ATHLTHScenePresentationContinuityPolicy.acceptsDismissal(
                       sceneIsActive: phase == .active
                   ) {
                    return
                }
                wrappedValue = next
            }
        )
    }
}
