import SwiftUI

enum GhostTargetTimeFormatter {
    static func parse(
        _ text: String
    ) -> TimeInterval? {
        let cleaned =
            text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !cleaned.isEmpty else {
            return nil
        }

        let parts =
            cleaned.split(
                separator: ":",
                omittingEmptySubsequences: false
            )

        guard (1...3).contains(parts.count),
              parts.allSatisfy({
                  Int($0) != nil
              })
        else {
            return nil
        }

        let values =
            parts.compactMap {
                Int($0)
            }

        let total: Int

        switch values.count {
        case 1:
            total =
                values[0] * 60
        case 2:
            guard values[1] < 60 else {
                return nil
            }
            total =
                values[0] * 60 +
                values[1]
        case 3:
            guard values[1] < 60,
                  values[2] < 60
            else {
                return nil
            }
            total =
                values[0] * 3_600 +
                values[1] * 60 +
                values[2]
        default:
            return nil
        }

        guard total >= 60 else {
            return nil
        }

        return TimeInterval(total)
    }

    static func string(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let remainder =
            total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            remainder
        )
    }

    static func paceText(
        distanceKilometers: Double,
        duration: TimeInterval
    ) -> String {
        guard distanceKilometers > 0,
              duration > 0
        else {
            return "— /km"
        }

        let secondsPerKilometer =
            duration /
            distanceKilometers
        let total =
            max(
                Int(
                    secondsPerKilometer
                        .rounded()
                ),
                0
            )

        return String(
            format:
                "%d:%02d /km",
            total / 60,
            total % 60
        )
    }
}

struct TargetGhostRoutePickerView: View {
    @EnvironmentObject private var session:
        AppSessionStore

    var body: some View {
        List {
            Section {
                Text(
                    "Choose a saved route, set the finish time you want, and ATHLTH creates a synthetic ghost that follows the course at the required average pace."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("My routes") {
                if session.savedRoutes.isEmpty {
                    ContentUnavailableView(
                        "No saved routes",
                        systemImage:
                            "map.fill",
                        description: Text(
                            "Create or save a route first."
                        )
                    )
                } else {
                    ForEach(
                        session.savedRoutes
                            .sorted {
                                $0.createdAt >
                                $1.createdAt
                            }
                    ) { route in
                        NavigationLink {
                            TargetGhostSetupView(
                                route: route
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName:
                                        "timer.circle.fill"
                                )
                                .font(.title3)
                                .foregroundStyle(
                                    ATHLTHTheme.vitality
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(route.title)
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )

                                    Text(
                                        String(
                                            format:
                                                "%.2f km",
                                            route
                                                .distanceKilometers
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Target Ghost")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GhostTargetSuggestion: Identifiable {
    let id: String
    let title: String
    let detail: String
    let duration: TimeInterval
    let icon: String
}

struct TargetGhostSetupView: View {
    @Environment(\.dismiss)
    private var dismiss

    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var settings:
        AppSettingsStore
    @EnvironmentObject private var watchConnection:
        AppleWatchConnectionStore
    @EnvironmentObject private var ghostRace:
        GhostRaceStore
    @EnvironmentObject private var health:
        HealthKitManager

    @StateObject private var routeAttempts =
        RouteAttemptStore()
    @StateObject private var publicTrailAttempts =
        PublicTrailAttemptStore()

    let route: TrainingRoute
    var challengeTitle: String? = nil

    @State private var targetTimeText: String
    @State private var starting = false
    @State private var loadingHistory = false
    @State private var errorMessage: String?

    init(
        route: TrainingRoute,
        challengeTitle: String? = nil
    ) {
        self.route = route
        self.challengeTitle = challengeTitle

        let suggested =
            route.expectedTravelTimeSeconds ??
            max(
                route.distanceKilometers * 330,
                5 * 60
            )

        _targetTimeText =
            State(
                initialValue:
                    GhostTargetTimeFormatter
                        .string(suggested)
            )
    }

    private var isPublicTrail: Bool {
        route.routeSource == "openstreetmap" ||
        route.ownerID ==
            PublicTrailRecord.publicSourceOwnerID ||
        route.sharedSourceOwnerID ==
            PublicTrailRecord.publicSourceOwnerID
    }

    private var publicTrailID: UUID {
        route.sharedSourceRouteID ?? route.id
    }

    private var targetDuration:
        TimeInterval? {
        GhostTargetTimeFormatter.parse(
            targetTimeText
        )
    }

    private var historicalAttempts:
        [RouteAttemptRecord] {
        if isPublicTrail {
            return publicTrailAttempts
                .attempts(
                    for: session.profile.userID
                )
        }

        return routeAttempts
            .attempts(
                for: session.profile.userID
            )
    }

    private var qualifyingAttempts:
        [RouteAttemptRecord] {
        historicalAttempts
            .filter(\.leaderboardEligible)
    }

    private var personalBest:
        RouteAttemptRecord? {
        qualifyingAttempts.min {
            $0.durationSeconds <
                $1.durationSeconds
        }
    }

    private var latestAttempt:
        RouteAttemptRecord? {
        historicalAttempts.max {
            $0.startedAt <
                $1.startedAt
        }
    }

    private var historyError: String? {
        isPublicTrail
            ? publicTrailAttempts.errorMessage
            : routeAttempts.errorMessage
    }

    private var smartTargets:
        [GhostTargetSuggestion] {
        var suggestions:
            [GhostTargetSuggestion] = []

        func add(
            id: String,
            title: String,
            detail: String,
            duration: TimeInterval,
            icon: String
        ) {
            let safeDuration =
                max(duration.rounded(), 60)

            guard !suggestions.contains(
                where: {
                    abs(
                        $0.duration -
                        safeDuration
                    ) < 0.5
                }
            )
            else {
                return
            }

            suggestions.append(
                GhostTargetSuggestion(
                    id: id,
                    title: title,
                    detail: detail,
                    duration: safeDuration,
                    icon: icon
                )
            )
        }

        if let personalBest {
            let best =
                personalBest.durationSeconds

            add(
                id: "match-pb",
                title: "Match PB",
                detail:
                    GhostTargetTimeFormatter
                        .string(best),
                duration: best,
                icon: "medal.fill"
            )

            add(
                id: "pb-15",
                title: "PB − 15 sec",
                detail:
                    GhostTargetTimeFormatter
                        .string(best - 15),
                duration: best - 15,
                icon: "bolt.fill"
            )

            add(
                id: "pb-30",
                title: "PB − 30 sec",
                detail:
                    GhostTargetTimeFormatter
                        .string(best - 30),
                duration: best - 30,
                icon: "bolt.circle.fill"
            )

            for percent in [1.0, 2.0, 5.0] {
                let multiplier =
                    1 - percent / 100
                let duration =
                    best * multiplier

                add(
                    id:
                        "pb-\(Int(percent))-percent",
                    title:
                        "\(Int(percent))% faster",
                    detail:
                        GhostTargetTimeFormatter
                            .string(duration),
                    duration: duration,
                    icon:
                        percent >= 5
                            ? "flame.fill"
                            : "speedometer"
                )
            }
        }

        if let latestAttempt {
            let latest =
                latestAttempt.durationSeconds

            add(
                id: "latest-match",
                title: "Match last run",
                detail:
                    GhostTargetTimeFormatter
                        .string(latest),
                duration: latest,
                icon: "clock.arrow.circlepath"
            )

            add(
                id: "latest-30",
                title: "Last run − 30 sec",
                detail:
                    GhostTargetTimeFormatter
                        .string(latest - 30),
                duration: latest - 30,
                icon: "arrow.up.right"
            )

            add(
                id: "latest-60",
                title: "Last run − 1 min",
                detail:
                    GhostTargetTimeFormatter
                        .string(latest - 60),
                duration: latest - 60,
                icon: "arrow.up.right.circle.fill"
            )
        }

        return suggestions
    }

    private var canStart: Bool {
        targetDuration != nil &&
        settings.trainingDeviceProvider ==
            .appleWatch &&
        watchConnection.isReady &&
        !watchConnection
            .workoutLaunchInProgress &&
        !starting
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                targetChoiceCard

                if personalBest != nil ||
                    latestAttempt != nil ||
                    loadingHistory {
                    historyCard
                }

                startButton

                if settings
                    .trainingDeviceProvider !=
                    .appleWatch ||
                    !watchConnection.isReady {
                    Label(
                        "Ghost Race currently requires a connected Apple Watch.",
                        systemImage:
                            "applewatch.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .padding()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .vitality
                        .opacity(0.20)
            )
        )
        .navigationTitle("Target Ghost")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.id) {
            await loadAttemptHistory()
        }
        .alert(
            "Target Ghost",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {}
        } message: {
            Text(
                errorMessage ?? ""
            )
        }
    }

    private var summaryCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 13
            ) {
                HStack {
                    Label(
                        "TARGET GHOST",
                        systemImage:
                            "timer.circle.fill"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .tracking(1.5)
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                    Spacer()

                    if loadingHistory {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(
                    challengeTitle ??
                    route.title
                )
                .font(.title2.bold())

                Text(
                    "Choose exactly how hard your ghost should be. Set any finish time, match a previous run, or make your best effort a little faster."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                HStack(spacing: 18) {
                    Label(
                        String(
                            format:
                                "%.2f km",
                            route
                                .distanceKilometers
                        ),
                        systemImage:
                            "location.fill"
                    )

                    if let targetDuration {
                        Label(
                            GhostTargetTimeFormatter
                                .paceText(
                                    distanceKilometers:
                                        route
                                            .distanceKilometers,
                                    duration:
                                        targetDuration
                                ),
                            systemImage:
                                "gauge.with.dots.needle.50percent"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var targetChoiceCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text("Choose your target")
                        .font(.headline)

                    Text(
                        smartTargets.isEmpty
                            ? "Set the exact finish time you want. Once ATHLTH has a matched attempt on this route, personal targets appear here automatically."
                            : "Use one of your personal targets or enter any finish time."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !smartTargets.isEmpty {
                    ScrollView(
                        .horizontal,
                        showsIndicators: false
                    ) {
                        HStack(spacing: 10) {
                            ForEach(
                                smartTargets
                            ) { suggestion in
                                targetSuggestion(
                                    suggestion
                                )
                            }
                        }
                    }
                }

                VStack(
                    alignment: .leading,
                    spacing: 9
                ) {
                    Text("Exact finish time")
                        .font(
                            .caption
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    TextField(
                        "45:00",
                        text:
                            $targetTimeText
                    )
                    .font(
                        .system(
                            size: 36,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .keyboardType(
                        .numbersAndPunctuation
                    )
                    .textInputAutocapitalization(
                        .never
                    )
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(
                        ATHLTHTheme
                            .surfaceSage,
                        in:
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                    )

                    Text(
                        "Use MM:SS or H:MM:SS."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                quickAdjuster

                if let targetDuration {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text("Required average pace")
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )

                            Text(
                                GhostTargetTimeFormatter
                                    .paceText(
                                        distanceKilometers:
                                            route
                                                .distanceKilometers,
                                        duration:
                                            targetDuration
                                    )
                            )
                            .font(
                                .title3
                                    .weight(.bold)
                            )
                            .monospacedDigit()
                        }

                        Spacer()

                        Image(
                            systemName:
                                "figure.run"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            ATHLTHTheme.vitality
                        )
                    }
                }
            }
        }
    }

    private var quickAdjuster: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text("Fine tune")
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 8) {
                    adjustmentButton(
                        "− 1 min",
                        seconds: -60
                    )
                    adjustmentButton(
                        "− 30 sec",
                        seconds: -30
                    )
                    adjustmentButton(
                        "− 15 sec",
                        seconds: -15
                    )
                    adjustmentButton(
                        "− 5 sec",
                        seconds: -5
                    )
                    adjustmentButton(
                        "+ 15 sec",
                        seconds: 15
                    )
                    adjustmentButton(
                        "+ 30 sec",
                        seconds: 30
                    )
                }
            }
        }
    }

    private var historyCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Your history")
                            .font(.headline)

                        Text(
                            "Matched runs on this course"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if loadingHistory {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let personalBest {
                    historyRow(
                        title: "Personal best",
                        value:
                            GhostTargetTimeFormatter
                                .string(
                                    personalBest
                                        .durationSeconds
                                ),
                        detail:
                            String(
                                format:
                                    "%.0f%% route match",
                                personalBest
                                    .routeMatchPercent
                            ),
                        icon: "medal.fill"
                    )
                }

                if let latestAttempt {
                    if personalBest?.id !=
                        latestAttempt.id {
                        Divider()

                        historyRow(
                            title: "Last run",
                            value:
                                GhostTargetTimeFormatter
                                    .string(
                                        latestAttempt
                                            .durationSeconds
                                    ),
                            detail:
                                latestAttempt
                                    .startedAt
                                    .formatted(
                                        date:
                                            .abbreviated,
                                        time:
                                            .omitted
                                    ),
                            icon:
                                "clock.arrow.circlepath"
                        )
                    }
                }

                if personalBest == nil &&
                    latestAttempt == nil &&
                    !loadingHistory {
                    Text(
                        historyError ??
                        "No matched attempts on this route yet."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            Task {
                await start()
            }
        } label: {
            if starting {
                ProgressView()
                    .frame(
                        maxWidth:
                            .infinity
                    )
            } else {
                HStack {
                    Image(
                        systemName:
                            "figure.run"
                    )

                    Text("Start Target Ghost")

                    Spacer()

                    if let targetDuration {
                        Text(
                            GhostTargetTimeFormatter
                                .string(
                                    targetDuration
                                )
                        )
                        .monospacedDigit()
                    }
                }
                .font(
                    .subheadline
                        .weight(.semibold)
                )
                .frame(
                    maxWidth:
                        .infinity
                )
            }
        }
        .buttonStyle(
            .borderedProminent
        )
        .tint(
            ATHLTHTheme.vitality
        )
        .controlSize(.large)
        .disabled(!canStart)
    }

    private func targetSuggestion(
        _ suggestion:
            GhostTargetSuggestion
    ) -> some View {
        let selected =
            targetDuration.map {
                abs(
                    $0 -
                    suggestion.duration
                ) < 0.5
            } ?? false

        return Button {
            setTarget(
                suggestion.duration
            )
        } label: {
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                Image(
                    systemName:
                        suggestion.icon
                )
                .font(.headline)

                Text(
                    suggestion.title
                )
                .font(
                    .caption
                        .weight(.semibold)
                )

                Text(
                    suggestion.detail
                )
                .font(
                    .caption2
                        .monospacedDigit()
                )
                .foregroundStyle(
                    selected
                        ? Color.white
                            .opacity(0.78)
                        : ATHLTHTheme
                            .mutedText
                )
            }
            .foregroundStyle(
                selected
                    ? Color.white
                    : ATHLTHTheme
                        .primaryText
            )
            .frame(
                width: 126,
                alignment: .leading
            )
            .padding(12)
            .background(
                selected
                    ? ATHLTHTheme
                        .vitality
                    : ATHLTHTheme
                        .surfaceStone,
                in:
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    selected
                        ? Color.clear
                        : ATHLTHTheme.border,
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func adjustmentButton(
        _ title: String,
        seconds: TimeInterval
    ) -> some View {
        Button {
            let base =
                targetDuration ??
                route.expectedTravelTimeSeconds ??
                max(
                    route.distanceKilometers *
                        330,
                    5 * 60
                )

            setTarget(
                max(
                    base + seconds,
                    60
                )
            )
        } label: {
            Text(title)
                .font(
                    .caption
                        .weight(.semibold)
                )
                .foregroundStyle(
                    seconds < 0
                        ? ATHLTHTheme
                            .vitality
                        : ATHLTHTheme
                            .primaryText
                )
                .padding(
                    .horizontal,
                    11
                )
                .frame(height: 34)
                .background(
                    ATHLTHTheme
                        .surfaceStone,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            ATHLTHTheme.border,
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func historyRow(
        title: String,
        value: String,
        detail: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: icon
            )
            .font(.headline)
            .foregroundStyle(
                ATHLTHTheme.vitality
            )
            .frame(
                width: 38,
                height: 38
            )
            .background(
                ATHLTHTheme
                    .vitalitySoft,
                in:
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
            }

            Spacer()

            Text(value)
                .font(
                    .headline
                        .monospacedDigit()
                )
        }
    }

    private func setTarget(
        _ duration: TimeInterval
    ) {
        targetTimeText =
            GhostTargetTimeFormatter
                .string(duration)
    }

    @MainActor
    private func loadAttemptHistory()
        async
    {
        loadingHistory = true
        defer {
            loadingHistory = false
        }

        if isPublicTrail {
            if health
                .hasRequestedAuthorization {
                await publicTrailAttempts
                    .syncHealthAttempts(
                        for: route,
                        trailID:
                            publicTrailID,
                        userID:
                            session
                                .profile
                                .userID,
                        health: health
                    )
            } else {
                await publicTrailAttempts
                    .refresh(
                        trailID:
                            publicTrailID
                    )
            }

            return
        }

        if health.hasRequestedAuthorization {
            await routeAttempts
                .syncHealthAttempts(
                    for: route,
                    userID:
                        session
                            .profile
                            .userID,
                    health: health
                )
        } else {
            await routeAttempts.refresh(
                routeID: route.id
            )
        }
    }

    @MainActor
    private func start() async {
        guard let targetDuration else {
            errorMessage =
                "Enter a valid target finish time."
            return
        }

        starting = true
        defer {
            starting = false
        }

        do {
            try await GhostRaceStartService
                .startTarget(
                    route: route,
                    targetDurationSeconds:
                        targetDuration,
                    ownerID:
                        session.profile.userID,
                    ghostRace:
                        ghostRace,
                    watchConnection:
                        watchConnection,
                    settings:
                        settings
                )

            dismiss()
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
}
