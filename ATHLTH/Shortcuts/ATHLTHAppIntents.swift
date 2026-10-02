import AppIntents

struct ATHLTHRecoveryIntent: AppIntent {
    static let title: LocalizedStringResource =
        "Check ATHLTH recovery"

    static let description = IntentDescription(
        "Hear your latest ATHLTH recovery status."
    )

    func perform() async throws ->
        some IntentResult & ProvidesDialog {
        let snapshot = ATHLTHSurfaceSharedStore.load()

        if let score = snapshot.recoveryScore {
            return .result(
                dialog:
                    "Your ATHLTH recovery is \(score) out of 100. \(snapshot.recoveryState)."
            )
        }

        return .result(
            dialog:
                "ATHLTH is still building your recovery baseline. Open ATHLTH after your latest Health data has synced."
        )
    }
}

struct ATHLTHNextWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource =
        "Check next ATHLTH workout"

    static let description = IntentDescription(
        "Hear the next workout in your ATHLTH training plan."
    )

    func perform() async throws ->
        some IntentResult & ProvidesDialog {
        let snapshot = ATHLTHSurfaceSharedStore.load()

        guard let title = snapshot.nextWorkoutTitle else {
            return .result(
                dialog:
                    "You do not currently have an upcoming workout in ATHLTH."
            )
        }

        if let date = snapshot.nextWorkoutDate {
            let formatted = date.formatted(
                date: .abbreviated,
                time: .shortened
            )

            return .result(
                dialog:
                    "Your next ATHLTH workout is \(title), scheduled for \(formatted)."
            )
        }

        return .result(
            dialog:
                "Your next ATHLTH workout is \(title)."
        )
    }
}

struct ATHLTHGoalIntent: AppIntent {
    static let title: LocalizedStringResource =
        "Check ATHLTH goal"

    static let description = IntentDescription(
        "Hear progress toward your primary ATHLTH goal."
    )

    func perform() async throws ->
        some IntentResult & ProvidesDialog {
        let snapshot = ATHLTHSurfaceSharedStore.load()

        guard let title = snapshot.primaryGoalTitle else {
            return .result(
                dialog:
                    "You do not currently have a primary goal in ATHLTH."
            )
        }

        if let progress = snapshot.primaryGoalProgress {
            let percent = Int(
                (min(max(progress, 0), 1) * 100).rounded()
            )

            return .result(
                dialog:
                    "Your primary ATHLTH goal is \(title). You are \(percent) percent complete."
            )
        }

        return .result(
            dialog:
                "Your primary ATHLTH goal is \(title)."
        )
    }
}

struct ATHLTHAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ATHLTHRecoveryIntent(),
            phrases: [
                "Check my recovery in \(.applicationName)",
                "What's my recovery in \(.applicationName)"
            ],
            shortTitle: "Check recovery",
            systemImageName: "heart.fill"
        )

        AppShortcut(
            intent: ATHLTHNextWorkoutIntent(),
            phrases: [
                "What's my next workout in \(.applicationName)",
                "Check my next workout in \(.applicationName)"
            ],
            shortTitle: "Next workout",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: ATHLTHGoalIntent(),
            phrases: [
                "Check my goal in \(.applicationName)",
                "How is my goal going in \(.applicationName)"
            ],
            shortTitle: "Goal progress",
            systemImageName: "target"
        )
    }
}
