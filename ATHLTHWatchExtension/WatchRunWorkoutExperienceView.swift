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
    @State private var ghostMapPosition:
        MapCameraPosition = .automatic
    @State private var navigationMapPosition:
        MapCameraPosition = .automatic

    var body: some View {
        Group {
            if isLuminanceReduced {
                WatchTrainingAlwaysOnDashboard()
                    .environmentObject(workoutManager)
            } else {
                TabView(
                    selection:
                        $selectedPage
                ) {
                    metricsPage
                        .tag(0)

                    planPage
                        .tag(1)

                    if workoutManager
                        .treadmillInclinePercent != nil {
                        treadmillInclinePage
                            .tag(6)
                    }

                    routePage
                        .tag(2)

                    if workoutManager
                        .plannedRoute != nil {
                        navigationPage
                            .tag(3)
                    }

                    WatchSpotifyRemotePage()
                        .tag(4)

                    controlsPage
                        .tag(5)
                }
                .tabViewStyle(
                    .verticalPage
                )
            }
        }
        .background(
            Group {
                if isLuminanceReduced {
                    Color.black
                } else {
                    WatchTheme.canvas
                }
            }
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
        GeometryReader { proxy in
            let compact =
                proxy.size.width < 190 ||
                proxy.size.height < 220
            let isPaused =
                workoutManager.state == .paused
            let isAutoPaused =
                workoutManager.automaticPauseActive

            ZStack {
                Color.black

                if isPaused ||
                    isAutoPaused {
                    alwaysOnPausedContent(
                        compact: compact,
                        automatic:
                            isAutoPaused
                    )
                } else if
                    workoutManager.kind ==
                        .strength {
                    alwaysOnStrengthContent(
                        compact: compact
                    )
                } else if
                    workoutManager.kind ==
                        .walking {
                    alwaysOnWalkingContent(
                        compact: compact
                    )
                } else {
                    alwaysOnRunningContent(
                        compact: compact
                    )
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
        }
        .foregroundStyle(
            Color(
                red: 0.94,
                green: 0.94,
                blue: 0.91
            )
        )
        .background(
            Color.black
                .ignoresSafeArea()
        )
    }

    private func alwaysOnStrengthContent(
        compact: Bool
    ) -> some View {
        Group {
            if let session =
                    workoutManager
                        .strengthSession {
                if session.isResting,
                   let restEndsAt =
                        session.restEndsAt {
                    TimelineView(
                        .periodic(
                            from: .now,
                            by: 1
                        )
                    ) { context in
                        alwaysOnStrengthRestContent(
                            session: session,
                            restEndsAt:
                                restEndsAt,
                            now:
                                context.date,
                            compact: compact
                        )
                    }
                } else {
                    alwaysOnStrengthSetContent(
                        session: session,
                        compact: compact
                    )
                }
            } else {
                alwaysOnStrengthBasicContent(
                    compact: compact
                )
            }
        }
    }

    private func alwaysOnStrengthSetContent(
        session:
            WatchStrengthSessionSnapshot,
        compact: Bool
    ) -> some View {
        return VStack(
            alignment: .leading,
            spacing: compact ? 5 : 7
        ) {
            alwaysOnHeader(
                compact: compact
            )

            Spacer(
                minLength: compact ? 1 : 3
            )

            Text(
                session.exerciseName ??
                session.title
            )
            .font(
                .system(
                    size:
                        compact
                            ? 9
                            : 10,
                    weight: .bold
                )
            )
            .tracking(0.65)
            .textCase(.uppercase)
            .foregroundStyle(
                Color.white.opacity(
                    0.55
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.68)

            HStack(
                alignment:
                    .firstTextBaseline,
                spacing: 5
            ) {
                Text(
                    strengthWeightText(
                        session
                            .draftWeightKilograms
                    )
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 31
                                : 36,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                Text("KG")
                    .font(
                        .system(
                            size:
                                compact
                                    ? 8
                                    : 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.48
                        )
                    )

                Text("×")
                    .font(
                        .system(
                            size:
                                compact
                                    ? 13
                                    : 15,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.38
                        )
                    )

                Text(
                    "\(session.draftReps)"
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 24
                                : 28,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
            }

            Text(
                "SET \(max(session.setIndex + 1, 1)) / \(max(session.setCount, 1))"
            )
            .font(
                .system(
                    size:
                        compact
                            ? 7.5
                            : 8.5,
                    weight: .bold
                )
            )
            .tracking(0.9)
            .foregroundStyle(
                strengthAlwaysOnAccent
                    .opacity(0.78)
            )

            Spacer(
                minLength: compact ? 1 : 3
            )

            HStack {
                Text(
                    "\(session.completedSets) / \(max(session.totalSets, 1)) SETS"
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 8
                                : 9,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    Color.white.opacity(
                        0.48
                    )
                )

                Spacer()

                Text(
                    durationText(
                        workoutManager
                            .elapsedTime
                    )
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 9
                                : 10,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    Color.white.opacity(
                        0.52
                    )
                )
            }

            alwaysOnStrengthFooter(
                session: session,
                compact: compact
            )
        }
        .padding(
            .horizontal,
            compact ? 9 : 11
        )
        .padding(
            .vertical,
            compact ? 6 : 8
        )
    }

    private func alwaysOnStrengthRestContent(
        session:
            WatchStrengthSessionSnapshot,
        restEndsAt: Date,
        now: Date,
        compact: Bool
    ) -> some View {
        let remaining =
            max(
                restEndsAt
                    .timeIntervalSince(now),
                0
            )

        return VStack(
            alignment: .leading,
            spacing: compact ? 5 : 7
        ) {
            alwaysOnHeader(
                compact: compact
            )

            Spacer(
                minLength: compact ? 1 : 3
            )

            Text("REST")
                .font(
                    .system(
                        size:
                            compact
                                ? 8
                                : 9,
                        weight: .bold
                    )
                )
                .tracking(1.1)
                .foregroundStyle(
                    strengthAlwaysOnAccent
                        .opacity(0.82)
                )

            Text(
                durationText(
                    remaining
                )
            )
            .font(
                .system(
                    size:
                        compact
                            ? 34
                            : 40,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)

            Text("NEXT SET")
                .font(
                    .system(
                        size: 7.5,
                        weight: .bold
                    )
                )
                .tracking(1.0)
                .foregroundStyle(
                    Color.white.opacity(
                        0.40
                    )
                )

            Spacer(
                minLength: compact ? 1 : 3
            )

            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    Text(
                        session.exerciseName ??
                        session.title
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 9
                                    : 10,
                            weight: .semibold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(
                        Color.white.opacity(
                            0.60
                        )
                    )

                    Text(
                        strengthSetSummary(
                            session
                        )
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 12
                                    : 14,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                }

                Spacer()

                Text(
                    "\(min(session.setIndex + 2, max(session.setCount, 1))) / \(max(session.setCount, 1))"
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 9
                                : 10,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    Color.white.opacity(
                        0.50
                    )
                )
            }

            alwaysOnStrengthFooter(
                session: session,
                compact: compact
            )
        }
        .padding(
            .horizontal,
            compact ? 9 : 11
        )
        .padding(
            .vertical,
            compact ? 6 : 8
        )
    }

    private func alwaysOnStrengthBasicContent(
        compact: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: compact ? 6 : 8
        ) {
            alwaysOnHeader(
                compact: compact
            )

            Spacer()

            Text("STRENGTH")
                .font(
                    .system(
                        size:
                            compact
                                ? 8
                                : 9,
                        weight: .bold
                    )
                )
                .tracking(1.1)
                .foregroundStyle(
                    strengthAlwaysOnAccent
                        .opacity(0.76)
                )

            Text(
                durationText(
                    workoutManager
                        .elapsedTime
                )
            )
            .font(
                .system(
                    size:
                        compact
                            ? 34
                            : 40,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()

            HStack {
                Image(
                    systemName:
                        "heart.fill"
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 8
                                : 9
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(
                        0.44
                    )
                )

                Text(
                    heartRateText
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 13
                                : 15,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()

                Text("bpm")
                    .font(
                        .system(
                            size:
                                compact
                                    ? 7
                                    : 8,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.46
                        )
                    )

                Spacer()
            }

            Spacer()

            Capsule()
                .fill(
                    strengthAlwaysOnAccent
                        .opacity(0.40)
                )
                .frame(height: 1.5)
        }
        .padding(
            .horizontal,
            compact ? 9 : 11
        )
        .padding(
            .vertical,
            compact ? 7 : 9
        )
    }

    private func alwaysOnStrengthFooter(
        session:
            WatchStrengthSessionSnapshot,
        compact: Bool
    ) -> some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(
                    alignment: .leading
                ) {
                    Capsule()
                        .fill(
                            Color.white
                                .opacity(0.09)
                        )

                    Capsule()
                        .fill(
                            strengthAlwaysOnAccent
                                .opacity(0.62)
                        )
                        .frame(
                            width:
                                proxy.size
                                    .width *
                                strengthWorkoutProgress(
                                    session
                                )
                        )
                }
            }
            .frame(height: 2)

            HStack {
                Text("STRENGTH")
                    .font(
                        .system(
                            size:
                                compact
                                    ? 7
                                    : 8,
                            weight: .bold
                        )
                    )
                    .tracking(0.85)
                    .foregroundStyle(
                        Color.white.opacity(
                            0.44
                        )
                    )

                Spacer()

                if session.exerciseCount > 0 {
                    Text(
                        "\(min(session.exerciseIndex + 1, session.exerciseCount))/\(session.exerciseCount)"
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 7.5
                                    : 8.5,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        Color.white.opacity(
                            0.50
                        )
                    )
                }
            }
        }
    }

    private var strengthAlwaysOnAccent:
        Color {
        Color(
            red: 0.83,
            green: 0.66,
            blue: 0.36
        )
    }

    private func strengthWeightText(
        _ kilograms: Double
    ) -> String {
        if kilograms.rounded() ==
            kilograms {
            return String(
                Int(kilograms)
            )
        }

        return String(
            format: "%.1f",
            kilograms
        )
    }

    private func strengthSetSummary(
        _ session:
            WatchStrengthSessionSnapshot
    ) -> String {
        strengthWeightText(
            session
                .draftWeightKilograms
        ) +
        " kg × " +
        String(session.draftReps)
    }

    private func strengthWorkoutProgress(
        _ session:
            WatchStrengthSessionSnapshot
    ) -> CGFloat {
        guard session.totalSets > 0
        else {
            return 0
        }

        return CGFloat(
            min(
                max(
                    Double(
                        session
                            .completedSets
                    ) /
                    Double(
                        session.totalSets
                    ),
                    0
                ),
                1
            )
        )
    }

    private func alwaysOnWalkingContent(
        compact: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: compact ? 5 : 7
        ) {
            alwaysOnHeader(
                compact: compact
            )

            Spacer(
                minLength: compact ? 1 : 3
            )

            // Walking is intentionally distance-first. Pace remains
            // available as a quiet secondary metric instead of competing
            // with the primary progress signal.
            VStack(
                alignment: .leading,
                spacing: compact ? 0 : 1
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 4
                ) {
                    Text(
                        distanceKilometersText
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 33
                                    : 39,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                    Text("km")
                        .font(
                            .system(
                                size:
                                    compact
                                        ? 10
                                        : 11,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(
                                0.54
                            )
                        )
                }

                Text("DISTANCE")
                    .font(
                        .system(
                            size: 7.5,
                            weight: .bold
                        )
                    )
                    .tracking(1.15)
                    .foregroundStyle(
                        Color.white.opacity(
                            0.43
                        )
                    )
            }

            Spacer(
                minLength: compact ? 1 : 3
            )

            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 4
                ) {
                    Image(
                        systemName: "clock"
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 8
                                    : 9,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.46
                        )
                    )

                    Text(
                        durationText(
                            workoutManager
                                .elapsedTime
                        )
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 14
                                    : 16,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                }

                Spacer()

                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 4
                ) {
                    Image(
                        systemName:
                            "heart.fill"
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 8
                                    : 9,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.52
                        )
                    )

                    Text(
                        heartRateText
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 14
                                    : 16,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()

                    Text("bpm")
                        .font(
                            .system(
                                size:
                                    compact
                                        ? 7
                                        : 8,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(
                                0.48
                            )
                        )
                }
            }

            HStack(spacing: 5) {
                Image(
                    systemName:
                        "figure.walk"
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 8
                                : 9,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    WatchTheme
                        .accent
                        .opacity(0.58)
                )

                Text("WALK")
                    .font(
                        .system(
                            size:
                                compact
                                    ? 7.5
                                    : 8.5,
                            weight: .bold
                        )
                    )
                    .tracking(0.95)
                    .foregroundStyle(
                        Color.white.opacity(
                            0.52
                        )
                    )

                Spacer()

                if let pace =
                        workoutManager
                            .currentPaceSecondsPerKilometer {
                    Text(
                        paceText(pace) +
                        " /km"
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 8
                                    : 9,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        Color.white.opacity(
                            0.48
                        )
                    )
                }
            }
            .padding(.top, 1)

            Capsule()
                .fill(
                    WatchTheme
                        .accent
                        .opacity(0.34)
                )
                .frame(height: 1.5)
        }
        .padding(
            .horizontal,
            compact ? 9 : 11
        )
        .padding(
            .vertical,
            compact ? 6 : 8
        )
    }

    private func alwaysOnRunningContent(
        compact: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: compact ? 5 : 7
        ) {
            alwaysOnHeader(
                compact: compact
            )

            Spacer(
                minLength: compact ? 1 : 3
            )

            VStack(
                alignment: .leading,
                spacing: compact ? 0 : 1
            ) {
                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 4
                ) {
                    Text(
                        paceText(
                            workoutManager
                                .currentPaceSecondsPerKilometer
                        )
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 33
                                    : 39,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                    Text("/km")
                        .font(
                            .system(
                                size:
                                    compact
                                        ? 10
                                        : 11,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(
                                0.54
                            )
                        )
                }

                Text("PACE")
                    .font(
                        .system(
                            size: 7.5,
                            weight: .bold
                        )
                    )
                    .tracking(1.15)
                    .foregroundStyle(
                        Color.white.opacity(
                            0.43
                        )
                    )
            }

            if let step =
                    workoutManager
                        .currentStructuredRunningStep {
                alwaysOnStructuredTarget(
                    step,
                    compact: compact
                )
            }

            Spacer(
                minLength: compact ? 1 : 3
            )

            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                alwaysOnMetricText(
                    value:
                        distanceKilometersText,
                    suffix: "km",
                    compact: compact
                )

                Spacer()

                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 4
                ) {
                    Image(
                        systemName:
                            "heart.fill"
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 8
                                    : 9,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.52
                        )
                    )

                    Text(
                        heartRateText
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 14
                                    : 16,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()

                    Text("bpm")
                        .font(
                            .system(
                                size:
                                    compact
                                        ? 7
                                        : 8,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(
                                0.48
                            )
                        )
                }
            }

            if let step =
                    workoutManager
                        .currentStructuredRunningStep {
                alwaysOnStepFooter(
                    step,
                    compact: compact
                )
            }
        }
        .padding(
            .horizontal,
            compact ? 9 : 11
        )
        .padding(
            .vertical,
            compact ? 6 : 8
        )
    }

    private func alwaysOnPausedContent(
        compact: Bool,
        automatic: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: compact ? 6 : 8
        ) {
            alwaysOnHeader(
                compact: compact,
                showElapsedTime: false
            )

            Spacer(
                minLength: 0
            )

            HStack(spacing: 6) {
                Circle()
                    .fill(
                        automatic
                            ? Color(
                                red: 0.78,
                                green: 0.55,
                                blue: 0.24
                            )
                            : Color.white
                                .opacity(0.68)
                    )
                    .frame(
                        width: 5,
                        height: 5
                    )

                Text(
                    automatic
                        ? "AUTO PAUSED"
                        : "PAUSED"
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 8
                                : 9,
                        weight: .bold
                    )
                )
                .tracking(1.05)
                .foregroundStyle(
                    automatic
                        ? Color(
                            red: 0.86,
                            green: 0.68,
                            blue: 0.40
                        )
                        : Color.white
                            .opacity(0.66)
                )
            }

            Text(
                durationText(
                    workoutManager
                        .elapsedTime
                )
            )
            .font(
                .system(
                    size:
                        compact
                            ? 34
                            : 40,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)

            HStack {
                alwaysOnMetricText(
                    value:
                        distanceKilometersText,
                    suffix: "km",
                    compact: compact
                )

                Spacer()

                if workoutManager
                    .heartRate > 0 {
                    HStack(
                        alignment:
                            .firstTextBaseline,
                        spacing: 4
                    ) {
                        Image(
                            systemName:
                                "heart.fill"
                        )
                        .font(
                            .system(
                                size:
                                    compact
                                        ? 8
                                        : 9
                            )
                        )
                        .foregroundStyle(
                            Color.white
                                .opacity(0.46)
                        )

                        Text(
                            heartRateText
                        )
                        .font(
                            .system(
                                size:
                                    compact
                                        ? 13
                                        : 15,
                                weight:
                                    .semibold,
                                design:
                                    .rounded
                            )
                        )
                        .monospacedDigit()
                    }
                }
            }

            Spacer(
                minLength: 0
            )
        }
        .padding(
            .horizontal,
            compact ? 9 : 11
        )
        .padding(
            .vertical,
            compact ? 7 : 9
        )
    }

    private func alwaysOnHeader(
        compact: Bool,
        showElapsedTime: Bool = true
    ) -> some View {
        HStack(spacing: 6) {
            WatchATHLTHAlwaysOnMark()
                .stroke(
                    Color.white.opacity(
                        0.72
                    ),
                    style:
                        StrokeStyle(
                            lineWidth: 1.7,
                            lineCap: .round,
                            lineJoin: .round
                        )
                )
                .frame(
                    width:
                        compact
                            ? 15
                            : 17,
                    height:
                        compact
                            ? 10
                            : 11
                )

            Text("ATHLTH")
                .font(
                    .system(
                        size:
                            compact
                                ? 7.5
                                : 8.5,
                        weight: .bold
                    )
                )
                .tracking(1.05)
                .foregroundStyle(
                    Color.white.opacity(
                        0.62
                    )
                )

            Spacer()

            if showElapsedTime {
                Text(
                    durationText(
                        workoutManager
                            .elapsedTime
                    )
                )
                .font(
                    .system(
                        size:
                            compact
                                ? 9.5
                                : 10.5,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    Color.white.opacity(
                        0.58
                    )
                )
            }
        }
    }

    private func alwaysOnMetricText(
        value: String,
        suffix: String,
        compact: Bool
    ) -> some View {
        HStack(
            alignment:
                .firstTextBaseline,
            spacing: 3
        ) {
            Text(value)
                .font(
                    .system(
                        size:
                            compact
                                ? 14
                                : 16,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .monospacedDigit()

            Text(suffix)
                .font(
                    .system(
                        size:
                            compact
                                ? 7
                                : 8,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(
                        0.48
                    )
                )
        }
    }

    private func alwaysOnStructuredTarget(
        _ step:
            WatchRunningWorkoutStep,
        compact: Bool
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            if let intensity =
                    step.intensityText,
               !intensity.isEmpty {
                HStack(spacing: 5) {
                    Text("TARGET")
                        .font(
                            .system(
                                size: 7,
                                weight: .bold
                            )
                        )
                        .tracking(0.9)
                        .foregroundStyle(
                            Color.white.opacity(
                                0.40
                            )
                        )

                    Text(intensity)
                        .font(
                            .system(
                                size:
                                    compact
                                        ? 9
                                        : 10,
                                weight:
                                    .semibold,
                                design:
                                    .rounded
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.72
                        )
                        .foregroundStyle(
                            Color.white.opacity(
                                0.68
                            )
                        )
                }
            }

            if let remaining =
                    alwaysOnRemainingStepText(
                        step
                    ) {
                Text(remaining)
                    .font(
                        .system(
                            size:
                                compact
                                    ? 8
                                    : 9,
                            weight:
                                .medium,
                            design:
                                .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        Color.white.opacity(
                            0.48
                        )
                    )
            }
        }
    }

    private func alwaysOnStepFooter(
        _ step:
            WatchRunningWorkoutStep,
        compact: Bool
    ) -> some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(
                    alignment: .leading
                ) {
                    Capsule()
                        .fill(
                            Color.white
                                .opacity(0.10)
                        )

                    Capsule()
                        .fill(
                            WatchTheme
                                .accent
                                .opacity(0.54)
                        )
                        .frame(
                            width:
                                proxy.size
                                    .width *
                                currentStepProgress(
                                    step
                                )
                        )
                }
            }
            .frame(height: 2)

            HStack {
                Text(step.title)
                    .font(
                        .system(
                            size:
                                compact
                                    ? 7.5
                                    : 8.5,
                            weight:
                                .semibold
                        )
                    )
                    .lineLimit(1)
                    .foregroundStyle(
                        Color.white.opacity(
                            0.58
                        )
                    )

                Spacer()

                let totalSteps =
                    workoutManager
                        .structuredRunningWorkout?
                        .steps.count ?? 0

                if totalSteps > 0 {
                    Text(
                        "\(workoutManager.structuredStepIndex + 1)/\(totalSteps)"
                    )
                    .font(
                        .system(
                            size:
                                compact
                                    ? 7.5
                                    : 8.5,
                            weight: .bold,
                            design:
                                .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        Color.white.opacity(
                            0.58
                        )
                    )
                }
            }
        }
    }

    private func alwaysOnRemainingStepText(
        _ step:
            WatchRunningWorkoutStep
    ) -> String? {
        switch step.measure {
        case .time:
            guard let target =
                    step.durationSeconds
            else {
                return nil
            }

            let remaining =
                max(
                    target -
                    workoutManager
                        .currentStructuredStepElapsedTime,
                    0
                )

            return
                durationText(
                    remaining
                ) +
                " remaining"

        case .distance:
            guard let target =
                    step.distanceMeters
            else {
                return nil
            }

            let remaining =
                max(
                    target -
                    workoutManager
                        .currentStructuredStepDistanceMeters,
                    0
                )

            if remaining >= 1_000 {
                return String(
                    format:
                        "%.1f km remaining",
                    remaining / 1_000
                )
            }

            return
                "\(Int(remaining.rounded())) m remaining"

        case .open:
            return nil
        }
    }

    // MARK: - Page 1: live metrics

    private var metricsPage: some View {
        GeometryReader { viewport in
            let compact = viewport.size.height < 205 ||
                viewport.size.width < 190

            VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                HStack(spacing: 5) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.liveLime)

                    Text(workoutManager.kind == .walking
                        ? ATHLTHLocalization.choose(
                            english: "WALK", norwegian: "GÅTUR"
                        )
                        : ATHLTHLocalization.choose(
                            english: "RUN", norwegian: "LØPING"
                        ))
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(.white)

                    Spacer(minLength: 2)

                    Circle()
                        .fill(workoutManager.state == .paused
                            ? WatchTheme.warning : WatchTheme.liveLime)
                        .frame(width: 6, height: 6)
                    Text(workoutManager.state == .paused ||
                         workoutManager.automaticPauseActive
                         ? "PAUSE" : "LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            Color.white.opacity(0.82)
                        )
                }

                Text(liveWorkoutStepTitle)
                    .font(.system(
                        size: compact ? 10 : 11,
                        weight: .semibold
                    ))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                liveHeroMetric(
                    title: "PACE",
                    value: paceText(
                        workoutManager.currentPaceSecondsPerKilometer
                    ),
                    unit: "/km",
                    tint: WatchTheme.liveLime,
                    fontSize: compact ? 35 : 42
                )

                liveHeroMetric(
                    title: ATHLTHLocalization.choose(
                        english: "DISTANCE", norwegian: "DISTANSE"
                    ),
                    value: distanceKilometersText,
                    unit: "km",
                    tint: WatchTheme.liveCyan,
                    fontSize: compact ? 31 : 37
                )

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Label(
                        durationText(workoutManager.elapsedTime),
                        systemImage: "clock"
                    )
                    .foregroundStyle(Color.white.opacity(0.88))
                    Spacer(minLength: 4)
                    Label(heartRateText, systemImage: "heart.fill")
                        .foregroundStyle(WatchTheme.liveHeart)
                }
                .font(.system(
                    size: compact ? 12 : 13,
                    weight: .semibold,
                    design: .rounded
                ))
                .monospacedDigit()
                .lineLimit(1)
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .frame(
                width: viewport.size.width,
                height: viewport.size.height,
                alignment: .topLeading
            )
            .background(WatchTheme.liveCanvas)
        }
        .background(WatchTheme.liveCanvas.ignoresSafeArea())
    }

    private var liveWorkoutStepTitle: String {
        if let step = workoutManager.currentStructuredRunningStep {
            return step.title
        }
        if let title = workoutManager.structuredRunningWorkout?.title,
           !title.isEmpty {
            return title
        }
        return ATHLTHLocalization.choose(
            english: "Current workout", norwegian: "Pågående økt"
        )
    }

    private func liveHeroMetric(
        title: String,
        value: String,
        unit: String,
        tint: Color,
        fontSize: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(tint)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(
                            size: fontSize,
                            weight: .bold,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text(unit)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.11),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 0.8)
        }
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
    private var treadmillInclinePage: some View {
        VStack(spacing: 10) {
            Text(
                ATHLTHLocalization.choose(
                    english: "Incline",
                    norwegian: "Stigning"
                )
            )
            .font(.headline)

            Text(
                String(
                    format: "%.1f%%",
                    workoutManager
                        .treadmillInclinePercent ??
                    0
                )
            )
            .font(
                .system(
                    size: 42,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()

            HStack(spacing: 12) {
                Button {
                    workoutManager
                        .setTreadmillInclinePercent(
                            (
                                workoutManager
                                    .treadmillInclinePercent ??
                                0
                            ) - 0.5
                        )
                } label: {
                    Image(systemName: "minus")
                        .font(.title3.bold())
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 44
                        )
                }
                .buttonStyle(.bordered)

                Button {
                    workoutManager
                        .setTreadmillInclinePercent(
                            (
                                workoutManager
                                    .treadmillInclinePercent ??
                                0
                            ) + 0.5
                        )
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.bold())
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 44
                        )
                }
                .buttonStyle(.borderedProminent)
            }

            Text(
                ATHLTHLocalization.choose(
                    english: "Adjust in 0.5% steps while you run.",
                    norwegian: "Juster i trinn på 0,5 % mens du løper."
                )
            )
            .font(.caption2)
            .foregroundStyle(
                WatchTheme.textSecondary
            )
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
    }

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

    // MARK: - Route navigation

    private var navigationPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                pageLabel(
                    "NAVIGATION",
                    icon:
                        "location.north.fill"
                )

                if let userCoordinate =
                        navigationUserCoordinate,
                   navigationRouteCoordinates
                    .count >= 2 {
                    Map(
                        position:
                            $navigationMapPosition,
                        interactionModes: []
                    ) {
                        MapPolyline(
                            coordinates:
                                navigationRouteCoordinates
                        )
                        .stroke(
                            WatchTheme.accent,
                            style:
                                StrokeStyle(
                                    lineWidth: 6,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                        )

                        Annotation(
                            "You",
                            coordinate:
                                userCoordinate,
                            anchor: .center
                        ) {
                            ZStack {
                                Circle()
                                    .fill(
                                        Color.white
                                    )
                                    .frame(
                                        width: 28,
                                        height: 28
                                    )

                                Image(
                                    systemName:
                                        "location.north.fill"
                                )
                                .font(
                                    .system(
                                        size: 14,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    Color(
                                        red: 0.10,
                                        green: 0.14,
                                        blue: 0.20
                                    )
                                )
                                .rotationEffect(
                                    .degrees(
                                        workoutManager
                                            .routeNavigationCourseDegrees ??
                                        0
                                    )
                                )
                            }
                            .overlay {
                                Circle()
                                    .stroke(
                                        WatchTheme
                                            .accent,
                                        lineWidth: 2
                                    )
                            }
                            .shadow(
                                color:
                                    Color.black
                                        .opacity(0.18),
                                radius: 2,
                                y: 1
                            )
                        }

                        if let finish =
                                navigationFinishCoordinate,
                           (
                                workoutManager
                                    .routeRemainingMeters ??
                                .greatestFiniteMagnitude
                           ) <= 550 {
                            Annotation(
                                "Finish",
                                coordinate:
                                    finish,
                                anchor: .center
                            ) {
                                Image(
                                    systemName:
                                        "flag.checkered"
                                )
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    .white
                                )
                                .frame(
                                    width: 25,
                                    height: 25
                                )
                                .background(
                                    Color.black
                                        .opacity(0.82),
                                    in: Circle()
                                )
                            }
                        }
                    }
                    .mapStyle(
                        .standard(
                            pointsOfInterest:
                                .excludingAll
                        )
                    )
                    .frame(height: 132)
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
                    .overlay(
                        alignment:
                            .topLeading
                    ) {
                        Text(
                            navigationStatusText
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .padding(
                            .horizontal,
                            8
                        )
                        .padding(
                            .vertical,
                            5
                        )
                        .background(
                            navigationStatusTint
                                .opacity(0.90),
                            in: Capsule()
                        )
                        .padding(6)
                    }
                    .onAppear {
                        updateNavigationMapCamera()
                    }
                    .onChange(
                        of:
                            workoutManager
                                .routeNavigationRevision
                    ) { _, _ in
                        updateNavigationMapCamera()
                    }
                } else {
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(
                                .small
                            )

                        Text(
                            "Finding your position…"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            WatchTheme.muted
                        )
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 112
                    )
                    .watchSurface(
                        radius: 18
                    )
                }

                HStack(spacing: 7) {
                    metricTile(
                        title: "REMAINING",
                        value:
                            remainingDistanceText,
                        suffix: "",
                        icon:
                            "flag.checkered"
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

                Text(
                    navigationInstructionText
                )
                .font(
                    .system(
                        size: 9,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    navigationStatusTint
                )
                .multilineTextAlignment(
                    .center
                )
                .frame(
                    maxWidth: .infinity
                )
                .padding(
                    .horizontal,
                    8
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var navigationUserCoordinate:
        CLLocationCoordinate2D? {
        guard let latitude =
                workoutManager
                    .routeNavigationLatitude,
              let longitude =
                workoutManager
                    .routeNavigationLongitude
        else {
            return nil
        }

        let coordinate =
            CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )

        return CLLocationCoordinate2DIsValid(
            coordinate
        )
            ? coordinate
            : nil
    }

    private var navigationRouteCoordinates:
        [CLLocationCoordinate2D] {
        guard let route =
                workoutManager
                    .plannedRoute
        else {
            return []
        }

        let points =
            route.points.sorted {
                $0.sequence <
                $1.sequence
            }

        guard points.count >= 2,
              let nearestIndex =
                workoutManager
                    .routeNavigationNearestPointIndex
        else {
            return points
                .prefix(40)
                .map {
                    CLLocationCoordinate2D(
                        latitude:
                            $0.latitude,
                        longitude:
                            $0.longitude
                    )
                }
        }

        let routeDistance =
            max(
                route
                    .distanceKilometers *
                    1_000,
                1
            )
        let averageSpacing =
            max(
                routeDistance /
                Double(
                    max(
                        points.count - 1,
                        1
                    )
                ),
                1
            )
        let behindCount =
            max(
                Int(
                    ceil(
                        55 /
                        averageSpacing
                    )
                ),
                2
            )
        let aheadCount =
            max(
                Int(
                    ceil(
                        450 /
                        averageSpacing
                    )
                ),
                12
            )
        let lower =
            max(
                nearestIndex -
                behindCount,
                0
            )
        let upper =
            min(
                nearestIndex +
                aheadCount,
                points.count - 1
            )

        guard lower <= upper
        else {
            return []
        }

        return points[
            lower...upper
        ]
        .map {
            CLLocationCoordinate2D(
                latitude:
                    $0.latitude,
                longitude:
                    $0.longitude
            )
        }
    }

    private var navigationFinishCoordinate:
        CLLocationCoordinate2D? {
        guard let point =
                workoutManager
                    .plannedRoute?
                    .points
                    .max(
                        by: {
                            $0.sequence <
                            $1.sequence
                        }
                    )
        else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude:
                point.latitude,
            longitude:
                point.longitude
        )
    }

    private var navigationStatusText:
        String {
        guard let deviation =
                workoutManager
                    .routeDeviationMeters
        else {
            return "ROUTE"
        }

        if deviation >
            workoutManager
                .routeAlertConfiguration
                .deviationMeters {
            return "OFF ROUTE"
        }

        return "ON ROUTE"
    }

    private var navigationStatusTint:
        Color {
        guard let deviation =
                workoutManager
                    .routeDeviationMeters
        else {
            return WatchTheme.accent
        }

        return deviation >
            workoutManager
                .routeAlertConfiguration
                .deviationMeters
            ? .orange
            : WatchTheme.accent
    }

    private var navigationInstructionText:
        String {
        guard let deviation =
                workoutManager
                    .routeDeviationMeters
        else {
            return "Follow the highlighted route."
        }

        if deviation >
            workoutManager
                .routeAlertConfiguration
                .deviationMeters {
            return "Move back toward the highlighted route."
        }

        return "Follow the highlighted route ahead."
    }

    private func updateNavigationMapCamera() {
        guard let user =
                navigationUserCoordinate
        else {
            return
        }

        let coordinates =
            [user] +
            navigationRouteCoordinates

        guard !coordinates.isEmpty
        else {
            return
        }

        let latitudes =
            coordinates.map(
                \.latitude
            )
        let longitudes =
            coordinates.map(
                \.longitude
            )

        guard let minLatitude =
                latitudes.min(),
              let maxLatitude =
                latitudes.max(),
              let minLongitude =
                longitudes.min(),
              let maxLongitude =
                longitudes.max()
        else {
            return
        }

        let center =
            CLLocationCoordinate2D(
                latitude:
                    (
                        minLatitude +
                        maxLatitude
                    ) / 2,
                longitude:
                    (
                        minLongitude +
                        maxLongitude
                    ) / 2
            )
        let latitudeSpan =
            max(
                (
                    maxLatitude -
                    minLatitude
                ) * 1.42,
                0.0012
            )
        let longitudeSpan =
            max(
                (
                    maxLongitude -
                    minLongitude
                ) * 1.42,
                0.0015
            )

        withAnimation(
            .easeInOut(
                duration: 0.24
            )
        ) {
            navigationMapPosition =
                .region(
                    MKCoordinateRegion(
                        center:
                            center,
                        span:
                            MKCoordinateSpan(
                                latitudeDelta:
                                    latitudeSpan,
                                longitudeDelta:
                                    longitudeSpan
                            )
                    )
                )
        }
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

                if let userCoordinate =
                        ghostMapUserCoordinate,
                   let ghostCoordinate =
                        ghostMapGhostCoordinate {
                    ghostProximityMap(
                        userCoordinate:
                            userCoordinate,
                        ghostCoordinate:
                            ghostCoordinate
                    )
                } else if routeCoordinates.count >= 2 {
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

    private func ghostProximityMap(
        userCoordinate:
            CLLocationCoordinate2D,
        ghostCoordinate:
            CLLocationCoordinate2D
    ) -> some View {
        Map(
            position:
                $ghostMapPosition,
            interactionModes: []
        ) {
            Annotation(
                "You",
                coordinate:
                    userCoordinate,
                anchor:
                    .center
            ) {
                ZStack {
                    Circle()
                        .fill(
                            Color(
                                red: 0.10,
                                green: 0.14,
                                blue: 0.20
                            )
                        )
                        .frame(
                            width: 22,
                            height: 22
                        )

                    Circle()
                        .stroke(
                            Color.white,
                            lineWidth: 2
                        )
                        .frame(
                            width: 22,
                            height: 22
                        )
                }
                .shadow(
                    color:
                        Color.black
                            .opacity(0.18),
                    radius: 2,
                    y: 1
                )
            }

            Annotation(
                "Ghost",
                coordinate:
                    ghostCoordinate,
                anchor:
                    .center
            ) {
                ZStack {
                    Circle()
                        .fill(
                            WatchTheme.accent
                        )
                        .frame(
                            width: 23,
                            height: 23
                        )

                    Image(
                        systemName:
                            "figure.run"
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                }
                .overlay {
                    Circle()
                        .stroke(
                            Color.white,
                            lineWidth: 1.5
                        )
                }
                .shadow(
                    color:
                        Color.black
                            .opacity(0.16),
                    radius: 2,
                    y: 1
                )
            }
        }
        .mapStyle(
            .standard(
                pointsOfInterest:
                    .excludingAll
            )
        )
        .frame(height: 112)
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
        .overlay(
            alignment:
                .bottomLeading
        ) {
            HStack(spacing: 8) {
                ghostMapLegendItem(
                    title: "You",
                    icon:
                        "circle.fill",
                    tint:
                        Color(
                            red: 0.10,
                            green: 0.14,
                            blue: 0.20
                        )
                )

                ghostMapLegendItem(
                    title: "Ghost",
                    icon:
                        "figure.run",
                    tint:
                        WatchTheme.accent
                )
            }
            .padding(
                .horizontal,
                7
            )
            .padding(
                .vertical,
                5
            )
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .padding(6)
        }
        .onAppear {
            updateGhostMapCamera(
                user:
                    userCoordinate,
                ghost:
                    ghostCoordinate
            )
        }
        .onChange(
            of:
                workoutManager
                    .ghostMapRevision
        ) { _, _ in
            guard let user =
                    ghostMapUserCoordinate,
                  let ghost =
                    ghostMapGhostCoordinate
            else {
                return
            }

            updateGhostMapCamera(
                user: user,
                ghost: ghost
            )
        }
    }

    private func ghostMapLegendItem(
        title: String,
        icon: String,
        tint: Color
    ) -> some View {
        Label {
            Text(title)
                .font(
                    .system(
                        size: 7.5,
                        weight: .semibold
                    )
                )
        } icon: {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 7,
                    weight: .bold
                )
            )
            .foregroundStyle(
                tint
            )
        }
        .foregroundStyle(
            WatchTheme.textPrimary
        )
    }

    private var ghostMapUserCoordinate:
        CLLocationCoordinate2D? {
        guard let latitude =
                workoutManager
                    .ghostMapUserLatitude,
              let longitude =
                workoutManager
                    .ghostMapUserLongitude
        else {
            return nil
        }

        let coordinate =
            CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )

        return CLLocationCoordinate2DIsValid(
            coordinate
        )
            ? coordinate
            : nil
    }

    private var ghostMapGhostCoordinate:
        CLLocationCoordinate2D? {
        guard let latitude =
                workoutManager
                    .ghostMapLatitude,
              let longitude =
                workoutManager
                    .ghostMapLongitude
        else {
            return nil
        }

        let coordinate =
            CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )

        return CLLocationCoordinate2DIsValid(
            coordinate
        )
            ? coordinate
            : nil
    }

    private func updateGhostMapCamera(
        user: CLLocationCoordinate2D,
        ghost: CLLocationCoordinate2D
    ) {
        let center =
            CLLocationCoordinate2D(
                latitude:
                    (
                        user.latitude +
                        ghost.latitude
                    ) / 2,
                longitude:
                    (
                        user.longitude +
                        ghost.longitude
                    ) / 2
            )

        let latitudeSpan =
            max(
                abs(
                    user.latitude -
                    ghost.latitude
                ) * 1.9,
                0.0014
            )
        let longitudeSpan =
            max(
                abs(
                    user.longitude -
                    ghost.longitude
                ) * 1.9,
                0.0018
            )

        withAnimation(
            .easeInOut(
                duration: 0.28
            )
        ) {
            ghostMapPosition =
                .region(
                    MKCoordinateRegion(
                        center:
                            center,
                        span:
                            MKCoordinateSpan(
                                latitudeDelta:
                                    latitudeSpan,
                                longitudeDelta:
                                    longitudeSpan
                            )
                    )
                )
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


private struct WatchATHLTHAlwaysOnMark:
    Shape {
    func path(
        in rect: CGRect
    ) -> Path {
        var path = Path()
        let midY =
            rect.midY

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: midY
            )
        )
        path.addLine(
            to: CGPoint(
                x:
                    rect.minX +
                    rect.width * 0.24,
                y: midY
            )
        )
        path.addLine(
            to: CGPoint(
                x:
                    rect.minX +
                    rect.width * 0.42,
                y:
                    rect.minY +
                    rect.height * 0.12
            )
        )
        path.addLine(
            to: CGPoint(
                x:
                    rect.minX +
                    rect.width * 0.58,
                y:
                    rect.maxY -
                    rect.height * 0.10
            )
        )
        path.addLine(
            to: CGPoint(
                x:
                    rect.minX +
                    rect.width * 0.72,
                y: midY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: midY
            )
        )

        return path
    }
}
