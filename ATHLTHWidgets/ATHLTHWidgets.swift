import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

private enum ATHLTHWidgetPalette {
    static let canvas = Color(
        red: 0.986,
        green: 0.978,
        blue: 0.962
    )
    static let card = Color(
        red: 0.965,
        green: 0.950,
        blue: 0.926
    )
    static let ink = Color(
        red: 0.07,
        green: 0.08,
        blue: 0.10
    )
    static let muted = Color(
        red: 0.43,
        green: 0.40,
        blue: 0.35
    )
    static let vitality = Color(
        red: 0.69,
        green: 0.53,
        blue: 0.31
    )
    static let brandGold = Color(
        red: 0.71,
        green: 0.55,
        blue: 0.31
    )
}

private struct ATHLTHSurfaceEntry: TimelineEntry {
    let date: Date
    let snapshot: ATHLTHSurfaceSnapshot
}

private struct ATHLTHSurfaceProvider: TimelineProvider {
    func placeholder(
        in context: Context
    ) -> ATHLTHSurfaceEntry {
        ATHLTHSurfaceEntry(
            date: Date(),
            snapshot: previewSnapshot
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (ATHLTHSurfaceEntry) -> Void
    ) {
        completion(
            ATHLTHSurfaceEntry(
                date: Date(),
                snapshot:
                    context.isPreview
                        ? previewSnapshot
                        : freshSnapshot()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion:
            @escaping (Timeline<ATHLTHSurfaceEntry>) -> Void
    ) {
        let entry = ATHLTHSurfaceEntry(
            date: Date(),
            snapshot: freshSnapshot()
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    Date().addingTimeInterval(
                        entry.snapshot.activeWorkout == nil ? 15 * 60 : 60
                    )
                )
            )
        )
    }

    /// Prevent stale iPhone/iPad workout telemetry from appearing active
    /// indefinitely after an app process, relay, or network interruption.
    private func freshSnapshot(at date: Date = .now) -> ATHLTHSurfaceSnapshot {
        var value = ATHLTHSurfaceSharedStore.load()
        if let workout = value.activeWorkout {
            let age = date.timeIntervalSince(workout.updatedAt)
            let permittedAge: TimeInterval =
                workout.state == "remote_strength" ? 90 : 180
            if age < -10 || age > permittedAge {
                value.activeWorkout = nil
            }
        }
        return value
    }

    private var previewSnapshot: ATHLTHSurfaceSnapshot {
        ATHLTHSurfaceSnapshot(
            recoveryScore: 82,
            recoveryState: "Ready",
            nextWorkoutTitle: "Easy run · 32 min",
            nextWorkoutDate:
                Date().addingTimeInterval(60 * 60 * 3),
            primaryGoalTitle: "10K under 45 min",
            primaryGoalProgress: 0.68,
            activeWorkout: nil,
            updatedAt: Date()
        )
    }
}

struct ATHLTHHomeWidget: Widget {
    let kind = "ATHLTHHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ATHLTHSurfaceProvider()
        ) { entry in
            ATHLTHHomeWidgetView(entry: entry)
                .containerBackground(
                    for: .widget
                ) {
                    LinearGradient(
                        colors: [
                            ATHLTHWidgetPalette.canvas,
                            ATHLTHWidgetPalette.card
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("ATHLTH")
        .description(
            "Recovery, your next workout and primary goal."
        )
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge
        ])
    }
}

private struct ATHLTHHomeWidgetView: View {
    @Environment(\.widgetFamily)
    private var family

    let entry: ATHLTHSurfaceEntry

    var body: some View {
        if let workout = entry.snapshot.activeWorkout {
            if family == .systemLarge {
                activeLargeView(workout)
            } else {
                activeWorkoutView(workout)
            }
        } else {
            switch family {
            case .systemLarge:
                largeView
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
    }

    private func counterLabel(
        _ workout: ATHLTHSurfaceWorkoutSnapshot
    ) -> String? {
        if let strengthCount = workout.strengthSetCount,
           strengthCount > 0,
           let setIndex = workout.strengthSetIndex {
            return "Sett \(min(max(setIndex, 1), strengthCount)) av \(strengthCount)"
        }
        return ATHLTHWidgetPresentationPolicy.intervalLabel(
            ordinal: workout.runningIntervalOrdinal,
            total: workout.runningIntervalTotal,
            isRecovery: workout.runningInRecovery == true
        )
    }

    private func timerCaption(
        _ workout: ATHLTHSurfaceWorkoutSnapshot
    ) -> String {
        if workout.strengthRestEndsAt != nil { return "SETTPAUSE" }
        if workout.runningInRecovery == true { return "PAUSE" }
        if ATHLTHWidgetPresentationPolicy.remainingSeconds(
            workout.runningStepRemainingSeconds
        ) != nil {
            return "TID IGJEN"
        }
        return "ØKTTID"
    }

    @ViewBuilder
    private func workoutTimer(
        _ workout: ATHLTHSurfaceWorkoutSnapshot,
        size: CGFloat
    ) -> some View {
        let paused = workout.state == "paused"
        let stepSeconds = ATHLTHWidgetPresentationPolicy.remainingSeconds(
            workout.runningStepRemainingSeconds
        )
        let anchor = ATHLTHWidgetPresentationPolicy.elapsedAnchor(
            updatedAt: workout.updatedAt,
            elapsedSeconds: workout.elapsedTime
        )

        Group {
            if paused {
                Text(ATHLTHWidgetPresentationPolicy.duration(
                    workout.strengthRestEndsAt.map {
                        max(0, $0.timeIntervalSince(workout.updatedAt))
                    } ?? stepSeconds ?? workout.elapsedTime
                ))
            } else if let restEnd = workout.strengthRestEndsAt {
                if restEnd > entry.date {
                    Text(timerInterval: workout.updatedAt...restEnd,
                         countsDown: true, showsHours: false)
                } else {
                    Text("KLAR")
                }
            } else if let stepSeconds {
                if stepSeconds > 0 {
                    Text(
                        timerInterval: workout.updatedAt...
                            workout.updatedAt.addingTimeInterval(stepSeconds),
                        countsDown: true, showsHours: false
                    )
                } else {
                    Text("00:00")
                }
            } else {
                Text(anchor, style: .timer)
            }
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .foregroundStyle(ATHLTHWidgetPalette.ink)
    }

    private func activityHeader(
        _ workout: ATHLTHSurfaceWorkoutSnapshot
    ) -> some View {
        HStack(spacing: 6) {
            ATHLTHMarkShape()
                .fill(ATHLTHWidgetPalette.brandGold)
                .frame(width: 18, height: 15)
                .accessibilityHidden(true)
            Text("ATHLTH")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(ATHLTHWidgetPalette.ink)
            Spacer(minLength: 3)
            Text(workout.state == "paused" ? "PAUSET" : "PÅGÅR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                .lineLimit(1)
        }
    }

    private func activeWorkoutView(
        _ workout: ATHLTHSurfaceWorkoutSnapshot
    ) -> some View {
        if family == .systemMedium {
            activeMediumView(workout)
        } else {
            activeSmallView(workout)
        }
    }

    private func activeSmallView(
        _ workout: ATHLTHSurfaceWorkoutSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            activityHeader(workout)

            Text(workout.currentStep ?? workout.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHWidgetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(timerCaption(workout))
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(ATHLTHWidgetPalette.muted)

            workoutTimer(workout, size: 33)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if let position = counterLabel(workout) {
                    Text(position)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else if let distance = ATHLTHWidgetPresentationPolicy.distanceLabel(
                    workout.distanceMeters
                ) {
                    Text(distance)
                } else if let pulse = ATHLTHWidgetPresentationPolicy.heartRateLabel(
                    workout.heartRate
                ) {
                    Text(pulse)
                } else {
                    Text(workout.title)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ATHLTHWidgetPalette.brandGold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func activeMediumView(
        _ workout: ATHLTHSurfaceWorkoutSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            activityHeader(workout)
            HStack(alignment: .center, spacing: 13) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(timerCaption(workout))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    workoutTimer(workout, size: 39)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(ATHLTHWidgetPalette.brandGold.opacity(0.18))
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 7) {
                    Text(workout.currentStep ?? workout.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHWidgetPalette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    if let position = counterLabel(workout) {
                        Text(position)
                            .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    HStack(spacing: 8) {
                        if let distance = ATHLTHWidgetPresentationPolicy.distanceLabel(
                            workout.distanceMeters
                        ) {
                            Label(distance, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        if let heart = ATHLTHWidgetPresentationPolicy.heartRateLabel(
                            workout.heartRate
                        ) {
                            Label(heart, systemImage: "heart.fill")
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(ATHLTHWidgetPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func activeLargeView(
        _ workout: ATHLTHSurfaceWorkoutSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            activityHeader(workout)
            Text(workout.currentStep ?? workout.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ATHLTHWidgetPalette.ink)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 3) {
                Text(timerCaption(workout))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHWidgetPalette.muted)
                workoutTimer(workout, size: 58)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if let interval = counterLabel(workout) {
                    activeMetric("INTERVALL / SETT", interval)
                }
                if let distance = ATHLTHWidgetPresentationPolicy.distanceLabel(
                    workout.distanceMeters
                ) {
                    activeMetric("DISTANSE", distance)
                }
                if let pulse = ATHLTHWidgetPresentationPolicy.heartRateLabel(
                    workout.heartRate
                ) {
                    activeMetric("PULS", pulse)
                }
            }

            if let next = workout.nextStep, !next.isEmpty {
                Label("Neste: \(next)", systemImage: "arrow.right.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ATHLTHWidgetPalette.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func activeMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ATHLTHWidgetPalette.muted)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHWidgetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHWidgetPalette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATHLTH")
                .font(.caption2.weight(.black))
                .tracking(2)
                .foregroundStyle(
                    ATHLTHWidgetPalette.ink
                )

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(
                        ATHLTHWidgetPalette.vitality
                    )

                Text(
                    entry.snapshot.recoveryScore
                        .map(String.init) ?? "—"
                )
                .font(.system(
                    size: 34,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(
                    ATHLTHWidgetPalette.ink
                )
            }

            Text(entry.snapshot.recoveryState)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    ATHLTHWidgetPalette.muted
                )
                .lineLimit(1)

            if let next =
                entry.snapshot.nextWorkoutTitle {
                Divider()

                Label(
                    next,
                    systemImage: "figure.run"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    ATHLTHWidgetPalette.ink
                )
                .lineLimit(2)
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text("RECOVERY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(
                        ATHLTHWidgetPalette.muted
                    )

                Text(
                    entry.snapshot.recoveryScore
                        .map(String.init) ?? "—"
                )
                .font(.system(
                    size: 32,
                    weight: .bold,
                    design: .rounded
                ))

                Text(entry.snapshot.recoveryState)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHWidgetPalette.muted
                    )
                    .lineLimit(1)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            Divider()

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                Text("NEXT")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(
                        ATHLTHWidgetPalette.muted
                    )

                Label(
                    entry.snapshot.nextWorkoutTitle ??
                        "No workout planned",
                    systemImage: "figure.run"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    ATHLTHWidgetPalette.ink
                )
                .lineLimit(2)

                if let date =
                    entry.snapshot.nextWorkoutDate {
                    Text(
                        date,
                        format:
                            .dateTime
                            .weekday(.abbreviated)
                            .hour()
                            .minute()
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHWidgetPalette.muted
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            if let goal =
                entry.snapshot.primaryGoalTitle {
                Divider()

                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    Text("GOAL")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(
                            ATHLTHWidgetPalette.muted
                        )

                    Text(goal)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHWidgetPalette.ink
                        )
                        .lineLimit(2)

                    if let progress =
                        entry.snapshot
                            .primaryGoalProgress {
                        ProgressView(
                            value:
                                min(max(progress, 0), 1)
                        )
                        .tint(
                            ATHLTHWidgetPalette.vitality
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
        }
    }
}

struct ATHLTHLockScreenWidget: Widget {
    let kind = "ATHLTHLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ATHLTHSurfaceProvider()
        ) { entry in
            ATHLTHLockScreenWidgetView(
                entry: entry
            )
            .containerBackground(
                for: .widget
            ) {
                Color.clear
            }
        }
        .configurationDisplayName(
            "ATHLTH Lock Screen"
        )
        .description(
            "Keep recovery and your active workout visible."
        )
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

private struct ATHLTHLockScreenWidgetView: View {
    @Environment(\.widgetFamily)
    private var family

    let entry: ATHLTHSurfaceEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryInline:
            inline
        default:
            rectangular
        }
    }

    private var circular: some View {
        Gauge(
            value:
                Double(
                    entry.snapshot.recoveryScore ?? 0
                ),
            in: 0...100
        ) {
            Image(systemName: "heart.fill")
        } currentValueLabel: {
            Text(
                entry.snapshot.recoveryScore
                    .map(String.init) ?? "—"
            )
            .font(.caption.weight(.bold))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var inline: some View {
        if let workout =
            entry.snapshot.activeWorkout {
            Label(
                "\(workout.title) · \(duration(workout.elapsedTime))",
                systemImage: workout.systemImage
            )
        } else {
            Label {
                Text("Recovery") +
                Text(
                    " \(entry.snapshot.recoveryScore.map(String.init) ?? "—")"
                )
            } icon: {
                Image(systemName: "heart.fill")
            }
        }
    }

    private var rectangular: some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            if let workout = entry.snapshot.activeWorkout {
                let paused = workout.state == "paused"
                let anchor = workout.updatedAt.addingTimeInterval(
                    -max(0, workout.elapsedTime)
                )
                let remaining = workout.runningStepRemainingSeconds
                HStack(spacing: 4) {
                    Label(workout.currentStep ?? workout.title,
                          systemImage: workout.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if let ordinal = workout.runningIntervalOrdinal,
                       let total = workout.runningIntervalTotal, total > 1 {
                        Text("\(ordinal)/\(total)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                    }
                }
                if let remaining, remaining.isFinite, remaining >= 0 {
                    if paused {
                        Text(duration(remaining))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text(timerInterval:
                            workout.updatedAt...workout.updatedAt.addingTimeInterval(remaining),
                            countsDown: true,
                            showsHours: false)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                } else if paused {
                    Text(duration(workout.elapsedTime))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text(anchor, style: .timer)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                if workout.distanceMeters > 0 {
                    Text(distance(workout.distanceMeters))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
            } else {
                HStack {
                    Label(
                        "Recovery",
                        systemImage: "heart.fill"
                    )

                    Spacer()

                    Text(
                        entry.snapshot.recoveryScore
                            .map(String.init) ?? "—"
                    )
                    .font(.headline)
                }

                Text(
                    entry.snapshot
                        .nextWorkoutTitle ??
                        entry.snapshot
                            .recoveryState
                )
                .font(.caption)
                .lineLimit(1)
            }
        }
    }

    private func duration(
        _ seconds: TimeInterval
    ) -> String {
        let total = max(Int(seconds), 0)
        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }

    private func distance(
        _ meters: Double
    ) -> String {
        String(
            format: "%.1f km",
            meters / 1000
        )
    }
}

/// iOS 27 can place two Live Activities side by side with reduced width.
/// Keep the readable training metric whenever there is room, rather than
/// constraining the entire Dynamic Island to the smallest presentation.
@available(iOS 27.0, *)
private struct ATHLTHAdaptiveCompactMetric: View {
    @Environment(\.isDynamicIslandLimitedInWidth)
    private var isLimitedInWidth

    let regular: String
    let condensed: String

    var body: some View {
        if isLimitedInWidth {
            Text(condensed)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 28, height: 28)
                .accessibilityLabel(regular)
        } else {
            Text(regular)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

/// Native timer keeps workout time moving smoothly between Watch snapshots.
/// iOS decides whether another Live Activity reduces the available width.
@available(iOS 27.0, *)
private struct ATHLTHAdaptiveCompactClock: View {
    @Environment(\.isDynamicIslandLimitedInWidth)
    private var isLimitedInWidth

    let elapsedAnchor: Date

    var body: some View {
        Text(elapsedAnchor, style: .timer)
            .font(.system(
                size: isLimitedInWidth ? 11 : 13,
                weight: .bold,
                design: .rounded
            ))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(isLimitedInWidth ? 0.70 : 0.85)
            .accessibilityLabel(Text(elapsedAnchor, style: .timer))
    }
}

struct ATHLTHWorkoutLiveActivity: Widget {
    private typealias Context =
        ActivityViewContext<ATHLTHWorkoutActivityAttributes>

    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: ATHLTHWorkoutActivityAttributes.self
        ) { context in
            unifiedLightLockScreenContent(context)
                .foregroundStyle(ATHLTHWidgetPalette.ink)
                .activityBackgroundTint(Color.white)
                .activitySystemActionForegroundColor(ATHLTHWidgetPalette.ink)
                // ActivityKit owns the outer card. A second generic 16-point
                // padding previously pushed long running content off-screen.
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        focusTitle(context),
                        systemImage: primarySymbol(context)
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(focusTint(context))
                    .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(compactValue(context))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        mainWorkoutHeadline(context)
                        if focus(context) != .workout {
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                if ATHLTHLiveActivityDisplayPolicy.isRecent(
                                    updatedAt: context.state.updatedAt,
                                    now: tick.date
                                ) {
                                    expandedBottom(context)
                                } else {
                                    delayedUpdateLabel
                                }
                            }
                        } else {
                            supportingMetrics(context)
                        }
                    }
                }
            } compactLeading: {
                compactActivityIdentity(context)
            } compactTrailing: {
                compactTrainingValue(context)
            } minimal: {
                compactActivityIdentity(context)
            }
        }
    }


    /// Strength uses a deliberately compact Live Activity. Earlier versions
    /// stacked multiple timers and long rows, overflowing the Lock Screen.
    /// Running and other sports keep their existing display unchanged.
    @ViewBuilder
    private func unifiedLightLockScreenContent(_ context: Context) -> some View {
        if context.state.workoutKindRaw == "strength",
           context.state.strengthRestEndsAt != nil,
           context.state.phase == "running" {
            expandedStrengthRestLockScreenContent(context)
        } else if context.state.workoutKindRaw == "strength" {
            compactStrengthLockScreenContent(context)
        } else if context.state.workoutKindRaw == "running" ||
                  context.state.workoutKindRaw == "walking" {
            compactCardioLockScreenContent(context)
        } else {
            generalLockScreenContent(context)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
    }

    /// One bounded design for running and walking, on all compatible iPhones.
    /// No stacked multi-line route/coach/status panels can escape the
    /// system Live Activity container. Active time and interval time use
    /// native system timers so they move even between sensor snapshots.
    private func compactCardioLockScreenContent(_ context: Context) -> some View {
        let state = context.state
        let paused = state.phase == "paused"
        let hasStepCountdown = state.runningStepRemainingSeconds.map {
            $0.isFinite && $0 >= 0
        } ?? false
        let recovery = state.runningInRecovery == true ||
            state.runningStepTitle?.localizedCaseInsensitiveContains("pause") == true
        let countLabel: String = {
            if let ordinal = state.runningIntervalOrdinal,
               let total = state.runningIntervalTotal, total > 1 {
                let position = recovery ? min(ordinal + 1, total) : ordinal
                return recovery
                    ? localized("NEXT", "NESTE") + " \(position) / \(total)"
                    : "\(ordinal) / \(total)"
            }
            if state.runningStepTitle != nil {
                return state.runningStepTitle ?? ""
            }
            return state.workoutDisplayTitle ?? context.attributes.workoutTitle
        }()
        let title = recovery
            ? localized("REST", "PAUSE")
            : state.runningStepTitle == nil
                ? (state.workoutKindRaw == "walking"
                    ? localized("WALKING", "GÅTUR")
                    : localized("RUNNING", "LØPING"))
                : state.runningStepTitle ?? ""
        let elapsedAnchor = state.updatedAt.addingTimeInterval(
            -max(0, state.elapsedTime.isFinite ? state.elapsedTime : 0)
        )
        let stepEnd = state.updatedAt.addingTimeInterval(
            max(0, state.runningStepRemainingSeconds ?? 0)
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ATHLTHMarkShape()
                    .fill(ATHLTHWidgetPalette.ink)
                    .frame(width: 21, height: 18)
                Text("ATHLTH")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.8)
                Spacer(minLength: 4)
                Text(paused ? localized("PAUSED", "PAUSET") :
                        localized("ACTIVE", "PÅGÅR"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 3)
                Text(countLabel)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .foregroundStyle(ATHLTHWidgetPalette.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasStepCountdown
                         ? (recovery
                             ? localized("NEXT INTERVAL IN", "NESTE DRAG OM")
                             : localized("TIME REMAINING", "TID IGJEN"))
                         : localized("WORKOUT TIME", "ØKTTID"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    if hasStepCountdown,
                       let remaining = state.runningStepRemainingSeconds {
                        if paused {
                            Text(duration(ceil(max(remaining, 0))))
                                .font(.system(size: 43, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        } else if remaining > 0 {
                            Text(
                                timerInterval: state.updatedAt...stepEnd,
                                countsDown: true,
                                showsHours: false
                            )
                            .font(.system(size: 43, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        } else {
                            Text("00:00")
                                .font(.system(size: 43, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                    } else if paused {
                        Text(duration(state.elapsedTime))
                            .font(.system(size: 43, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text(elapsedAnchor, style: .timer)
                            .font(.system(size: 43, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .frame(maxWidth: .infinity, alignment: .leading)

                if state.distanceMeters.isFinite, state.distanceMeters > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(localized("DISTANCE", "DISTANSE"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ATHLTHWidgetPalette.muted)
                        Text(distance(state.distanceMeters))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: 103, alignment: .trailing)
                }
            }

            if let next = state.runningNextStepTitle,
               !next.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.right.circle")
                    Text(localized("Next", "Neste") + ": " + next)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ATHLTHWidgetPalette.muted)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// During rest the countdown is the entire primary Lock Screen metric.
    /// The next action and heart rate remain legible but never compete with it.
    private func expandedStrengthRestLockScreenContent(
        _ context: Context
    ) -> some View {
        let state = context.state
        let end = state.strengthRestEndsAt ?? .now
        let remaining = end.timeIntervalSinceNow
        let nextTitle = state.strengthNextExerciseName
        let exercise = state.strengthExerciseName
            ?? localized("Strength", "Styrke")
        let setIndex = max(state.strengthSetIndex ?? 0, 0)
        let setCount = max(state.strengthSetCount ?? 0, 0)

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                ATHLTHMarkShape()
                    .fill(ATHLTHWidgetPalette.ink)
                    .frame(width: 19, height: 16)
                    .accessibilityHidden(true)
                Text("ATHLTH")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                Spacer()
                Text(localized("REST", "PAUSE"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ATHLTHWidgetPalette.brandGold)
            }

            HStack(alignment: .center, spacing: 10) {
                if remaining > 0 {
                    Text(
                        timerInterval: Date()...end,
                        countsDown: true,
                        showsHours: false
                    )
                    .font(.system(size: 61, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(localized("Rest time remaining", "Gjenstående pause"))
                } else {
                    Text(localized("READY", "KLAR"))
                        .font(.system(size: 43, weight: .bold, design: .rounded))
                        .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 7) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("UP NEXT", "ETTER PAUSEN"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    Text(
                        setCount > 0 && setIndex < setCount
                            ? "\(exercise) · \(setIndex + 1)/\(setCount)"
                            : (nextTitle ?? exercise)
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 6)
                if state.heartRate.isFinite, state.heartRate > 0 {
                    Text("\(Int(state.heartRate.rounded())) bpm")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                }
            }
        }
        .foregroundStyle(ATHLTHWidgetPalette.ink)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func compactStrengthLockScreenContent(_ context: Context) -> some View {
        let state = context.state
        let resting = state.strengthRestEndsAt != nil
        let paused = state.phase == "paused"
        let label = paused
            ? localized("PAUSED", "PAUSET")
            : resting
                ? localized("REST", "PAUSE")
                : localized("ACTIVE", "PÅGÅR")
        let exerciseName = state.strengthExerciseName
            ?? localized("Strength", "Styrke")
        let completedSet = max(state.strengthSetIndex ?? 1, 1)
        let totalSets = max(state.strengthSetCount ?? 1, 1)
        let restEndsAt = state.strengthRestEndsAt
        let remainingAtRender = restEndsAt?.timeIntervalSinceNow ?? 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ATHLTHMarkShape()
                    .fill(ATHLTHWidgetPalette.ink)
                    .frame(width: 21, height: 17)
                    .accessibilityHidden(true)
                Text("ATHLTH")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2.2)
                Spacer(minLength: 5)
                HStack(spacing: 5) {
                    Circle()
                        .fill(ATHLTHWidgetPalette.brandGold)
                        .frame(width: 7, height: 7)
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    ATHLTHWidgetPalette.brandGold.opacity(0.09),
                    in: Capsule()
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exerciseName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.77)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if (state.strengthSetCount ?? 0) > 0 {
                    Text("\(min(completedSet, totalSets))/\(totalSets)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                        .fixedSize()
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let restEndsAt {
                    Text(localized("Rest", "Pause"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    Spacer(minLength: 2)
                    if remainingAtRender > 0 {
                        // Apple's system-driven countdown clamps to zero.
                        // A date-style timer can produce a growing negative
                        // value that overlaps adjacent Lock Screen content.
                        Text(
                            timerInterval: Date()...restEndsAt,
                            countsDown: true,
                            showsHours: false
                        )
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 82, alignment: .trailing)
                    } else {
                        Text(localized("Ready", "Klar"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                    }
                } else if let target = state.strengthTimedSetTargetSeconds,
                          target > 0 {
                    Text(localized("Timed set", "Tidssett"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    Spacer(minLength: 2)
                    Text(duration(max(
                        state.strengthTimedSetSecondsAtSnapshot
                            ?? Double(target), 0
                    )))
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                } else if let reps = state.strengthReps, reps > 0 {
                    Label("\(reps) reps", systemImage: "repeat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 36)

            Rectangle()
                .fill(ATHLTHWidgetPalette.ink.opacity(0.09))
                .frame(height: 1)

            HStack(spacing: 12) {
                Label {
                    if paused || state.phase != "running" {
                        Text(duration(state.elapsedTime))
                    } else {
                        // Workout start includes pauses; anchor to active elapsed
                        // from the latest HealthKit snapshot instead.
                        Text(
                            state.updatedAt.addingTimeInterval(-max(state.elapsedTime, 0)),
                            style: .timer
                        )
                    }
                } icon: {
                    Image(systemName: "clock")
                }
                Spacer(minLength: 6)
                if state.heartRate.isFinite, state.heartRate > 0 {
                    Label(
                        "\(Int(state.heartRate.rounded())) bpm",
                        systemImage: "heart.fill"
                    )
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(ATHLTHWidgetPalette.muted)
        }
        .foregroundStyle(ATHLTHWidgetPalette.ink)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// Preserve the existing sport Live Activity outside strength workouts.
    private func generalLockScreenContent(_ context: Context) -> some View {
        let isStrength = context.state.workoutKindRaw == "strength"
        let headline = isStrength
            ? (context.state.strengthExerciseName ??
               localized("Strength training", "Styrketrening"))
            : (context.state.runningStepTitle ??
               context.state.workoutDisplayTitle ??
               context.attributes.workoutTitle)
        let isPaused = context.state.phase == "paused"
        let isResting = context.state.strengthRestEndsAt != nil

        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                ATHLTHMarkShape()
                    .fill(ATHLTHWidgetPalette.ink)
                    .frame(width: 23, height: 18)
                    .accessibilityHidden(true)
                Text("ATHLTH")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2.7)
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle()
                        .fill(ATHLTHWidgetPalette.brandGold)
                        .frame(width: 7, height: 7)
                    Text(
                        isPaused ? localized("PAUSED", "PAUSET") :
                        isResting ? localized("REST", "PAUSE") :
                        localized("ACTIVE", "PÅGÅR")
                    )
                    .lineLimit(1)
                }
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(ATHLTHWidgetPalette.brandGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(ATHLTHWidgetPalette.brandGold.opacity(0.09),
                            in: Capsule())
            }

            Rectangle()
                .fill(ATHLTHWidgetPalette.ink.opacity(0.09))
                .frame(height: 1)

            Text(headline)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ATHLTHWidgetPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 13) {
                if isStrength {
                    if let current = context.state.strengthSetIndex,
                       let total = context.state.strengthSetCount, total > 0 {
                        Label("\(min(max(current, 1), total))/\(total)",
                              systemImage: "list.number")
                    }
                    if let reps = context.state.strengthReps, reps > 0 {
                        Label("\(reps) reps", systemImage: "repeat")
                    }
                    if let target = context.state.strengthTimedSetTargetSeconds,
                       target > 0 {
                        Label(duration(Double(target)), systemImage: "timer")
                    }
                } else {
                    if context.state.distanceMeters.isFinite,
                       context.state.distanceMeters > 0 {
                        Label(distance(context.state.distanceMeters),
                              systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    if context.state.workoutKindRaw == "running",
                       context.state.currentPaceSecondsPerKilometer != nil {
                        Text(validPace(context.state.currentPaceSecondsPerKilometer) + "/km")
                    }
                    if let index = context.state.runningStepIndex,
                       let count = context.state.runningStepCount, count > 0 {
                        Text("\(index + 1)/\(count)")
                    }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ATHLTHWidgetPalette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.80)

            if let rest = context.state.strengthRestEndsAt {
                HStack {
                    Label(localized("Rest timer", "Pauseklokke"),
                          systemImage: "timer")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    Spacer()
                    Text(rest, style: .timer)
                        .font(.system(size: 27, weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else if let target = context.state.strengthTimedSetTargetSeconds,
                      target > 0, let remaining =
                      context.state.strengthTimedSetSecondsAtSnapshot {
                HStack {
                    Text(localized("Timed set", "Tidsbasert sett"))
                        .font(.caption)
                    Spacer()
                    Text(duration(remaining))
                        .font(.system(size: 24, weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                }
            }

            if let next = isStrength
                ? context.state.strengthNextExerciseName
                : context.state.runningNextStepTitle,
               !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Text(localized("Next", "Neste"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    Text(next)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !isStrength,
               let remaining = context.state.runningStepRemainingSeconds,
               remaining.isFinite {
                HStack(spacing: 8) {
                    Label(localized("Step remaining", "Tid igjen i steget"),
                          systemImage: "timer")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHWidgetPalette.muted)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        let consumed = context.state.phase == "running"
                            ? max(0, tick.date.timeIntervalSince(context.state.updatedAt))
                            : 0
                        Text(duration(ceil(max(0, remaining - consumed))))
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHWidgetPalette.ink)
                    }
                }
            }

            Rectangle()
                .fill(ATHLTHWidgetPalette.ink.opacity(0.09))
                .frame(height: 1)

            HStack(spacing: 10) {
                Label {
                    if isPaused || context.state.phase != "running" {
                        Text(duration(context.state.elapsedTime))
                    } else {
                        Text(
                            context.state.updatedAt.addingTimeInterval(
                                -max(context.state.elapsedTime, 0)
                            ),
                            style: .timer
                        )
                    }
                } icon: {
                    Image(systemName: "clock")
                }
                Spacer(minLength: 8)
                if context.state.heartRate.isFinite,
                   context.state.heartRate > 0 {
                    Label("\(Int(context.state.heartRate.rounded())) bpm",
                          systemImage: "heart.fill")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(ATHLTHWidgetPalette.muted)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func lockScreenContent(
        _ context: Context
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    context.state.strengthExerciseName != nil
                        ? (context.state.workoutDisplayTitle ??
                            context.attributes.workoutTitle)
                        : focusTitle(context),
                    systemImage: focusIcon(context)
                )
                .font(.headline)

                Spacer()

                Text(workoutPhaseLabel(context.state.phase))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(focusTint(context))
            }

            mainWorkoutHeadline(context)
            if focus(context) != .workout {
                TimelineView(.periodic(from: .now, by: 15)) { tick in
                    if ATHLTHLiveActivityDisplayPolicy.isRecent(
                        updatedAt: context.state.updatedAt,
                        now: tick.date
                    ) {
                        expandedBottom(context)
                    } else {
                        delayedUpdateLabel
                    }
                }
            } else {
                supportingMetrics(context)
            }
        }
    }

    private func workoutFocus(
        _ context: Context
    ) -> ATHLTHLiveActivityDisplayFocus {
        ATHLTHLiveActivityDisplayPolicy.resolve(
            kindRaw: context.state.workoutKindRaw,
            phase: context.state.phase,
            hasStrengthExercise: context.state.strengthExerciseName != nil,
            restEndsAt: context.state.strengthRestEndsAt,
            hasTimedSetCountdown:
                context.state.strengthTimedSetSecondsAtSnapshot != nil,
            hasRunningStep: context.state.runningStepTitle != nil,
            recordedDistanceMeters: context.state.distanceMeters
        )
    }

    /// Active or paused workouts use their sport icon. During transition
    /// phases the original ATHLTH mark appears instead of a generic spinner.
    @ViewBuilder
    private func compactActivityIdentity(_ context: Context) -> some View {
        if ATHLTHLiveActivityDisplayPolicy.showsBrandMark(
            phase: context.state.phase
        ) {
            ATHLTHMarkShape()
                .fill(ATHLTHWidgetPalette.brandGold)
                .frame(width: 23, height: 18)
                .accessibilityLabel("ATHLTH")
        } else {
            Image(systemName: compactSportSymbol(context))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isOffRoute(context) || context.state.phase == "paused"
                        ? Color.orange
                        : focusTint(context)
                )
                .accessibilityLabel(
                    context.state.workoutDisplayTitle ??
                    context.attributes.workoutTitle
                )
        }
    }

    private func compactSportSymbol(_ context: Context) -> String {
        // A route warning takes priority, without changing the workout.
        if isOffRoute(context) { return "exclamationmark.triangle.fill" }
        if context.state.workoutKindRaw == "strength" ||
           context.state.strengthExerciseName != nil {
            return "dumbbell.fill"
        }
        switch context.state.workoutKindRaw {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        default: return context.attributes.systemImage
        }
    }

    private func primarySymbol(_ context: Context) -> String {
        if isOffRoute(context) { return "exclamationmark.triangle.fill" }
        switch workoutFocus(context) {
        case .paused: return "pause.fill"
        case .strengthRest, .strengthTimedSet: return "timer"
        case .strengthSet: return "dumbbell.fill"
        case .runningInterval, .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .elapsed: return context.attributes.systemImage
        }
    }

    private func mainWorkoutHeadline(_ context: Context) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            switch workoutFocus(context) {
            case .paused:
                Label(
                    localized("Workout paused", "Økten er pauset"),
                    systemImage: "pause.circle.fill"
                )
                .font(.subheadline.weight(.bold))
                Text(duration(context.state.elapsedTime))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()

            case .strengthRest:
                Text(
                    context.state.strengthExerciseName ??
                        localized("Rest between sets", "Pause mellom sett")
                )
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                if let end = context.state.strengthRestEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let remaining = end.timeIntervalSince(timeline.date)
                        Text(remaining > 0
                            ? duration(ceil(remaining))
                            : localized("READY", "KLAR"))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                    Text(localized(
                        "Continue manually when ready",
                        "Fortsett manuelt når du er klar"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                }

            case .strengthTimedSet:
                Text(
                    context.state.strengthExerciseName ??
                        localized("Timed set", "Tidsbasert sett")
                )
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = ATHLTHLiveActivityDisplayPolicy
                        .remainingTimedSet(
                            secondsAtSnapshot:
                                context.state.strengthTimedSetSecondsAtSnapshot,
                            resumedAt: context.state.strengthTimedSetResumedAt,
                            now: timeline.date
                        )
                    Text(remaining.map { $0 > 0
                        ? duration(ceil($0))
                        : localized("READY", "KLAR")
                    } ?? "—")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }

            case .strengthSet:
                Text(context.state.strengthExerciseName ??
                     localized("Strength", "Styrke"))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                HStack(spacing: 10) {
                    if let reps = context.state.strengthReps {
                        Text("\(reps) reps")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    }
                    if let set = context.state.strengthSetIndex,
                       let count = context.state.strengthSetCount,
                       count > 0 {
                        Text(localized("Set", "Sett") +
                             " \(min(max(set, 1), count))/\(count)")
                            .font(.caption.weight(.semibold))
                    }
                    if let weight = context.state.strengthWeightKilograms,
                       weight.isFinite, weight > 0 {
                        Text(String(format: "%.1f kg", weight))
                            .font(.caption.weight(.semibold))
                    }
                }

            case .runningInterval:
                Text(context.state.runningStepTitle ??
                     localized("Interval", "Intervall"))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let seconds = context.state.runningStepRemainingSeconds,
                       seconds.isFinite {
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            let consumed = context.state.phase == "running"
                                ? max(0, tick.date.timeIntervalSince(context.state.updatedAt))
                                : 0
                            Text(duration(ceil(max(seconds - consumed, 0))))
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                        }
                        Text(localized("left", "igjen"))
                            .font(.caption2)
                    } else if let meters =
                        context.state.runningStepRemainingMeters,
                              meters.isFinite {
                        Text(distance(meters))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text(localized("left", "igjen"))
                            .font(.caption2)
                    } else if let progress =
                        ATHLTHLiveActivityDisplayPolicy.safeProgress(
                            context.state.runningStepProgress
                        ) {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    } else {
                        Text(localized("Open interval", "Åpent intervall"))
                            .font(.caption.weight(.semibold))
                    }
                }

            case .running:
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(validPace(context.state.currentPaceSecondsPerKilometer))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("/km")
                        .font(.caption.weight(.semibold))
                }
                Text(distance(context.state.distanceMeters))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

            case .walking:
                Text(distance(context.state.distanceMeters))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(localized("Walking", "Gåtur"))
                    .font(.caption.weight(.semibold))

            case .cycling:
                Text(distance(context.state.distanceMeters))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(localized("Recorded cycling distance", "Målt sykkeldistanse"))
                    .font(.caption.weight(.semibold))

            case .elapsed:
                Text(duration(context.state.elapsedTime))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The compact Island must coexist with music and other system
    /// activities. Expanded and Lock Screen views keep full descriptions.
    private func compactIslandValue(_ context: Context) -> String {
        switch workoutFocus(context) {
        case .paused:
            return "PAUSE"
        case .strengthRest:
            return localized("REST", "PAUSE")
        case .strengthTimedSet:
            return localized("TIME", "TID")
        case .strengthSet:
            if let reps = context.state.strengthReps {
                return ATHLTHLiveActivityDisplayPolicy.compactRepetitions(reps)
            }
            if let set = context.state.strengthSetIndex,
               let count = context.state.strengthSetCount, count > 0 {
                return "\(min(max(set, 1), count))/\(count)"
            }
            return "—"
        case .runningInterval:
            if let seconds = context.state.runningStepRemainingSeconds,
               seconds.isFinite {
                return ATHLTHLiveActivityDisplayPolicy
                    .compactDuration(ceil(max(seconds, 0)))
            }
            if let meters = context.state.runningStepRemainingMeters {
                return ATHLTHLiveActivityDisplayPolicy.compactDistance(meters)
            }
            if let progress = ATHLTHLiveActivityDisplayPolicy.safeProgress(
                context.state.runningStepProgress
            ) {
                return "\(Int((progress * 100).rounded()))%"
            }
            return "INT"
        case .running:
            return validPace(context.state.currentPaceSecondsPerKilometer)
        case .walking, .cycling:
            return ATHLTHLiveActivityDisplayPolicy.compactDistance(
                context.state.distanceMeters
            )
        case .elapsed:
            return ATHLTHLiveActivityDisplayPolicy.compactDuration(
                context.state.elapsedTime
            )
        }
    }

    /// Use the full value in a normal compact Island. Only reduce it when
    /// iOS reports that adjacent Live Activities make the Island narrower.
    @ViewBuilder
    private func compactIslandText(
        _ regular: String,
        condensed: String
    ) -> some View {
        if #available(iOS 27.0, *) {
            ATHLTHAdaptiveCompactMetric(
                regular: regular,
                condensed: condensed
            )
        } else {
            Text(regular)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// Text(status) is used only while the Live Activity is preparing,
    /// ending or finished. No ongoing activity is created just for branding.
    private func compactTransitionLabel(_ phase: String) -> String {
        switch phase {
        case "preparing": return localized("STARTING", "STARTER")
        case "ending": return localized("FINISHING", "AVSLUTTER")
        case "completed": return localized("DONE", "FERDIG")
        case "failed": return localized("ERROR", "FEIL")
        default: return "ATHLTH"
        }
    }

    @ViewBuilder
    private func compactElapsedClock(_ context: Context) -> some View {
        // Keep snapshot freshness checks on a one-second cadence. The
        // anchored system timer renders its digits independently of network
        // and Watch snapshot delivery, without requiring a new HK update.
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            if context.state.phase == "paused" ||
               context.state.phase == "ending" ||
               context.state.phase == "completed" {
                // Never leave a system timer running after pause or finish.
                compactIslandText(
                    ATHLTHLiveActivityDisplayPolicy.compactDuration(
                        context.state.elapsedTime
                    ),
                    condensed: ATHLTHLiveActivityDisplayPolicy.compactDuration(
                        context.state.elapsedTime
                    )
                )
            } else if context.state.phase == "running",
                      ATHLTHLiveActivityDisplayPolicy.isRecent(
                          updatedAt: context.state.updatedAt,
                          now: tick.date
                      ), context.state.elapsedTime.isFinite,
                      context.state.elapsedTime >= 0 {
                // Anchored to the latest captured workout elapsed time, not
                // wall-clock workout start (which can include paused time).
                let anchor = context.state.updatedAt.addingTimeInterval(
                    -context.state.elapsedTime
                )
                if #available(iOS 27.0, *) {
                    ATHLTHAdaptiveCompactClock(elapsedAnchor: anchor)
                } else {
                    Text(anchor, style: .timer)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                compactIslandText("—", condensed: "—")
            }
        }
    }

    @ViewBuilder
    private func compactTrainingValue(_ context: Context) -> some View {
        let metric = ATHLTHLiveActivityDisplayPolicy.compactMetric(
            focus: workoutFocus(context),
            pace: context.state.currentPaceSecondsPerKilometer,
            distanceMeters: context.state.distanceMeters
        )

        if ATHLTHLiveActivityDisplayPolicy.showsBrandMark(
            phase: context.state.phase
        ) {
            compactIslandText(
                compactTransitionLabel(context.state.phase),
                condensed: compactTransitionLabel(context.state.phase)
            )
        } else if metric == .paused {
            compactIslandText(
                localized("PAUSED", "PAUSE"),
                condensed: "PAUSE"
            )
        } else if metric == .strengthRest,
                  let ends = context.state.strengthRestEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = ceil(ends.timeIntervalSince(timeline.date))
                compactIslandText(
                    remaining > 0
                        ? duration(remaining)
                        : localized("READY", "KLAR"),
                    condensed: remaining > 0
                        ? ATHLTHLiveActivityDisplayPolicy.compactDuration(
                            remaining
                        )
                        : localized("READY", "KLAR")
                )
            }
        } else if metric == .strengthTimedSet {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let left = ATHLTHLiveActivityDisplayPolicy.remainingTimedSet(
                    secondsAtSnapshot:
                        context.state.strengthTimedSetSecondsAtSnapshot,
                    resumedAt: context.state.strengthTimedSetResumedAt,
                    now: timeline.date
                )
                compactIslandText(
                    left.map { $0 > 0
                        ? duration(ceil($0))
                        : localized("READY", "KLAR")
                    } ?? "—",
                    condensed: left.map { $0 > 0
                        ? ATHLTHLiveActivityDisplayPolicy.compactDuration(
                            ceil($0)
                        )
                        : localized("READY", "KLAR")
                    } ?? "—"
                )
            }
        } else if metric == .elapsed || metric == .strengthRest {
            compactElapsedClock(context)
        } else if metric == .runningInterval,
                  let remaining = context.state.runningStepRemainingSeconds,
                  remaining.isFinite {
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                let isCurrent = ATHLTHLiveActivityDisplayPolicy.isRecent(
                    updatedAt: context.state.updatedAt, now: tick.date
                )
                let spent = context.state.phase == "running"
                    ? max(0, tick.date.timeIntervalSince(context.state.updatedAt))
                    : 0
                let left = max(0, remaining - spent)
                let value = isCurrent
                    ? ATHLTHLiveActivityDisplayPolicy.compactDuration(ceil(left))
                    : "—"
                compactIslandText(value, condensed: value)
            }
        } else {
            TimelineView(.periodic(from: .now, by: 15)) { tick in
                let isCurrent = ATHLTHLiveActivityDisplayPolicy.isRecent(
                    updatedAt: context.state.updatedAt,
                    now: tick.date
                )
                compactIslandText(
                    isCurrent ? compactValue(context) : "—",
                    condensed: isCurrent ? compactIslandValue(context) : "—"
                )
            }
        }
    }

    private var delayedUpdateLabel: some View {
        Label(
            localized("Workout data delayed", "Treningsdata forsinket"),
            systemImage: "wifi.exclamationmark"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
    }

    private func supportingMetrics(_ context: Context) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            HStack(spacing: 12) {
                if ATHLTHLiveActivityDisplayPolicy.isRecent(
                    updatedAt: context.state.updatedAt,
                    now: timeline.date
                ) {
                    Label(
                        duration(context.state.elapsedTime),
                        systemImage: "clock"
                    )
                    if context.state.distanceMeters.isFinite,
                       context.state.distanceMeters > 0 {
                        Text(distance(context.state.distanceMeters))
                    }
                } else {
                    Label(
                        localized(
                            "Workout data delayed",
                            "Treningsdata forsinket"
                        ),
                        systemImage: "wifi.exclamationmark"
                    )
                }
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
        }
    }

    private func validPace(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 120, value <= 1_800
        else { return "—:—" }
        let seconds = Int(value.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func localized(_ en: String, _ no: String) -> String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return ["nb", "nn", "no"].contains(code) ? no : en
    }

    @ViewBuilder
    private func expandedBottom(
        _ context: Context
    ) -> some View {
        switch focus(context) {
        case .routeGuardian:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            isOffRoute(context)
                                ? routeDeviationText(context)
                                : routeRemainingText(context)
                        )
                        .font(.title3.weight(.bold))
                        .monospacedDigit()

                        Text(
                            isOffRoute(context)
                                ? "Return to route"
                                : "Remaining"
                        )
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.66))
                    }

                    Spacer()

                    if let progress =
                        context.state.routeProgressPercent {
                        Text(
                            "\(Int(min(max(progress, 0), 100).rounded()))%"
                        )
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    }
                }

                if let step =
                    context.state.runningStepTitle {
                    HStack(spacing: 8) {
                        Image(
                            systemName:
                                "figure.run.circle.fill"
                        )
                        .foregroundStyle(.green)

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(step)
                                .font(
                                    .caption
                                        .weight(.semibold)
                                )
                                .lineLimit(1)

                            if let next =
                                context.state
                                    .runningNextStepTitle {
                                (
                                    Text("Next:") +
                                    Text(" \(next)")
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .white.opacity(0.62)
                                )
                                .lineLimit(1)
                            }
                        }

                        Spacer()

                        runningStepLabel(context)
                    }
                }
            }

        case .zoneLock:
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        context.state.heartRate > 0
                            ? "\(Int(context.state.heartRate.rounded())) bpm"
                            : "Heart rate"
                    )
                    .font(.title3.weight(.bold))
                    .monospacedDigit()

                    Text(zoneTargetText(context))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer()

                Text(
                    context.state.heartRateTargetStatus ??
                    "Zone active"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(focusTint(context))
                .lineLimit(1)
            }

        case .ghostGap:
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        context.state.ghostDistanceDeltaMeters
                            .map(ghostDistanceText) ??
                        context.state.ghostRaceTitle ??
                        "Ghost"
                    )
                    .font(.title3.weight(.bold))
                    .lineLimit(1)

                    Text("YOU vs GHOST")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer()

                if let delta =
                    context.state.ghostTimeDeltaSeconds {
                    Text(ghostTimeText(delta))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
            }

        case .liveChallenge:
            let challenge =
                context.state.liveContext.challenge

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge?.title ?? "Challenge")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)

                    if let target =
                        challenge?.targetDistanceMeters,
                       target > 0 {
                        Text(
                            String(
                                format: "%.1f / %.1f km",
                                context.state.distanceMeters / 1_000,
                                target / 1_000
                            )
                        )
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    }
                }

                Spacer()

                if let projected =
                    challenge?.projectedFinishSeconds {
                    Text(duration(projected))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }

        case .liveShare:
            let share =
                context.state.liveContext.liveShare

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "LIVE · \(max(share?.viewerCount ?? 0, 0))"
                    )
                    .font(.title3.weight(.bold))
                    .monospacedDigit()

                    Text(
                        share?.viewerSummary ??
                        "Location sharing active"
                    )
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
                }

                Spacer()

                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

        case .workout:
            VStack(alignment: .leading, spacing: 8) {
                if context.state.strengthExerciseName != nil {
                    strengthSummary(context)
                }

                if let step =
                    context.state.runningStepTitle {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(step)
                                .font(
                                    .subheadline
                                        .weight(.bold)
                                )
                                .lineLimit(1)

                            if let next =
                                context.state
                                    .runningNextStepTitle {
                                (
                                    Text("Next:") +
                                    Text(" \(next)")
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .white.opacity(0.62)
                                )
                                .lineLimit(1)
                            }
                        }

                        Spacer()

                        runningStepLabel(context)
                    }
                }

                HStack(spacing: 18) {
                    liveDuration(context)

                    if context.state.distanceMeters > 0 {
                        metric(
                            value: String(
                                format: "%.2f",
                                context.state.distanceMeters / 1_000
                            ),
                            label: "KM"
                        )
                    }

                    if context.state.heartRate > 0 {
                        metric(
                            value:
                                String(
                                    Int(
                                        context.state
                                            .heartRate
                                            .rounded()
                                    )
                                ),
                            label: "BPM"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func strengthSummary(
        _ context: Context
    ) -> some View {
        if let exerciseName = context.state.strengthExerciseName {
            VStack(alignment: .leading, spacing: 5) {
                Text(exerciseName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if let setCount = context.state.strengthSetCount,
                       setCount > 0 {
                        let setNumber = min(
                            max(context.state.strengthSetIndex ?? 1, 1),
                            setCount
                        )
                        Label(
                            "\(setNumber) / \(setCount) sett",
                            systemImage: "list.number"
                        )
                    }

                    if let reps = context.state.strengthReps {
                        Label(
                            "\(reps) reps",
                            systemImage: "repeat"
                        )
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.80))

                if let restEndsAt = context.state.strengthRestEndsAt {
                    HStack(spacing: 8) {
                        Label("Pause", systemImage: "timer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))

                        Text(restEndsAt, style: .timer)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private func workoutPhaseLabel(_ phase: String) -> String {
        let norwegian = ["nb", "nn", "no"].contains(
            Locale.current.language.languageCode?.identifier ?? ""
        )

        switch phase {
        case "running": return norwegian ? "Pågår" : "Active"
        case "paused": return norwegian ? "Pauset" : "Paused"
        case "preparing": return norwegian ? "Klargjør" : "Preparing"
        case "ending": return norwegian ? "Avslutter" : "Finishing"
        case "completed": return norwegian ? "Fullført" : "Completed"
        case "failed": return norwegian ? "Feil" : "Error"
        default: return phase.capitalized
        }
    }

    private func focus(
        _ context: Context
    ) -> ATHLTHLiveWorkoutFocus {
        ATHLTHLiveWorkoutPriorityResolver.resolve(
            configuration:
                context.state.surfaceConfiguration,
            state: ATHLTHLiveWorkoutPriorityState(
                hasRoute:
                    context.state.routeProgressPercent != nil ||
                    context.state.routeRemainingMeters != nil ||
                    context.state.routeDeviationMeters != nil,
                routeDeviationMeters:
                    context.state.routeDeviationMeters,
                routeDeviationThresholdMeters:
                    context.state.routeDeviationThresholdMeters,
                hasZoneTarget:
                    context.state.heartRateTargetZone != nil ||
                    (
                        context.state
                            .heartRateTargetMinimumBPM != nil &&
                        context.state
                            .heartRateTargetMaximumBPM != nil
                    ),
                zoneStatus:
                    context.state.heartRateTargetStatus,
                hasGhost:
                    context.state.ghostRaceTitle != nil,
                hasChallenge:
                    context.state.liveContext.challenge != nil,
                hasLiveShare:
                    context.state.liveContext
                        .liveShare?.isSharing == true
            )
        )
    }

    private func focusTitle(
        _ context: Context
    ) -> String {
        switch focus(context) {
        case .routeGuardian:
            return isOffRoute(context)
                ? "Off Route"
                : "Route Guardian"
        case .zoneLock:
            return context.state.heartRateTargetZone
                .map { "Zone \($0)" } ??
                "Zone Lock"
        case .ghostGap:
            return "Ghost Gap"
        case .liveChallenge:
            return "Live Challenge"
        case .liveShare:
            return "Live Share"
        case .workout:
            return context.state.workoutDisplayTitle ??
                context.attributes.workoutTitle
        }
    }

    private func focusIcon(
        _ context: Context
    ) -> String {
        switch focus(context) {
        case .routeGuardian:
            return isOffRoute(context)
                ? "exclamationmark.triangle.fill"
                : "location.fill"
        case .zoneLock:
            return "heart.fill"
        case .ghostGap:
            return "figure.run"
        case .liveChallenge:
            return "trophy.fill"
        case .liveShare:
            return "dot.radiowaves.left.and.right"
        case .workout:
            return context.attributes.systemImage
        }
    }

    private func focusTint(
        _ context: Context
    ) -> Color {
        switch focus(context) {
        case .routeGuardian where isOffRoute(context):
            return .orange
        case .zoneLock:
            let status =
                context.state.heartRateTargetStatus?
                    .lowercased()
            return status == nil ||
                status == "on target" ||
                status == "in target"
                ? .green
                : .orange
        case .liveShare:
            return .green
        default:
            return .green
        }
    }

    private func compactValue(
        _ context: Context
    ) -> String {
        switch workoutFocus(context) {
        case .paused: return localized("PAUSED", "PAUSE")
        case .strengthRest: return localized("REST", "PAUSE")
        case .strengthTimedSet: return localized("SET TIME", "SETTID")
        case .strengthSet:
            if let reps = context.state.strengthReps { return "\(reps) reps" }
            return localized("STRENGTH", "STYRKE")
        case .runningInterval:
            if let seconds = context.state.runningStepRemainingSeconds,
               seconds.isFinite { return duration(ceil(max(seconds, 0))) }
            if let meters = context.state.runningStepRemainingMeters,
               meters.isFinite { return distance(meters) }
            if let progress = ATHLTHLiveActivityDisplayPolicy.safeProgress(
                context.state.runningStepProgress
            ) { return "\(Int((progress * 100).rounded()))%" }
            return localized("INTERVAL", "INTERVALL")
        case .running:
            return validPace(context.state.currentPaceSecondsPerKilometer)
        case .walking:
            return distance(context.state.distanceMeters)
        case .cycling:
            return distance(context.state.distanceMeters)
        case .elapsed:
            return duration(context.state.elapsedTime)
        }
    }

    private func legacyPriorityValue(
        _ context: Context
    ) -> String {
        switch focus(context) {
        case .routeGuardian:
            return isOffRoute(context)
                ? routeDeviationText(context)
                : routeRemainingText(context)
        case .zoneLock:
            return context.state.heartRate > 0
                ? "\(Int(context.state.heartRate.rounded()))"
                : "Z"
        case .ghostGap:
            return context.state.ghostTimeDeltaSeconds
                .map(ghostTimeText) ?? "GHOST"
        case .liveChallenge:
            if let target =
                context.state.liveContext
                    .challenge?.targetDistanceMeters,
               target > 0 {
                return String(
                    format: "%.1f/%.1f",
                    context.state.distanceMeters / 1_000,
                    target / 1_000
                )
            }
            return "LIVE"
        case .liveShare:
            return "LIVE · \(max(context.state.liveContext.liveShare?.viewerCount ?? 0, 0))"
        case .workout:
            return compactValue(context)
        }
    }

    @ViewBuilder
    private func runningStepLabel(
        _ context: Context
    ) -> some View {
        VStack(
            alignment: .trailing,
            spacing: 2
        ) {
            if let index =
                    context.state.runningStepIndex,
               let count =
                    context.state.runningStepCount,
               count > 0 {
                Text(
                    "\(index + 1)/\(count)"
                )
                .font(
                    .caption2.weight(.bold)
                )
                .monospacedDigit()
            }

            if let progress =
                context.state.runningStepProgress {
                Text(
                    "\(Int(min(max(progress, 0), 1) * 100))%"
                )
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(
                    .white.opacity(0.70)
                )
            }
        }
    }

    private func isOffRoute(
        _ context: Context
    ) -> Bool {
        guard let deviation =
                context.state.routeDeviationMeters,
              let threshold =
                context.state
                    .routeDeviationThresholdMeters
        else {
            return false
        }

        return deviation > threshold
    }

    private func routeDeviationText(
        _ context: Context
    ) -> String {
        distance(
            context.state.routeDeviationMeters
        )
    }

    private func routeRemainingText(
        _ context: Context
    ) -> String {
        distance(
            context.state.routeRemainingMeters
        )
    }

    private func zoneTargetText(
        _ context: Context
    ) -> String {
        if let low =
                context.state
                    .heartRateTargetMinimumBPM,
           let high =
                context.state
                    .heartRateTargetMaximumBPM {
            return "\(Int(low.rounded()))–\(Int(high.rounded())) bpm"
        }

        return context.state.heartRateTargetZone
            .map { "Target Z\($0)" } ??
            "Target heart rate"
    }

    @ViewBuilder
    private func liveDuration(
        _ context: Context
    ) -> some View {
        // A timer starting at workout launch would incorrectly keep counting
        // through pause periods. Use the HealthKit-recorded active elapsed.
        Text(duration(context.state.elapsedTime))
            .font(.title3.weight(.bold))
            .monospacedDigit()
    }

    private func metric(
        value: String,
        label: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    .white.opacity(0.66)
                )
        }
    }

    private func distance(
        _ meters: Double?
    ) -> String {
        guard let meters,
              meters.isFinite
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

    private func ghostDistanceText(
        _ delta: Double
    ) -> String {
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
            delta >= 0 ? "−" : "+"

        if seconds >= 60 {
            return prefix +
                String(
                    format: "%d:%02d",
                    seconds / 60,
                    seconds % 60
                )
        }

        return prefix + "\(seconds)s"
    }

    private func duration(
        _ seconds: TimeInterval
    ) -> String {
        let total = max(Int(seconds), 0)

        if total >= 3_600 {
            return String(
                format: "%d:%02d:%02d",
                total / 3_600,
                (total % 3_600) / 60,
                total % 60
            )
        }

        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }
}


private struct ATHLTHAliveEyes: View {
    var body: some View {
        HStack(spacing: 3) {
            Capsule().fill(.white).frame(width: 4, height: 9)
            Capsule().fill(.white).frame(width: 4, height: 9)
        }
        .accessibilityLabel("ATHLTH Alive")
    }
}

/// Experimental Live Activity. iOS owns the physical camera/sensor cutout;
/// the eyes render in supported ActivityKit regions, not over the cutout.
struct ATHLTHAliveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ATHLTHAliveActivityAttributes.self) { _ in
            HStack(spacing: 12) {
                ATHLTHAliveEyes()
                Text("ATHLTH Alive")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ATHLTHAliveEyes()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("ATHLTH Alive")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } compactLeading: {
                Capsule().fill(.white).frame(width: 4, height: 9)
            } compactTrailing: {
                Capsule().fill(.white).frame(width: 4, height: 9)
            } minimal: {
                ATHLTHAliveEyes()
            }
        }
    }
}

@main
struct ATHLTHWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ATHLTHHomeWidget()
        ATHLTHLockScreenWidget()
        ATHLTHWorkoutLiveActivity()
        ATHLTHAliveLiveActivity()
    }
}
