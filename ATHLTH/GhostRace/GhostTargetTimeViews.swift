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

enum GhostTargetGoalType: String, CaseIterable, Identifiable {
    case finishTime
    case pace

    var id: String { rawValue }
    var title: String {
        switch self {
        case .finishTime: return ATHLTHLocalization.choose(english: "Finish time", norwegian: "Sluttid")
        case .pace: return ATHLTHLocalization.choose(english: "Pace /km", norwegian: "Tempo per km")
        }
    }
}

enum GhostTargetPaceFormatter {
    static func secondsPerKilometer(from text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              minutes >= 0, seconds >= 0, seconds < 60 else { return nil }
        let value = Double(minutes * 60 + seconds)
        return (120...1_800).contains(value) ? value : nil
    }

    static func text(secondsPerKilometer seconds: TimeInterval) -> String {
        let value = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    static func duration(
        paceSeconds: TimeInterval,
        routeKilometers: Double
    ) -> TimeInterval? {
        guard paceSeconds.isFinite, (120...1_800).contains(paceSeconds),
              routeKilometers.isFinite, routeKilometers > 0 else { return nil }
        return max((paceSeconds * routeKilometers).rounded(), 60)
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
    @EnvironmentObject private var phoneWorkout:
        IPhoneWorkoutStore
    @EnvironmentObject private var ghostRace:
        GhostRaceStore
    @EnvironmentObject private var realtime:
        ATHLTHRealtimeSocialStore
    @EnvironmentObject private var health:
        HealthKitManager

    @StateObject private var routeAttempts =
        RouteAttemptStore()
    @StateObject private var publicTrailAttempts =
        PublicTrailAttemptStore()

    let route: TrainingRoute
    var challengeTitle: String? = nil

    @State private var targetTimeText: String
    @State private var targetPaceText: String
    @State private var goalType: GhostTargetGoalType = .finishTime
    @State private var pacingStrategy: GhostTargetPacingStrategy = .even
    @State private var confirmingStart = false
    @State private var starting = false
    @State private var loadingHistory = false
    @State private var errorMessage: String?
    @State private var captureDevice:
        WorkoutCaptureDevice = .iPhone

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

        _targetTimeText = State(
            initialValue: GhostTargetTimeFormatter.string(suggested)
        )
        _targetPaceText = State(
            initialValue: GhostTargetPaceFormatter.text(
                secondsPerKilometer:
                    suggested / max(route.distanceKilometers, 0.1)
            )
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

    private var targetDuration: TimeInterval? {
        switch goalType {
        case .finishTime:
            return GhostTargetTimeFormatter.parse(targetTimeText)
        case .pace:
            guard let pace = GhostTargetPaceFormatter
                .secondsPerKilometer(from: targetPaceText) else { return nil }
            return GhostTargetPaceFormatter.duration(
                paceSeconds: pace,
                routeKilometers: route.distanceKilometers
            )
        }
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
        guard targetDuration != nil,
              !starting
        else {
            return false
        }

        switch captureDevice {
        case .iPhone:
            return phoneWorkout.active == nil
        case .appleWatch:
            return watchConnection.isReady &&
                !watchConnection
                    .workoutLaunchInProgress
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                targetChoiceCard
                ghostStrategyCard

                if personalBest != nil ||
                    latestAttempt != nil ||
                    loadingHistory {
                    historyCard
                }

                workoutDeviceCard
                startButton
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
        .confirmationDialog(
            ATHLTHLocalization.choose(
                english: "Ready to chase your goal?",
                norwegian: "Klar til å jage målet?"
            ),
            isPresented: $confirmingStart,
            titleVisibility: .visible
        ) {
            Button(ATHLTHLocalization.choose(
                english: "Start Ghost Race",
                norwegian: "Start Ghost Race"
            )) {
                Task { await start() }
            }
        } message: {
            let device = captureDevice == .iPhone ? "iPhone" : "Apple Watch"
            Text("\(route.title) · \(targetDuration.map(GhostTargetTimeFormatter.string) ?? "—") · \(pacingStrategy.title) · \(device)")
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

                Picker(
                    ATHLTHLocalization.choose(
                        english: "Goal type", norwegian: "Måltype"
                    ),
                    selection: $goalType
                ) {
                    ForEach(GhostTargetGoalType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if goalType == .pace {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(ATHLTHLocalization.choose(
                            english: "Desired pace", norwegian: "Ønsket tempo"
                        ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        HStack(spacing: 12) {
                            paceStepButton(-5)
                            TextField("5:00", text: $targetPaceText)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.center)
                                .monospacedDigit()
                                .padding(12)
                                .background(ATHLTHTheme.surfaceSage,
                                            in: RoundedRectangle(cornerRadius: 16))
                            Text("/km")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            paceStepButton(5)
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "The finish time updates automatically from the course length.",
                            norwegian: "Sluttiden beregnes automatisk ut fra rutelengden."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                VStack(
                    alignment: .leading,
                    spacing: 9
                ) {
                    Text(ATHLTHLocalization.choose(
                        english: "Exact finish time",
                        norwegian: "Ønsket sluttid"
                    ))
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

                    Text(ATHLTHLocalization.choose(
                        english: "Use MM:SS or H:MM:SS.",
                        norwegian: "Bruk MM:SS eller T:MM:SS."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                quickAdjuster
                }

                if let duration = targetDuration {
                    Label(
                        ATHLTHLocalization.format(
                            english: "Estimated finish: %@",
                            norwegian: "Beregnet sluttid: %@",
                            GhostTargetTimeFormatter.string(duration)
                        ),
                        systemImage: "flag.checkered"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }

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

    private func paceStepButton(_ step: Int) -> some View {
        Button {
            let current = GhostTargetPaceFormatter.secondsPerKilometer(
                from: targetPaceText
            ) ?? 300
            let next = min(max(current + Double(step), 120), 1_800)
            targetPaceText = GhostTargetPaceFormatter.text(
                secondsPerKilometer: next
            )
        } label: {
            Image(systemName: step < 0 ? "minus" : "plus")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 36, height: 36)
                .background(ATHLTHTheme.surfaceStone, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step < 0 ? "Reduser tempo" : "Øk tempo")
    }

    private var ghostStrategyCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(ATHLTHLocalization.choose(
                    english: "Ghost strategy",
                    norwegian: "Ghost-strategi"
                ))
                .font(.headline)
                Text(ATHLTHLocalization.choose(
                    english: "Choose how your ghost spreads its pace over the route.",
                    norwegian: "Velg hvordan Ghosten fordeler tempoet gjennom løypa."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 7) {
                    ForEach(GhostTargetPacingStrategy.allCases) { strategy in
                        Button {
                            pacingStrategy = strategy
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: strategy.icon)
                                    Spacer(minLength: 2)
                                    if pacingStrategy == strategy {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                Text(strategy.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(2)
                                Text(strategy.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                            .padding(10)
                            .background(
                                pacingStrategy == strategy
                                    ? ATHLTHTheme.accentSoft
                                    : ATHLTHTheme.surfaceStone,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        pacingStrategy == strategy
                                            ? ATHLTHTheme.accentDeep : ATHLTHTheme.border,
                                        lineWidth: pacingStrategy == strategy ? 1.4 : 0.6
                                    )
                            }
                        }
                        .buttonStyle(.plain)
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

    private var workoutDeviceCard: some View {
        QuickStartWorkoutDeviceCard(
            selection: $captureDevice,
            watchConnected:
                watchConnection.isReady &&
                !watchConnection
                    .workoutLaunchInProgress,
            iPhoneEnabled:
                phoneWorkout.active == nil,
            iPhoneSubtitle:
                phoneWorkout.active == nil
                    ? ATHLTHLocalization.choose(
                        english:
                            "Record the Target Ghost with iPhone GPS, Route Guardian and live Ghost comparison.",
                        norwegian:
                            "Registrer Target Ghost med GPS på iPhone, Route Guardian og live Ghost-sammenligning."
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Finish the active iPhone workout before starting Target Ghost.",
                        norwegian:
                            "Fullfør den aktive iPhone-økten før du starter Target Ghost."
                    )
        )
    }

    private var startButton: some View {
        Button {
            Task {
                confirmingStart = true
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
        targetTimeText = GhostTargetTimeFormatter.string(duration)
        let pace = duration / max(route.distanceKilometers, 0.1)
        targetPaceText = GhostTargetPaceFormatter.text(
            secondsPerKilometer: pace
        )
        goalType = .finishTime
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
            realtime.selectLiveGhost(nil)

            try await GhostRaceStartService
                .startTarget(
                    route: route,
                    targetDurationSeconds: targetDuration,
                    strategy: pacingStrategy,
                    ownerID:
                        session.profile.userID,
                    ghostRace:
                        ghostRace,
                    watchConnection:
                        watchConnection,
                    phoneWorkout:
                        phoneWorkout,
                    captureDevice:
                        captureDevice,
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
