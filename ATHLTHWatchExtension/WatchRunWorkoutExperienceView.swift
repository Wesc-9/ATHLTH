import MapKit
import SwiftUI

/// The run-first Apple Watch experience.
///
/// The workout engine remains owned by `WatchWorkoutManager`. This view is
/// intentionally presentation-only so HealthKit recording can continue even
/// when WatchConnectivity or the iPhone is unavailable.
struct WatchRunWorkoutExperienceView: View {
    @EnvironmentObject private var workoutManager:
        WatchWorkoutManager
    @Environment(\.isLuminanceReduced)
    private var isLuminanceReduced

    @State private var selectedPage = 0
    @State private var confirmingEnd = false

    var body: some View {
        Group {
            if isLuminanceReduced {
                alwaysOnPage
            } else {
                TabView(
                    selection:
                        $selectedPage
                ) {
                    metricsPage
                        .tag(0)

                    planPage
                        .tag(1)

                    routePage
                        .tag(2)

                    WatchSpotifyRemotePage()
                        .tag(3)

                    controlsPage
                        .tag(4)
                }
                .tabViewStyle(
                    .verticalPage
                )
            }
        }
        .background(
            WatchTheme.canvas
                .ignoresSafeArea()
        )
        .foregroundStyle(
            WatchTheme.textPrimary
        )
        .confirmationDialog(
            "End workout?",
            isPresented: $confirmingEnd,
            titleVisibility: .visible
        ) {
            Button(
                "End Workout",
                role: .destructive
            ) {
                workoutManager.end()
            }

            Button(
                "Keep Going",
                role: .cancel
            ) {}
        } message: {
            Text(
                "ATHLTH will finish and save the workout to Apple Health."
            )
        }
    }

    private var alwaysOnPage: some View {
        VStack(spacing: 7) {
            HStack {
                Image(
                    systemName:
                        workoutManager
                            .kind.systemImage
                )
                .font(
                    .system(
                        size: 10,
                        weight: .bold
                    )
                )

                Text(
                    workoutManager
                        .automaticPauseActive
                        ? "AUTO PAUSED"
                        : workoutManager
                            .state ==
                            .paused
                            ? "PAUSED"
                            : "ATHLTH"
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .tracking(0.8)

                Spacer()

                Text(
                    durationText(
                        workoutManager
                            .elapsedTime
                    )
                )
                .font(
                    .system(
                        size: 11,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
            }
            .foregroundStyle(
                Color.white.opacity(0.72)
            )

            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    Text("PACE")
                        .font(
                            .system(
                                size: 7,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(0.55)
                        )

                    Text(
                        paceText(
                            workoutManager
                                .currentPaceSecondsPerKilometer
                        )
                    )
                    .font(
                        .system(
                            size: 25,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                }

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: 1
                ) {
                    Text(
                        distanceKilometersText +
                        " km"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()

                    Text(
                        heartRateText +
                        " bpm"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        Color.white.opacity(0.72)
                    )
                }
            }

            if let step =
                    workoutManager
                        .currentStructuredRunningStep {
                HStack {
                    Text(step.title)
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold
                            )
                        )
                        .lineLimit(1)

                    Spacer()

                    Text(
                        "\(workoutManager.structuredStepIndex + 1)"
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                }
                .foregroundStyle(
                    WatchTheme
                        .textSecondary
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .foregroundStyle(Color.white)
        .background(
            Color.black
                .ignoresSafeArea()
        )
    }

    // MARK: - Page 1: live metrics

    private var metricsPage: some View {
        VStack(spacing: 7) {
            statusHeader(
                title: workoutManager.kind.title,
                icon:
                    workoutManager
                        .kind.systemImage
            )

            Text(
                durationText(
                    workoutManager.elapsedTime
                )
            )
            .font(
                .system(
                    size: 30,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .foregroundStyle(
                WatchTheme.textPrimary
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.horizontal, 2)

            HStack(spacing: 7) {
                metricTile(
                    title: "PACE",
                    value:
                        paceText(
                            workoutManager
                                .currentPaceSecondsPerKilometer
                        ),
                    suffix: "/km",
                    icon: "speedometer"
                )

                metricTile(
                    title: "HEART",
                    value:
                        heartRateText,
                    suffix: "bpm",
                    icon: "heart.fill"
                )
            }

            HStack(spacing: 7) {
                metricTile(
                    title: "DISTANCE",
                    value:
                        distanceKilometersText,
                    suffix: "km",
                    icon: "location.fill"
                )

                metricTile(
                    title: "CALORIES",
                    value:
                        String(
                            Int(
                                workoutManager
                                    .activeCalories
                                    .rounded()
                            )
                        ),
                    suffix: "kcal",
                    icon: "flame.fill"
                )
            }

            sensorStatus
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var sensorStatus: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(
                    sensorsAreLive
                        ? WatchTheme.accent
                        : WatchTheme.warning
                )
                .frame(
                    width: 6,
                    height: 6
                )

            Text(
                sensorsAreLive
                    ? "Recording on Apple Watch"
                    : "Acquiring sensors…"
            )
            .font(
                .system(
                    size: 8,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                WatchTheme.muted
            )

            Spacer()

            if workoutManager.routePoints.count > 1 {
                Image(
                    systemName:
                        "location.fill"
                )
                .font(
                    .system(size: 8)
                )
                .foregroundStyle(
                    WatchTheme.accent
                )
            }
        }
        .padding(.horizontal, 3)
    }

    // MARK: - Page 2: workout / interval plan

    @ViewBuilder
    private var planPage: some View {
        if let workout =
                workoutManager
                    .structuredRunningWorkout,
           let step =
                workoutManager
                    .currentStructuredRunningStep,
           !workout.steps.isEmpty {
            structuredPlanPage(
                workout: workout,
                step: step
            )
        } else {
            freeRunPage
        }
    }

    private func structuredPlanPage(
        workout: WatchRunningWorkoutTransfer,
        step: WatchRunningWorkoutStep
    ) -> some View {
        VStack(spacing: 8) {
            pageLabel(
                "WORKOUT",
                icon: "list.bullet.rectangle"
            )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                HStack {
                    Text(
                        workout.title.isEmpty
                            ? "Running workout"
                            : workout.title
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        WatchTheme.textSecondary
                    )
                    .lineLimit(1)

                    Spacer()

                    Text(
                        "\(workoutManager.structuredStepIndex + 1)/\(workout.steps.count)"
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        WatchTheme.accent
                    )
                }

                Text(step.title)
                    .font(
                        .system(
                            size: 20,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let target =
                        stepTargetText(step) {
                    Text(target)
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            WatchTheme.accent
                        )
                        .lineLimit(2)
                }

                ProgressView(
                    value:
                        currentStepProgress(
                            step
                        )
                )
                .tint(
                    WatchTheme.accent
                )
            }
            .padding(11)
            .watchSurface(radius: 18)

            HStack(spacing: 7) {
                metricTile(
                    title: "STEP TIME",
                    value:
                        durationText(
                            workoutManager
                                .currentStructuredStepElapsedTime
                        ),
                    suffix: "",
                    icon: "timer"
                )

                metricTile(
                    title: "STEP DIST",
                    value:
                        String(
                            format: "%.2f",
                            workoutManager
                                .currentStructuredStepDistanceMeters /
                                1_000
                        ),
                    suffix: "km",
                    icon:
                        "point.topleft.down.to.point.bottomright.curvepath"
                )
            }

            if let next =
                    workoutManager
                        .nextStructuredRunningStep {
                HStack(spacing: 6) {
                    Text("NEXT")
                        .font(
                            .system(
                                size: 7,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            WatchTheme.muted
                        )

                    Text(next.title)
                        .font(
                            .system(
                                size: 10,
                                weight: .semibold
                            )
                        )
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var freeRunPage: some View {
        VStack(spacing: 9) {
            pageLabel(
                "FREE RUN",
                icon: "figure.run"
            )

            VStack(spacing: 4) {
                Text("Average pace")
                    .font(
                        .system(
                            size: 9,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        WatchTheme.muted
                    )

                Text(
                    paceText(
                        workoutManager
                            .averagePaceSecondsPerKilometer
                    )
                )
                .font(
                    .system(
                        size: 28,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()

                Text("/km")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        WatchTheme.muted
                    )
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(.vertical, 12)
            .watchSurface(radius: 20)

            HStack(spacing: 7) {
                metricTile(
                    title: "CALORIES",
                    value:
                        "\(Int(workoutManager.activeCalories.rounded()))",
                    suffix: "kcal",
                    icon: "flame.fill"
                )

                metricTile(
                    title: "LAP",
                    value:
                        "\(workoutManager.lapCount + 1)",
                    suffix: "",
                    icon: "flag.fill"
                )
            }

            Text(
                "Swipe for route, Spotify and controls"
            )
            .font(
                .system(size: 8)
            )
            .foregroundStyle(
                WatchTheme.muted
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Page 3: route, Route Guardian and Ghost

    private var routePage: some View {
        ScrollView {
            VStack(spacing: 8) {
                pageLabel(
                    workoutManager
                        .plannedRoute == nil
                        ? "GPS"
                        : "ROUTE",
                    icon: "map.fill"
                )

                if routeCoordinates.count >= 2 {
                    Map {
                        MapPolyline(
                            coordinates:
                                routeCoordinates
                        )
                        .stroke(
                            WatchTheme.accent,
                            lineWidth: 4
                        )
                    }
                    .frame(height: 102)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                        .stroke(
                            WatchTheme.border,
                            lineWidth: 1
                        )
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(
                            systemName:
                                "location.fill.viewfinder"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            WatchTheme.accent
                        )

                        Text(
                            workoutManager
                                .routePoints
                                .isEmpty
                                ? "Finding GPS…"
                                : "Building your route…"
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold
                            )
                        )
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 86
                    )
                    .watchSurface(radius: 18)
                }

                if workoutManager.plannedRoute != nil {
                    HStack(spacing: 7) {
                        metricTile(
                            title: "REMAINING",
                            value:
                                remainingDistanceText,
                            suffix: "",
                            icon:
                                "location.north.fill"
                        )

                        metricTile(
                            title: "OFF ROUTE",
                            value:
                                routeDeviationText,
                            suffix: "",
                            icon:
                                "location.triangle.fill"
                        )
                    }

                    if let progress =
                            workoutManager
                                .routeProgressPercent {
                        ProgressView(
                            value:
                                min(
                                    max(
                                        progress / 100,
                                        0
                                    ),
                                    1
                                )
                        )
                        .tint(
                            WatchTheme.accent
                        )
                        .padding(
                            .horizontal,
                            5
                        )
                    }
                }

                if workoutManager
                        .ghostRaceTitle != nil {
                    ghostCard
                } else if workoutManager
                            .plannedRoute == nil {
                    Text(
                        "Free run · the Watch records your live route."
                    )
                    .font(
                        .system(size: 8)
                    )
                    .foregroundStyle(
                        WatchTheme.muted
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var ghostCard: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            HStack {
                Label(
                    "GHOST",
                    systemImage:
                        "figure.run.circle.fill"
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    WatchTheme.accent
                )

                Spacer()

                if let timeDelta =
                        workoutManager
                            .ghostTimeDeltaSeconds {
                    Text(
                        ghostTimeText(
                            timeDelta
                        )
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )
                    .monospacedDigit()
                }
            }

            Text(
                ghostDistanceText(
                    workoutManager
                        .ghostDistanceDeltaMeters
                )
            )
            .font(
                .system(
                    size: 18,
                    weight: .bold,
                    design: .rounded
                )
            )

            Text(
                workoutManager
                    .ghostRaceTitle ??
                    "Target"
            )
            .font(
                .system(size: 8)
            )
            .foregroundStyle(
                WatchTheme.muted
            )
            .lineLimit(1)
        }
        .padding(10)
        .watchSurface(radius: 17)
    }

    // MARK: - Page 5: controls

    private var controlsPage: some View {
        VStack(spacing: 9) {
            pageLabel(
                "CONTROLS",
                icon: "slider.horizontal.3"
            )

            HStack(spacing: 8) {
                controlButton(
                    title:
                        workoutManager
                            .state == .paused
                        ? "Resume"
                        : "Pause",
                    icon:
                        workoutManager
                            .state == .paused
                        ? "play.fill"
                        : "pause.fill",
                    accent: true
                ) {
                    if workoutManager
                            .state == .paused {
                        workoutManager.resume()
                    } else {
                        workoutManager.pause()
                    }
                }

                controlButton(
                    title: "Lap",
                    icon: "flag.fill",
                    accent: false
                ) {
                    workoutManager.markLap()
                }
                .disabled(
                    workoutManager.state !=
                        .running
                )
                .opacity(
                    workoutManager.state ==
                        .running
                        ? 1
                        : 0.45
                )
            }

            if workoutManager
                    .audioCoachConfigured {
                Button {
                    workoutManager
                        .setAudioCoachEnabled(
                            !workoutManager
                                .audioCoachConfiguration
                                .enabled
                        )
                } label: {
                    HStack {
                        Image(
                            systemName:
                                workoutManager
                                    .audioCoachConfiguration
                                    .enabled
                                ? "speaker.wave.2.fill"
                                : "speaker.slash.fill"
                        )

                        Text("Audio Coach")
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold
                                )
                            )

                        Spacer()

                        Text(
                            workoutManager
                                .audioCoachConfiguration
                                .enabled
                                ? "ON"
                                : "OFF"
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            workoutManager
                                .audioCoachConfiguration
                                .enabled
                                ? WatchTheme.accent
                                : WatchTheme.muted
                        )
                    }
                    .padding(11)
                    .watchSurface(radius: 17)
                }
                .buttonStyle(.plain)
            }

            Button {
                confirmingEnd = true
            } label: {
                HStack {
                    Image(
                        systemName:
                            "stop.fill"
                    )

                    Text("End Workout")
                        .font(
                            .system(
                                size: 13,
                                weight: .bold
                            )
                        )
                }
                .foregroundStyle(.white)
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 44)
                .background(
                    WatchTheme.danger,
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                workoutManager.state ==
                    .ending
            )
            .opacity(
                workoutManager.state ==
                    .ending
                    ? 0.5
                    : 1
            )

            Text(
                "Swipe up/down between live metrics, workout, route and controls."
            )
            .font(
                .system(size: 8)
            )
            .foregroundStyle(
                WatchTheme.muted
            )
            .multilineTextAlignment(
                .center
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Components

    private func statusHeader(
        title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 11,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    WatchTheme.accent
                )

            Text(title.uppercased())
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .tracking(0.9)

            Spacer()

            Circle()
                .fill(
                    workoutManager
                        .state == .paused
                        ? WatchTheme.warning
                        : WatchTheme.accent
                )
                .frame(
                    width: 6,
                    height: 6
                )

            Text(
                workoutManager
                    .automaticPauseActive
                    ? "AUTO PAUSED"
                    : workoutManager
                        .state == .paused
                        ? "PAUSED"
                        : "LIVE"
            )
            .font(
                .system(
                    size: 8,
                    weight: .bold
                )
            )
            .foregroundStyle(
                WatchTheme.muted
            )
        }
        .padding(.horizontal, 3)
    }

    private func pageLabel(
        _ title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(
                    WatchTheme.accent
                )

            Text(title)
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .tracking(1)

            Spacer()
        }
        .padding(.horizontal, 3)
    }

    private func metricTile(
        title: String,
        value: String,
        suffix: String,
        icon: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(
                        .system(size: 8)
                    )

                Text(title)
                    .font(
                        .system(
                            size: 7,
                            weight: .bold
                        )
                    )
                    .tracking(0.6)
            }
            .foregroundStyle(
                WatchTheme.muted
            )

            HStack(
                alignment: .firstTextBaseline,
                spacing: 3
            ) {
                Text(value)
                    .font(
                        .system(
                            size: 18,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                if !suffix.isEmpty {
                    Text(suffix)
                        .font(
                            .system(
                                size: 7,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            WatchTheme.muted
                        )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(9)
        .watchSurface(radius: 16)
    }

    private func controlButton(
        title: String,
        icon: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 18,
                            weight: .bold
                        )
                    )

                Text(title)
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
            }
            .foregroundStyle(
                accent
                    ? Color.white
                    : WatchTheme
                        .textPrimary
            )
            .frame(
                maxWidth: .infinity
            )
            .frame(height: 54)
            .background(
                accent
                    ? WatchTheme.accent
                    : WatchTheme.cardRaised,
                in: RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived state

    private var sensorsAreLive: Bool {
        workoutManager.heartRate > 0 ||
        workoutManager.distanceMeters > 0 ||
        workoutManager.routePoints.count > 1
    }

    private var distanceKilometersText:
        String {
        String(
            format: "%.2f",
            max(
                workoutManager
                    .distanceMeters,
                0
            ) / 1_000
        )
    }

    private var heartRateText: String {
        guard workoutManager.heartRate > 0
        else {
            return "—"
        }

        return "\(Int(workoutManager.heartRate.rounded()))"
    }

    private var routeCoordinates:
        [CLLocationCoordinate2D] {
        let live =
            workoutManager
                .routePoints
                .sorted {
                    $0.sequence < $1.sequence
                }
                .map {
                    CLLocationCoordinate2D(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    )
                }

        if live.count >= 2 {
            return live
        }

        let planned =
            workoutManager
                .plannedRoute?
                .points
                .sorted {
                    $0.sequence < $1.sequence
                } ?? []

        guard planned.count > 240
        else {
            return planned.map {
                CLLocationCoordinate2D(
                    latitude:
                        $0.latitude,
                    longitude:
                        $0.longitude
                )
            }
        }

        let strideValue =
            max(
                planned.count / 220,
                1
            )

        var sampled =
            stride(
                from: 0,
                to: planned.count,
                by: strideValue
            )
            .map {
                planned[$0]
            }

        if let last = planned.last,
           sampled.last?.sequence !=
            last.sequence {
            sampled.append(last)
        }

        return sampled.map {
            CLLocationCoordinate2D(
                latitude:
                    $0.latitude,
                longitude:
                    $0.longitude
            )
        }
    }

    private var remainingDistanceText:
        String {
        guard let meters =
                workoutManager
                    .routeRemainingMeters
        else {
            return "—"
        }

        if meters >= 1_000 {
            return String(
                format: "%.1f km",
                meters / 1_000
            )
        }

        return "\(Int(max(meters, 0).rounded())) m"
    }

    private var routeDeviationText:
        String {
        guard let meters =
                workoutManager
                    .routeDeviationMeters
        else {
            return "—"
        }

        return "\(Int(max(meters, 0).rounded())) m"
    }

    private func currentStepProgress(
        _ step: WatchRunningWorkoutStep
    ) -> Double {
        switch step.measure {
        case .time:
            guard let target =
                    step.durationSeconds,
                  target > 0
            else {
                return 0
            }

            return min(
                max(
                    workoutManager
                        .currentStructuredStepElapsedTime /
                        target,
                    0
                ),
                1
            )

        case .distance:
            guard let target =
                    step.distanceMeters,
                  target > 0
            else {
                return 0
            }

            return min(
                max(
                    workoutManager
                        .currentStructuredStepDistanceMeters /
                        target,
                    0
                ),
                1
            )

        case .open:
            return 0
        }
    }

    private func stepTargetText(
        _ step: WatchRunningWorkoutStep
    ) -> String? {
        let measure: String

        switch step.measure {
        case .time:
            if let seconds =
                    step.durationSeconds {
                measure =
                    durationText(seconds)
            } else {
                measure = "Open"
            }

        case .distance:
            if let meters =
                    step.distanceMeters {
                if meters >= 1_000 {
                    measure =
                        String(
                            format:
                                "%.1f km",
                            meters / 1_000
                        )
                } else {
                    measure =
                        "\(Int(meters.rounded())) m"
                }
            } else {
                measure = "Open"
            }

        case .open:
            measure = "Open"
        }

        if let intensity =
                step.intensityText,
           !intensity.isEmpty {
            return
                "\(measure) · \(intensity)"
        }

        return measure
    }

    private func paceText(
        _ secondsPerKilometer:
            TimeInterval?
    ) -> String {
        guard let pace =
                secondsPerKilometer,
              pace.isFinite,
              pace > 0
        else {
            return "—:—"
        }

        let total =
            max(
                Int(pace.rounded()),
                0
            )

        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }

    private func durationText(
        _ duration: TimeInterval
    ) -> String {
        let total =
            max(
                Int(
                    duration
                        .rounded(.down)
                ),
                0
            )
        let hours = total / 3_600
        let minutes =
            (total % 3_600) / 60
        let seconds =
            total % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format:
                "%02d:%02d",
            minutes,
            seconds
        )
    }

    private func ghostDistanceText(
        _ delta: Double?
    ) -> String {
        guard let delta else {
            return "Finding Ghost…"
        }

        let meters =
            Int(abs(delta).rounded())

        if meters < 8 {
            return "Neck and neck"
        }

        return delta >= 0
            ? "You +\(meters) m"
            : "Ghost +\(meters) m"
    }

    private func ghostTimeText(
        _ delta: TimeInterval
    ) -> String {
        let seconds =
            Int(abs(delta).rounded())
        let prefix =
            delta >= 0
                ? "−"
                : "+"

        if seconds >= 60 {
            return prefix +
                String(
                    format:
                        "%d:%02d",
                    seconds / 60,
                    seconds % 60
                )
        }

        return
            prefix + "\(seconds)s"
    }
}
