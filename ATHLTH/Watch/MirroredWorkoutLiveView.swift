import SwiftUI

struct MirroredWorkoutLiveView: View {
    @EnvironmentObject private var mirroring: WorkoutMirroringStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingTreadmillInclineEditor = false
    @State private var treadmillInclineDraft = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    TrainTogetherStatusStrip()

                    if let snapshot = mirroring.snapshot {
                        if ghostRace.reference != nil &&
                            snapshot.kind == .running {
                            GhostRaceLivePanel(
                                snapshot: snapshot
                            )
                            .environmentObject(
                                ghostRace
                            )
                        } else if snapshot.kind ==
                                    .running,
                                  realtime
                                    .selectedLiveGhostSessionID !=
                                    nil {
                            liveGhostRaceCard(
                                snapshot
                            )
                        }

                        if snapshot.kind ==
                            .running {
                            runningDashboard(
                                snapshot
                            )
                        } else {
                            timer(snapshot)

                            HStack(
                                spacing: 12
                            ) {
                                metricCard(
                                    title:
                                        "Heart rate",
                                    value:
                                        snapshot
                                            .heartRate >
                                        0
                                            ? "\(Int(snapshot.heartRate.rounded()))"
                                            : "—",
                                    unit: "bpm",
                                    icon:
                                        "heart.fill"
                                )

                                metricCard(
                                    title:
                                        "Calories",
                                    value:
                                        "\(Int(snapshot.activeCalories.rounded()))",
                                    unit: "kcal",
                                    icon:
                                        "flame.fill"
                                )

                                if snapshot.kind
                                    .supportsDistanceMetric {
                                    metricCard(
                                        title:
                                            "Distance",
                                        value:
                                            String(
                                                format:
                                                    "%.2f",
                                                snapshot
                                                    .distanceMeters /
                                                1000
                                            ),
                                        unit: "km",
                                        icon:
                                            "location.fill"
                                    )
                                }
                            }
                        }

                        if let liveSession =
                            realtime.currentSession,
                           realtime.isSharingLiveLocation {
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(
                                    session: liveSession
                                )
                            } label: {
                                ATHLTHCard {
                                    HStack {
                                        Label(
                                            liveSession.ghostChallengeID ==
                                                nil
                                                ? "Live position"
                                                : "Live Ghost Run",
                                            systemImage:
                                                "location.circle.fill"
                                        )
                                        .font(
                                            .subheadline
                                                .weight(
                                                    .semibold
                                                )
                                        )

                                        Spacer()

                                        Image(
                                            systemName:
                                                "chevron.right"
                                        )
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if snapshot.kind !=
                            .running {
                            ATHLTHCard {
                                HStack {
                                    VStack(
                                        alignment:
                                            .leading,
                                        spacing: 5
                                    ) {
                                        Text(
                                            "Apple Watch"
                                        )
                                        .font(
                                            .headline
                                        )

                                        Text(
                                            mirroring
                                                .connectionText
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }

                                    Spacer()

                                    Label(
                                        statusTitle(
                                            snapshot
                                                .state
                                        ),
                                        systemImage:
                                            statusIcon(
                                                snapshot
                                                    .state
                                            )
                                    )
                                    .font(
                                        .caption
                                            .weight(
                                                .semibold
                                            )
                                    )
                                    .foregroundStyle(
                                        statusColor(
                                            snapshot
                                                .state
                                        )
                                    )
                                }
                            }
                        }

                        if let errorMessage = mirroring.errorMessage {
                            Label(
                                errorMessage,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        controls(snapshot)
                    } else {
                        ContentUnavailableView(
                            "Waiting for Apple Watch",
                            systemImage: "applewatch",
                            description: Text(
                                "Start an ATHLTH workout on Apple Watch to mirror it here."
                            )
                        )
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Live Workout",
                    norwegian: "Live økt"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                if mirroring
                    .hasActiveMirroredWorkout {
                    ToolbarItem(
                        placement:
                            .topBarLeading
                    ) {
                        Button {
                            mirroring
                                .minimizeWorkout()
                        } label: {
                            Image(
                                systemName:
                                    "chevron.down"
                            )
                            .font(
                                .system(
                                    size: 16,
                                    weight:
                                        .semibold
                                )
                            )
                        }
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english:
                                    "Minimize workout",
                                norwegian:
                                    "Legg ned økten"
                            )
                        )
                    }
                }

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    ATHLTHAudioRouteControl(
                        compact: true
                    )
                }
            }
        }
        .sheet(
            isPresented:
                $showingTreadmillInclineEditor
        ) {
            TreadmillInclineEditorView(
                initialValue:
                    treadmillInclineDraft
            ) { value in
                _ = mirroring
                    .sendTreadmillInclinePercent(
                        value
                    )
                treadmillInclineDraft =
                    value
            }
        }
        .interactiveDismissDisabled(mirroring.hasActiveMirroredWorkout)
        .task(
            id: mirroring.snapshot?
                .capturedAt
        ) {
            await syncLivePosition()
        }
        .onAppear {
            mirroring.liveViewDidAppear()
            updateScreenAwakeState()
        }
        .onDisappear {
            mirroring.liveViewDidDisappear()
            ATHLTHWorkoutScreenAwake.set(
                false,
                reason: "watch-mirrored-workout"
            )
        }
        .onChange(
            of:
                mirroring
                    .hasActiveMirroredWorkout
        ) { _, _ in
            updateScreenAwakeState()
        }
        .onChange(
            of: scenePhase
        ) { _, _ in
            updateScreenAwakeState()
        }
    }

    private func updateScreenAwakeState() {
        ATHLTHWorkoutScreenAwake.set(
            mirroring
                .hasActiveMirroredWorkout &&
                scenePhase == .active,
            reason: "watch-mirrored-workout"
        )
    }

    @ViewBuilder
    private func liveGhostRaceCard(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> some View {
        if let session =
                realtime
                    .selectedLiveGhostSession {
            let comparison =
                realtime
                    .liveGhostComparison(
                        ownDistanceMeters:
                            snapshot
                                .distanceMeters,
                        ownElapsedSeconds:
                            snapshot
                                .elapsedTime,
                        ownRouteKey:
                            snapshot
                                .routeComparisonID,
                        ownRouteProgressPercent:
                            snapshot
                                .routeProgressPercent,
                        ownRouteDeviationMeters:
                            snapshot
                                .routeDeviationMeters
                    )

            ATHLTHCard {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text("LIVE GHOST")
                                .font(
                                    .caption2
                                        .weight(.bold)
                                )
                                .tracking(1.5)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .vitality
                                )

                            Text(
                                liveGhostOpponentName(
                                    session
                                )
                            )
                            .font(
                                .headline
                            )
                        }

                        Spacer()

                        Circle()
                            .fill(
                                Color.green
                            )
                            .frame(
                                width: 9,
                                height: 9
                            )

                        Text("LIVE")
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                Color.green
                            )
                    }

                    if let comparison {
                        HStack(
                            alignment: .firstTextBaseline
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(
                                    comparison
                                        .userIsAhead
                                        ? "YOU ARE AHEAD"
                                        : "GHOST IS AHEAD"
                                )
                                .font(
                                    .caption
                                        .weight(.semibold)
                                )
                                .foregroundStyle(
                                    comparison
                                        .userIsAhead
                                        ? ATHLTHTheme
                                            .vitality
                                        : Color.orange
                                )

                                Text(
                                    signedDistanceText(
                                        comparison
                                            .signedDistanceMeters
                                    )
                                )
                                .font(
                                    .system(
                                        size: 34,
                                        weight: .bold,
                                        design:
                                            .rounded
                                    )
                                )
                                .monospacedDigit()
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                            }

                            Spacer()

                            if let seconds =
                                comparison
                                    .estimatedTimeDeltaSeconds {
                                VStack(
                                    alignment: .trailing,
                                    spacing: 3
                                ) {
                                    Text("EST. GAP")
                                        .font(
                                            .caption2
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            .secondary
                                        )

                                    Text(
                                        signedTimeText(
                                            seconds
                                        )
                                    )
                                    .font(
                                        .title3
                                            .weight(.bold)
                                            .monospacedDigit()
                                    )

                                    Text("approx.")
                                        .font(.caption2)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Label(
                                comparison
                                    .isRouteAware
                                    ? "Route matched"
                                    : String(
                                        format:
                                            "%.2f km",
                                        comparison
                                            .opponentDistanceMeters /
                                            1_000
                                    ),
                                systemImage:
                                    comparison
                                        .isRouteAware
                                        ? "point.topleft.down.to.point.bottomright.curvepath"
                                        : "figure.run"
                            )

                            Label(
                                liveGhostFreshness(
                                    comparison
                                        .updatedAt
                                ),
                                systemImage:
                                    "clock"
                            )

                            if comparison
                                .isRouteAware,
                               let own =
                                comparison
                                    .ownRouteProgressPercent,
                               let opponent =
                                comparison
                                    .opponentRouteProgressPercent {
                                Text(
                                    String(
                                        format:
                                            "%.1f%% / %.1f%%",
                                        own,
                                        opponent
                                    )
                                )
                                .monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)

                            Text(
                                "Waiting for the runner's next live position…"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        NavigationLink {
                            ATHLTHLiveWorkoutMapView(
                                session: session
                            )
                        } label: {
                            Label(
                                "Live map",
                                systemImage:
                                    "map.fill"
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.bordered)

                        Button {
                            realtime
                                .selectLiveGhost(
                                    nil
                                )
                        } label: {
                            Label(
                                "Stop Ghost",
                                systemImage:
                                    "xmark.circle"
                            )
                            .font(
                                .caption
                                    .weight(.semibold)
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func liveGhostOpponentName(
        _ session:
            ATHLTHLiveWorkoutSession
    ) -> String {
        social.visibleProfiles
            .first {
                $0.userID ==
                    session.ownerID
            }?
            .resolvedName ??
        social.following
            .first {
                $0.userID ==
                    session.ownerID
            }?
            .resolvedName ??
        session.title
    }

    private func signedDistanceText(
        _ meters: Double
    ) -> String {
        let prefix =
            meters >= 0 ? "+" : "−"
        return String(
            format:
                "%@%.0f m",
            prefix,
            abs(meters)
        )
    }

    private func signedTimeText(
        _ seconds: TimeInterval
    ) -> String {
        let prefix =
            seconds >= 0 ? "+" : "−"
        let absolute =
            abs(seconds)

        if absolute >= 60 {
            let total =
                Int(
                    absolute.rounded()
                )
            return String(
                format:
                    "%@%d:%02d",
                prefix,
                total / 60,
                total % 60
            )
        }

        return String(
            format:
                "%@%.0f s",
            prefix,
            absolute
        )
    }

    private func liveGhostFreshness(
        _ date: Date
    ) -> String {
        let seconds =
            max(
                Int(
                    Date()
                        .timeIntervalSince(
                            date
                        )
                        .rounded()
                ),
                0
            )

        return seconds < 5
            ? "Now"
            : "\(seconds)s ago"
    }

    @ViewBuilder
    private var header: some View {
        if let snapshot = mirroring.snapshot {
            ATHLTHCard {
                HStack(spacing: 14) {
                    Image(systemName: snapshot.kind.systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(ATHLTHTheme.accent.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.kind.title)
                            .font(.title2.weight(.bold))

                        Text("Live from Apple Watch")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Circle()
                        .fill(
                            mirroring.hasActiveMirroredWorkout
                                ? ATHLTHTheme.accent
                                : Color.secondary
                        )
                        .frame(width: 10, height: 10)
                }
            }
        }
    }

    @ViewBuilder
    private func runningDashboard(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> some View {
        VStack(spacing: 12) {
            ATHLTHCard {
                VStack(spacing: 4) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "TIME",
                            norwegian: "TID"
                        )
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .tracking(1.4)
                    .foregroundStyle(
                        .secondary
                    )

                    TimelineView(
                        .periodic(
                            from: .now,
                            by: 1
                        )
                    ) { context in
                        Text(
                            durationText(
                                displayedElapsedTime(
                                    snapshot:
                                        snapshot,
                                    now:
                                        context.date
                                )
                            )
                        )
                        .font(
                            .system(
                                size: 80,
                                weight: .bold,
                                design:
                                    .rounded
                            )
                        )
                        .monospacedDigit()
                        .minimumScaleFactor(
                            0.72
                        )
                        .lineLimit(1)
                        .frame(
                            maxWidth:
                                .infinity
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            HStack(spacing: 12) {
                runningMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "DISTANCE",
                            norwegian:
                                "DISTANSE"
                        ),
                    value:
                        String(
                            format: "%.2f",
                            snapshot
                                .distanceMeters /
                            1_000
                        ),
                    unit: "km"
                )

                runningMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english: "PACE",
                            norwegian: "TEMPO"
                        ),
                    value:
                        runningPaceText(
                            snapshot
                        ),
                    unit: "/km"
                )
            }

            HStack(spacing: 12) {
                runningMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english:
                                "HEART RATE",
                            norwegian:
                                "PULS"
                        ),
                    value:
                        snapshot.heartRate >
                            0
                            ? "\(Int(snapshot.heartRate.rounded()))"
                            : "—",
                    unit: "bpm"
                )

                if let incline =
                        snapshot
                            .treadmillInclinePercent {
                    Button {
                        treadmillInclineDraft =
                            incline
                        showingTreadmillInclineEditor =
                            true
                    } label: {
                        runningMetric(
                            title:
                                ATHLTHLocalization.choose(
                                    english:
                                        "INCLINE",
                                    norwegian:
                                        "STIGNING"
                                ),
                            value:
                                String(
                                    format: "%.1f",
                                    incline
                                ),
                            unit: "%"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        ATHLTHLocalization.choose(
                            english:
                                "Adjust treadmill incline",
                            norwegian:
                                "Juster stigning på tredemøllen"
                        )
                    )
                }
            }

            HStack(spacing: 7) {
                Image(
                    systemName:
                        snapshot
                            .treadmillInclinePercent !=
                            nil
                            ? "figure.run.treadmill"
                            : "applewatch"
                )

                Text(
                    snapshot
                        .treadmillInclinePercent !=
                        nil
                        ? ATHLTHLocalization.choose(
                            english:
                                "Treadmill · live from Apple Watch",
                            norwegian:
                                "Tredemølle · live fra Apple Watch"
                        )
                        : mirroring
                            .connectionText
                )
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )

                Spacer()

                Label(
                    statusTitle(
                        snapshot.state
                    ),
                    systemImage:
                        statusIcon(
                            snapshot.state
                        )
                )
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    statusColor(
                        snapshot.state
                    )
                )
            }
            .foregroundStyle(
                .secondary
            )
            .padding(.horizontal, 4)
        }
    }

    private func runningMetric(
        title: String,
        value: String,
        unit: String
    ) -> some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(title)
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .tracking(1.15)
                    .foregroundStyle(
                        .secondary
                    )

                Spacer(
                    minLength: 3
                )

                Text(value)
                    .font(
                        .system(
                            size: 58,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .minimumScaleFactor(
                        0.65
                    )
                    .lineLimit(1)

                Text(unit)
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        .secondary
                    )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 148,
                alignment: .leading
            )
        }
    }

    private func runningPaceText(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> String {
        if let pace = snapshot.currentPaceSecondsPerKilometer,
           pace.isFinite,
           pace > 0 {
            return paceText(pace)
        }

        // Indoor runs have no GPS speed. Prefer the measured average pace
        // when Watch distance and elapsed time are available.
        return averageRunningPaceText(snapshot)
    }

    private func averageRunningPaceText(
        _ snapshot:
            WatchWorkoutLiveSnapshot
    ) -> String {
        guard snapshot.distanceMeters >=
                20,
              snapshot.elapsedTime > 0
        else {
            return "—"
        }

        let pace =
            snapshot.elapsedTime /
            snapshot.distanceMeters *
            1_000

        guard pace.isFinite,
              pace > 0
        else {
            return "—"
        }

        return paceText(pace)
    }

    private func paceText(
        _ seconds:
            TimeInterval
    ) -> String {
        let total =
            max(
                Int(
                    seconds.rounded()
                ),
                0
            )
        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }

    @ViewBuilder
    private func timer(_ snapshot: WatchWorkoutLiveSnapshot) -> some View {
        ATHLTHCard {
            VStack(spacing: 6) {
                Text("Duration")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        durationText(
                            displayedElapsedTime(
                                snapshot: snapshot,
                                now: context.date
                            )
                        )
                    )
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func metricCard(
        title: String,
        value: String,
        unit: String,
        icon: String
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(ATHLTHTheme.accent)

                Text(value)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func controls(_ snapshot: WatchWorkoutLiveSnapshot) -> some View {
        if snapshot.state == .completed || snapshot.state == .failed {
            Button {
                mirroring.dismissSummary()
                if ghostRace.reference != nil {
                    ghostRace.dismissResult()
                }
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(ATHLTHTheme.accent)
        } else {
            HStack(spacing: 12) {
                Button {
                    mirroring.sendCommand(
                        snapshot.state == .paused ? .resume : .pause
                    )
                } label: {
                    Label(
                        snapshot.state == .paused ? "Resume" : "Pause",
                        systemImage: snapshot.state == .paused
                            ? "play.fill"
                            : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(
                    snapshot.state == .preparing ||
                    snapshot.state == .ending
                )

                Button(role: .destructive) {
                    mirroring.sendCommand(.end)
                } label: {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(snapshot.state == .ending)
            }
        }
    }

    private func displayedElapsedTime(
        snapshot: WatchWorkoutLiveSnapshot,
        now: Date
    ) -> TimeInterval {
        guard snapshot.state == .running else {
            return snapshot.elapsedTime
        }

        return max(
            snapshot.elapsedTime,
            snapshot.elapsedTime + now.timeIntervalSince(snapshot.capturedAt)
        )
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func statusTitle(
        _ state: WatchWorkoutMirrorState
    ) -> String {
        switch state {
        case .preparing: return "Starting"
        case .running: return "Live"
        case .paused: return "Paused"
        case .ending: return "Saving"
        case .completed: return "Completed"
        case .failed: return "Error"
        }
    }

    private func statusIcon(
        _ state: WatchWorkoutMirrorState
    ) -> String {
        switch state {
        case .preparing: return "hourglass"
        case .running: return "waveform.path.ecg"
        case .paused: return "pause.circle.fill"
        case .ending: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(
        _ state: WatchWorkoutMirrorState
    ) -> Color {
        switch state {
        case .running, .completed:
            return ATHLTHTheme.accent
        case .paused, .preparing, .ending:
            return .orange
        case .failed:
            return .red
        }
    }
    @MainActor
    private func syncLivePosition() async {
        guard let snapshot =
                mirroring.snapshot
        else {
            return
        }

        if snapshot.state == .completed ||
            snapshot.state == .failed {
            if realtime.currentSession != nil {
                await realtime
                    .leaveCurrentLiveWorkout()
            }
            return
        }

        guard snapshot.state == .running ||
                snapshot.state == .paused
        else {
            return
        }

        if realtime.currentSession == nil {
            guard social.privacy?
                    .shareLiveWorkoutLocation ==
                    true
            else {
                return
            }

            let activity: String
            switch snapshot.kind {
            case .walking:
                activity = "walking"
            case .cycling:
                activity = "cycling"
            case .running:
                activity = "running"
            default:
                return
            }

            let visibility =
                ATHLTHLiveWorkoutVisibility(
                    rawValue:
                        social.privacy?
                            .liveLocationVisibility ??
                        "followers"
                ) ?? .followers

            _ = await realtime
                .beginLiveWorkout(
                    title:
                        snapshot.routeTitle ??
                        snapshot.kind.title,
                    activity: activity,
                    visibility: visibility,
                    routeKey:
                        snapshot
                            .routeComparisonID,
                    routeDistanceMeters:
                        snapshot
                            .routeDistanceMeters,
                    routeTitle:
                        snapshot
                            .routeTitle
                )
        }

        await realtime
            .publishMirroredSnapshot(
                snapshot,
                includeHeartRate:
                    social.privacy?
                        .shareLiveWorkoutHeartRate ==
                    true
            )
    }

}
