import AppIntents

struct ATHLTHRecoveryIntent: AppIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
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
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
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
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
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

struct ATHLTHOpenCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Open ATHLTH Coach"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ATHLTHShortcutNavigation.coach.enqueue()
        return .result()
    }
}

struct ATHLTHOpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open today's ATHLTH training"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ATHLTHShortcutNavigation.today.enqueue()
        return .result()
    }
}

struct ATHLTHOpenPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Open ATHLTH training plan"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ATHLTHShortcutNavigation.plan.enqueue()
        return .result()
    }
}

struct ATHLTHRunSetupIntent: AppIntent {
    static let title: LocalizedStringResource = "Set up a run"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ATHLTHShortcutNavigation.runSetup.enqueue()
        return .result()
    }
}

struct ATHLTHWalkSetupIntent: AppIntent {
    static let title: LocalizedStringResource = "Set up a walk"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ATHLTHShortcutNavigation.walkSetup.enqueue()
        return .result()
    }
}

struct ATHLTHStrengthSetupIntent: AppIntent {
    static let title: LocalizedStringResource = "Set up strength training"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ATHLTHShortcutNavigation.strengthSetup.enqueue()
        return .result()
    }
}

struct ATHLTHSportSetupIntent: AppIntent {
    static let title: LocalizedStringResource = "Open workout categories"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ATHLTHShortcutNavigation.sportSetup.enqueue()
        return .result()
    }
}

struct ATHLTHAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ATHLTHRunSetupIntent(),
            phrases: ["Set up a run in \(.applicationName)", "Klargjør løping i \(.applicationName)"],
            shortTitle: "Set up run",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: ATHLTHWalkSetupIntent(),
            phrases: ["Set up a walk in \(.applicationName)", "Klargjør gange i \(.applicationName)"],
            shortTitle: "Set up walk",
            systemImageName: "figure.walk"
        )

        AppShortcut(
            intent: ATHLTHStrengthSetupIntent(),
            phrases: ["Set up strength training in \(.applicationName)", "Klargjør styrketrening i \(.applicationName)"],
            shortTitle: "Set up strength",
            systemImageName: "dumbbell"
        )

        AppShortcut(
            intent: ATHLTHSportSetupIntent(),
            phrases: ["Open workout categories in \(.applicationName)", "Åpne treningsformer i \(.applicationName)"],
            shortTitle: "Workout categories",
            systemImageName: "sportscourt"
        )

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

        AppShortcut(
            intent: ATHLTHOpenCoachIntent(),
            phrases: ["Open Coach in \(.applicationName)", "Åpne Coach i \(.applicationName)"],
            shortTitle: "Open Coach",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: ATHLTHOpenTodayIntent(),
            phrases: ["Show today's training in \(.applicationName)", "Vis dagens trening i \(.applicationName)"],
            shortTitle: "Today's training",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: ATHLTHOpenPlanIntent(),
            phrases: ["Open my training plan in \(.applicationName)", "Åpne treningsplanen min i \(.applicationName)"],
            shortTitle: "Training plan",
            systemImageName: "calendar"
        )
    }
}
