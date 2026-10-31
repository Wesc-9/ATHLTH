import Foundation

/// Optional preparation before following a saved outdoor route.
/// The shared running-step engine owns the timer and all transitions.
struct ATHLTHRouteWarmupConfiguration: Codable, Hashable {
    var enabled = false
    /// Zero means untimed: the runner decides when to start the route.
    var durationMinutes = 10
    var autoStartMain = true

    static let disabled = ATHLTHRouteWarmupConfiguration()

    var startsMainAutomatically: Bool {
        enabled && durationMinutes > 0 && autoStartMain
    }

    func runningTransfer(
        title: String,
        routeAlerts: WatchRouteAlertConfiguration,
        autoPauseEnabled: Bool
    ) -> WatchRunningWorkoutTransfer? {
        guard enabled else { return nil }

        let minutes = durationMinutes == 0
            ? 0 : min(max(durationMinutes, 1), 120)
        let warmup = WatchRunningWorkoutStep(
            id: UUID(),
            title: ATHLTHLocalization.choose(
                english: "Warm-up", norwegian: "Oppvarming"
            ),
            measure: minutes == 0 ? .open : .time,
            distanceMeters: nil,
            durationSeconds: minutes == 0
                ? nil : TimeInterval(minutes * 60),
            intensityText: nil,
            phase: "warmup"
        )
        let main = WatchRunningWorkoutStep(
            id: UUID(),
            title: ATHLTHLocalization.choose(
                english: "Follow route", norwegian: "Følg ruten"
            ),
            measure: .open,
            distanceMeters: nil,
            durationSeconds: nil,
            intensityText: nil,
            phase: "work"
        )
        var transfer = WatchRunningWorkoutTransfer(
            title: title,
            steps: [warmup, main],
            routeAlerts: routeAlerts,
            autoPauseEnabled: autoPauseEnabled
        )
        transfer.autoAdvanceTimedSteps = true
        transfer.autoStartMainAfterWarmup = startsMainAutomatically
        transfer.deferRouteUntilMain = true
        return transfer
    }
}
