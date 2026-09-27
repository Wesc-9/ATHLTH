import ActivityKit
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
            Label(
                "Recovery \(entry.snapshot.recoveryScore.map(String.init) ?? "—")",
                systemImage: "heart.fill"
            )
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

struct ATHLTHWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: ATHLTHWorkoutActivityAttributes.self
        ) { context in
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                HStack {
                    Label(
                        context.attributes.workoutTitle,
                        systemImage:
                            context.attributes.systemImage
                    )
                    .font(.headline)

                    Spacer()

                    Text(
                        context.state.phase.capitalized
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                }

                HStack(spacing: 18) {
                    liveDuration(context)

                    if context.state.distanceMeters > 0 {
                        metric(
                            value: String(
                                format: "%.2f",
                                context.state
                                    .distanceMeters /
                                    1000
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
            .padding()
            .activityBackgroundTint(
                Color.black.opacity(0.88)
            )
            .activitySystemActionForegroundColor(
                .white
            )
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        context.attributes.workoutTitle,
                        systemImage:
                            context.attributes.systemImage
                    )
                    .font(.caption.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.heartRate > 0 {
                        Text(
                            "\(Int(context.state.heartRate.rounded())) bpm"
                        )
                        .font(.caption.weight(.semibold))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        liveDuration(context)

                        Spacer()

                        if context.state.distanceMeters > 0 {
                            Text(
                                String(
                                    format: "%.2f km",
                                    context.state
                                        .distanceMeters /
                                        1000
                                )
                            )
                            .monospacedDigit()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } compactLeading: {
                Image(
                    systemName:
                        context.attributes.systemImage
                )
                .foregroundStyle(.green)
            } compactTrailing: {
                if context.state.distanceMeters > 0 {
                    Text(
                        String(
                            format: "%.1f",
                            context.state
                                .distanceMeters /
                                1000
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                } else if let startedAt =
                    context.attributes.startedAt {
                    Text(
                        startedAt,
                        style: .timer
                    )
                    .font(.caption2.monospacedDigit())
                } else {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                }
            } minimal: {
                Image(
                    systemName:
                        context.attributes.systemImage
                )
                .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func liveDuration(
        _ context:
            ActivityViewContext<
                ATHLTHWorkoutActivityAttributes
            >
    ) -> some View {
        if let startedAt =
            context.attributes.startedAt,
           context.state.phase != "paused" {
            Text(startedAt, style: .timer)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        } else {
            Text(
                duration(
                    context.state.elapsedTime
                )
            )
            .font(.title3.weight(.bold))
            .monospacedDigit()
        }
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
}

@main
struct ATHLTHWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ATHLTHHomeWidget()
        ATHLTHLockScreenWidget()
        ATHLTHWorkoutLiveActivity()
    }
}
