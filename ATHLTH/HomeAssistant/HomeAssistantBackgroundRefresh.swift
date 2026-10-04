import BackgroundTasks
import Foundation

private final class ATHLTHBackgroundRefreshTaskBox:
    @unchecked Sendable {
    let task: BGAppRefreshTask

    init(
        _ task: BGAppRefreshTask
    ) {
        self.task = task
    }
}

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
                using: nil,
                launchHandler:
                    launchTask
            )
    }

    // BGTaskScheduler invokes its launch handler on its own private queue.
    // Keep the system callback itself nonisolated, then hop explicitly to
    // MainActor before touching app stores. Creating this callback inside a
    // MainActor-isolated closure causes Swift 6's executor precondition to
    // trap before the Task hop can run.
    nonisolated private static func launchTask(
        _ task: BGTask
    ) {
        guard let refreshTask =
                task as? BGAppRefreshTask
        else {
            task.setTaskCompleted(
                success: false
            )
            return
        }

        // BGTask is not Sendable. Box the immutable reference explicitly
        // before hopping actors; all actual BGTask interaction then stays on
        // MainActor. This avoids Swift 6's region-isolation send error without
        // weakening isolation for the app stores used by the refresh handler.
        let box =
            ATHLTHBackgroundRefreshTaskBox(
                refreshTask
            )

        Task { @MainActor in
            await handle(
                box.task
            )
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

        installExpirationHandler(
            on: task,
            work: work
        )

        let success =
            await work.value &&
            !work.isCancelled

        task.setTaskCompleted(
            success: success
        )
    }

    // BGTaskScheduler may invoke the expiration callback off-main as well.
    // Build that callback from a nonisolated context so it never inherits
    // MainActor isolation and can safely do the one thread-safe operation
    // it needs: cancel the Task that owns the refresh work.
    nonisolated private static func installExpirationHandler(
        on task: BGTask,
        work: Task<Bool, Never>
    ) {
        task.expirationHandler = {
            work.cancel()
        }
    }
}
