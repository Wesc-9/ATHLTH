import Foundation

/// Pure routing decision for an alert's two independent output channels.
/// A blocked or unavailable voice must never consume an otherwise permitted
/// safety haptic, and a voice-only setting must not vibrate unexpectedly.
struct ATHLTHCoachAlertChannels: Equatable {
    let voice: Bool
    let haptic: Bool

    static func resolve(
        delivery: WatchAlertDelivery,
        voiceEnabled: Bool,
        hapticsEnabled: Bool,
        hapticPermittedByPriority: Bool
    ) -> ATHLTHCoachAlertChannels {
        ATHLTHCoachAlertChannels(
            voice: delivery.usesVoice && voiceEnabled,
            haptic: delivery.usesHaptics &&
                hapticsEnabled &&
                hapticPermittedByPriority
        )
    }
}
