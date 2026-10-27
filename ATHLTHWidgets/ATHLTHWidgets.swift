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
        red: 0.955,
        green: 0.958,
        blue: 0.950
    )
    static let ink = Color(
        red: 0.07,
        green: 0.08,
        blue: 0.10
    )
    static let muted = Color(
        red: 0.43,
        green: 0.46,
        blue: 0.53
    )
    static let vitality = Color(
        red: 0.24,
        green: 0.47,
        blue: 0.38
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
                        : ATHLTHSurfaceSharedStore.load()
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
            snapshot: ATHLTHSurfaceSharedStore.load()
        )

        completion(
            Timeline(
                entries: [entry],
                policy: .after(
                    Date().addingTimeInterval(15 * 60)
                )
            )
        )
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
            .systemMedium
        ])
    }
}

private struct ATHLTHHomeWidgetView: View {
    @Environment(\.widgetFamily)
    private var family

    let entry: ATHLTHSurfaceEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
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
            if let workout =
                entry.snapshot.activeWorkout {
                Label(
                    workout.title,
                    systemImage:
                        workout.systemImage
                )
                .font(.headline)

                HStack {
                    Text(
                        duration(
                            workout.elapsedTime
                        )
                    )
                    .monospacedDigit()

                    if workout.distanceMeters > 0 {
                        Text(
                            distance(
                                workout.distanceMeters
                            )
                        )
                    }
                }
                .font(.caption)
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
            .padding()
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


    /// One premium lock-screen card for every sport. Long exercise and phase
    /// titles have room to wrap; progress is never cramped by the music UI.
    private func unifiedLightLockScreenContent(_ context: Context) -> some View {
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
                    Label(distance(context.state.distanceMeters),
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
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

            Rectangle()
                .fill(ATHLTHWidgetPalette.ink.opacity(0.09))
                .frame(height: 1)

            HStack(spacing: 10) {
                Label {
                    if isPaused {
                        Text(duration(context.state.elapsedTime))
                    } else if let started = context.attributes.startedAt {
                        Text(started, style: .timer)
                    } else {
                        Text(duration(context.state.elapsedTime))
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
                        Text(duration(ceil(max(seconds, 0))))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
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
            if ATHLTHLiveActivityDisplayPolicy.isRecent(
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
