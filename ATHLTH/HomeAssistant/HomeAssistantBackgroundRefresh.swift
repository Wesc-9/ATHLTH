import BackgroundTasks
import Foundation

@MainActor
enum ATHLTHHomeAssistantBackgroundRefresh {
    static let identifier =
        "com.wesc9.athlth.home-assistant-refresh"

    static var refreshHandler:
        (@MainActor @Sendable () async -> Bool)?

    private static var registered = false

    static func register() {
        guard !registered else {
            return
        }

        registered =
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier:
                    identifier,
                using: nil
            ) { task in
                guard let refreshTask =
                        task as?
                            BGAppRefreshTask
                else {
                    task.setTaskCompleted(
                        success: false
                    )
                    return
                }

                Task { @MainActor in
                    await handle(
                        refreshTask
                    )
                }
            }
    }

    static func schedule() {
        guard registered else {
            return
        }

        BGTaskScheduler.shared
            .cancel(
                taskRequestWithIdentifier:
                    identifier
            )

        let request =
            BGAppRefreshTaskRequest(
                identifier:
                    identifier
            )
        request.earliestBeginDate =
            Date()
                .addingTimeInterval(
                    15 * 60
                )

        try? BGTaskScheduler.shared
            .submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier:
                identifier
        )
    }

    private static func handle(
        _ task: BGAppRefreshTask
    ) async {
        schedule()

        let work =
            Task { @MainActor in
                guard let refreshHandler
                else {
                    return false
                }

                return await refreshHandler()
            }

        task.expirationHandler = {
            work.cancel()
        }

        let success =
            await work.value &&
            !work.isCancelled

        task.setTaskCompleted(
            success: success
        )
    }
}
