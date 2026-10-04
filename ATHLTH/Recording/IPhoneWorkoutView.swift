import SwiftUI
import MapKit

struct IPhoneWorkoutLiveSplit: Identifiable, Equatable {
    let index: Int
    let seconds: TimeInterval

    var id: Int { index }
}

struct IPhoneWorkoutLiveRouteMetrics: Equatable {
    var splits: [IPhoneWorkoutLiveSplit] = []
    var elevationGainMeters: Double = 0
    var gpsAccuracyMeters: Double?

    static func calculate(
        workout: PhoneWorkout,
        splitMeters: Double
    ) -> IPhoneWorkoutLiveRouteMetrics {
        guard workout.points.count >= 2,
              splitMeters > 0
        else {
            return IPhoneWorkoutLiveRouteMetrics(
                gpsAccuracyMeters:
                    workout.points.last?.accuracy
            )
        }

        let points = workout.points
        let pauses = workout.pauses ?? []
        var distanceMeters: Double = 0
        var movingSeconds: TimeInterval = 0
        var previousSplitSeconds: TimeInterval = 0
        var nextSplitMeters = splitMeters
        var splits: [IPhoneWorkoutLiveSplit] = []

        var altitudeWindow: [Double] = [
            points[0].altitude
        ]
        var previousSmoothedAltitude =
            points[0].altitude
        var elevationGainMeters: Double = 0

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]

            if intersectsPause(
                from: previous.timestamp,
                to: current.timestamp,
                pauses: pauses
            ) {
                altitudeWindow = [
                    current.altitude
                ]
                previousSmoothedAltitude =
                    current.altitude
                continue
            }

            let seconds =
                current.timestamp
                    .timeIntervalSince(
                        previous.timestamp
                    )

            guard seconds > 0,
                  seconds <= 30
            else {
                altitudeWindow = [
                    current.altitude
                ]
                previousSmoothedAltitude =
                    current.altitude
                continue
            }

            let segmentMeters =
                current.location.distance(
                    from:
                        previous.location
                )

            guard segmentMeters >= 0,
                  segmentMeters / seconds <= 12
            else {
                continue
            }

            let distanceBefore =
                distanceMeters
            let secondsBefore =
                movingSeconds

            distanceMeters += segmentMeters
            movingSeconds += seconds

            if segmentMeters > 0 {
                while distanceMeters >=
                        nextSplitMeters {
                    let fraction =
                        min(
                            max(
                                (
                                    nextSplitMeters -
                                    distanceBefore
                                ) /
                                segmentMeters,
                                0
                            ),
                            1
                        )

                    let crossingSeconds =
                        secondsBefore +
                        seconds * fraction
                    let splitSeconds =
                        max(
                            crossingSeconds -
                            previousSplitSeconds,
                            0
                        )

                    splits.append(
                        IPhoneWorkoutLiveSplit(
                            index:
                                splits.count + 1,
                            seconds:
                                splitSeconds
                        )
                    )

                    previousSplitSeconds =
                        crossingSeconds
                    nextSplitMeters +=
                        splitMeters
                }
            }

            altitudeWindow.append(
                current.altitude
            )
            if altitudeWindow.count > 5 {
                altitudeWindow.removeFirst(
                    altitudeWindow.count - 5
                )
            }

            let smoothedAltitude =
                altitudeWindow.reduce(0, +) /
                Double(altitudeWindow.count)
            let altitudeDelta =
                smoothedAltitude -
                previousSmoothedAltitude

            // A small dead-band prevents ordinary GPS altitude
            // noise from becoming fake climbing. Larger jumps are
            // also ignored because they are normally bad samples.
            if altitudeDelta >= 0.75,
               altitudeDelta <= 12 {
                elevationGainMeters +=
                    altitudeDelta
            }

            previousSmoothedAltitude =
                smoothedAltitude
        }

        return IPhoneWorkoutLiveRouteMetrics(
            splits: splits,
            elevationGainMeters:
                elevationGainMeters,
            gpsAccuracyMeters:
                points.last?.accuracy
        )
    }

    private static func intersectsPause(
        from start: Date,
        to end: Date,
        pauses: [PhoneWorkoutPauseInterval]
    ) -> Bool {
        pauses.contains { pause in
            let pauseEnd =
                pause.endedAt ??
                .distantFuture

            return pause.startedAt < end &&
                pauseEnd > start
        }
    }
}

private struct IPhoneWorkoutLiveMetricsPanel: View {
    let workout: PhoneWorkout
    let isMetric: Bool

    @State private var routeMetrics =
        IPhoneWorkoutLiveRouteMetrics()

    private var splitMeters: Double {
        isMetric ? 1_000 : 1_609.344
    }

    var body: some View {
        TimelineView(
            .periodic(
                from: .now,
                by: 1
            )
        ) { context in
            let elapsed =
                workout.elapsed(
                    at: context.date
                )
            let distance =
                workout.distanceMeters /
                splitMeters
            let currentPace =
                workout
                    .currentPaceSecondsPerKilometer
                    .map {
                        isMetric
                            ? $0
                            : $0 * 1.609344
                    }
            let isTreadmill =
                workout.runEnvironment ==
                .treadmill

            VStack(spacing: 0) {
                heroMetric(
                    title:
                        ATHLTHLocalization.choose(
                            english: "TIME",
                            norwegian: "TID"
                        ),
                    value:
                        elapsedText(elapsed),
                    unit: nil
                )

                Divider()
                    .opacity(0.55)

                if isTreadmill {
                    HStack(spacing: 0) {
                        focusedMetric(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "INCLINE",
                                    norwegian: "STIGNING"
                                ),
                            value:
                                String(
                                    format: "%.1f",
                                    workout
                                        .treadmillInclinePercent ??
                                    0
                                ),
                            unit: "%"
                        )

                        if workout.distanceMeters >= 50 {
                            focusedDivider

                            focusedMetric(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "DISTANCE",
                                        norwegian: "DISTANSE"
                                    ),
                                value:
                                    String(
                                        format: "%.2f",
                                        distance
                                    ),
                                unit:
                                    isMetric
                                        ? "km"
                                        : "mi"
                            )
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        focusedMetric(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "DISTANCE",
                                    norwegian: "DISTANSE"
                                ),
                            value:
                                String(
                                    format: "%.2f",
                                    distance
                                ),
                            unit:
                                isMetric
                                    ? "km"
                                    : "mi"
                        )

                        focusedDivider

                        focusedMetric(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "PACE",
                                    norwegian: "TEMPO"
                                ),
                            value:
                                paceValue(
                                    currentPace
                                ),
                            unit:
                                isMetric
                                    ? "/km"
                                    : "/mi"
                        )
                    }
                }
            }
            .background(
                Color.white.opacity(0.97),
                in:
                    RoundedRectangle(
                        cornerRadius: 28,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
                .stroke(
                    Color.black.opacity(0.045),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color:
                    ATHLTHTheme.accentDeep
                        .opacity(0.07),
                radius: 16,
                y: 6
            )
        }
    }

    private func heroMetric(
        title: String,
        value: String,
        unit: String?
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            Text(title)
                .font(
                    .system(
                        size: 12,
                        weight: .bold
                    )
                )
                .tracking(1.5)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            HStack(
                alignment: .lastTextBaseline,
                spacing: 5
            ) {
                Text(value)
                    .font(
                        .system(
                            size: 74,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)

                if let unit {
                    Text(unit)
                        .font(
                            .title3
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 172,
            alignment: .leading
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func focusedMetric(
        title: String,
        value: String,
        unit: String?
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text(title)
                .font(
                    .system(
                        size: 10,
                        weight: .bold
                    )
                )
                .tracking(1.05)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

            HStack(
                alignment: .lastTextBaseline,
                spacing: 3
            ) {
                Text(value)
                    .font(
                        .system(
                            size: 43,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .minimumScaleFactor(0.56)
                    .lineLimit(1)

                if let unit {
                    Text(unit)
                        .font(
                            .caption
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 142,
            alignment: .leading
        )
        .padding(.horizontal, 12)
    }

    private var focusedDivider: some View {
        Rectangle()
            .fill(
                Color.black.opacity(0.055)
            )
            .frame(
                width: 0.7,
                height: 94
            )
    }

    private var secondaryMetrics: some View {
        HStack(spacing: 0) {
            compactMetric(
                icon: "bolt.fill",
                title:
                    isMetric
                        ? ATHLTHLocalization.choose(
                            english: "LAST KM",
                            norwegian: "SISTE KM"
                        )
                        : ATHLTHLocalization.choose(
                            english: "LAST MI",
                            norwegian: "SISTE MI"
                        ),
                value:
                    routeMetrics.splits.last
                        .map {
                            paceValue(
                                $0.seconds
                            )
                        } ??
                    "—"
            )

            compactDivider

            compactMetric(
                icon:
                    "mountain.2.fill",
                title:
                    ATHLTHLocalization.choose(
                        english: "ELEVATION",
                        norwegian: "HØYDE"
                    ),
                value:
                    elevationText
            )

            compactDivider

            compactMetric(
                icon:
                    "location.fill",
                title: "GPS",
                value:
                    gpsAccuracyText
            )
        }
        .padding(.vertical, 9)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private func compactMetric(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    width: 30,
                    height: 30
                )
                .background(
                    ATHLTHTheme.accentSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 8,
                            weight: .semibold
                        )
                    )
                    .tracking(0.7)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)

                Text(value)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.horizontal, 9)
    }

    private var compactDivider: some View {
        Rectangle()
            .fill(
                Color.black.opacity(0.05)
            )
            .frame(
                width: 0.7,
                height: 38
            )
    }

    private var splitsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english: "SPLITS",
                        norwegian: "SPLITS"
                    )
                )
                .font(
                    .system(
                        size: 10,
                        weight: .semibold
                    )
                )
                .tracking(1.2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Spacer()

                Text(
                    isMetric
                        ? "/ km"
                        : "/ mi"
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            HStack(spacing: 7) {
                ForEach(
                    Array(
                        routeMetrics.splits
                            .suffix(4)
                    )
                ) { split in
                    VStack(spacing: 5) {
                        HStack(
                            alignment:
                                .firstTextBaseline
                        ) {
                            Text(
                                "\(split.index)"
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                            Spacer(
                                minLength: 2
                            )

                            Text(
                                paceValue(
                                    split.seconds
                                )
                            )
                            .fontWeight(
                                .semibold
                            )
                            .monospacedDigit()
                        }
                        .font(.caption)

                        Capsule()
                            .fill(
                                ATHLTHTheme
                                    .accent
                                    .opacity(0.18)
                            )
                            .frame(height: 5)
                            .overlay(
                                alignment: .leading
                            ) {
                                Capsule()
                                    .fill(
                                        ATHLTHTheme
                                            .accentDeep
                                            .opacity(
                                                0.74
                                            )
                                    )
                                    .frame(
                                        width:
                                            splitBarWidth(
                                                seconds:
                                                    split.seconds
                                            ),
                                        height: 5
                                    )
                            }
                    }
                    .padding(8)
                    .frame(
                        maxWidth: .infinity
                    )
                    .background(
                        ATHLTHTheme
                            .accentSoft
                            .opacity(0.55),
                        in:
                            RoundedRectangle(
                                cornerRadius: 12,
                                style:
                                    .continuous
                            )
                    )
                }
            }
        }
        .padding(12)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 19,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    private func splitBarWidth(
        seconds: TimeInterval
    ) -> CGFloat {
        guard seconds > 0 else {
            return 18
        }

        let values =
            routeMetrics.splits
                .suffix(4)
                .map(\.seconds)
        guard let fastest = values.min(),
              let slowest = values.max(),
              slowest > fastest
        else {
            return 54
        }

        let normalized =
            (slowest - seconds) /
            (slowest - fastest)

        return 32 +
            CGFloat(normalized) * 34
    }

    private var elevationText: String {
        if isMetric {
            return "+\(Int(routeMetrics.elevationGainMeters.rounded())) m"
        }

        let feet =
            routeMetrics
                .elevationGainMeters *
            3.28084
        return "+\(Int(feet.rounded())) ft"
    }

    private var gpsAccuracyText: String {
        guard let accuracy =
                routeMetrics.gpsAccuracyMeters,
              accuracy >= 0
        else {
            return "—"
        }

        if isMetric {
            return "±\(Int(accuracy.rounded())) m"
        }

        return "±\(Int((accuracy * 3.28084).rounded())) ft"
    }

    private func paceValue(
        _ seconds: TimeInterval?
    ) -> String {
        guard let seconds,
              seconds.isFinite,
              seconds > 0
        else {
            return "—"
        }

        let rounded =
            Int(seconds.rounded())
        return String(
            format:
                "%d:%02d",
            rounded / 60,
            rounded % 60
        )
    }

    private func elapsedText(
        _ seconds: TimeInterval
    ) -> String {
        let total =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = total / 3600
        let minutes =
            (total % 3600) / 60
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
            format:
                "%02d:%02d",
            minutes,
            remainder
        )
    }
}

struct IPhoneWorkoutView: View {
    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmFinish = false
    @State private var followMe = true
    @State private var showingTreadmillInclineEditor = false
    @State private var treadmillInclineDraft = 0.0
    @State private var routeCamera:
        MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            List {
                if let workout = recorder.active {
                    VStack(
                        alignment: .leading,
                        spacing: 13
                    ) {
                        premiumWorkoutHeader(
                            workout
                        )

                        TrainTogetherStatusStrip()

                        IPhoneWorkoutLiveMetricsPanel(
                            workout: workout,
                            isMetric:
                                settings
                                    .measurementPreference ==
                                .metric
                        )

                        if let message =
                            recorder.message,
                           !message.isEmpty {
                            compactStatusMessage(
                                message
                            )
                        }
                    }
                    .listRowInsets(
                        EdgeInsets(
                            top: 10,
                            leading: 14,
                            bottom: 6,
                            trailing: 14
                        )
                    )
                    .listRowBackground(
                        Color.clear
                    )
                    .listRowSeparator(
                        .hidden
                    )

                    if let ghostTitle =
                            workout.ghostRaceTitle,
                       let distanceDelta =
                            workout
                                .ghostDistanceDeltaMeters {
                        Section("Ghost") {
                            HStack(
                                alignment:
                                    .firstTextBaseline
                            ) {
                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(ghostTitle)
                                        .font(.headline)

                                    Text(
                                        "Live comparison"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )

                                    if realtime
                                        .selectedLiveGhostSessionID != nil {
                                        liveGhostConnectionLabel
                                    }
                                }

                                Spacer()

                                Text(
                                    liveGhostText(
                                        distanceDelta
                                    )
                                )
                                .font(
                                    .title3
                                        .weight(.bold)
                                )
                                .monospacedDigit()
                                .foregroundStyle(
                                    abs(distanceDelta) <
                                        8
                                        ? .secondary
                                        : distanceDelta >= 0
                                            ? ATHLTHTheme
                                                .vitality
                                            : .orange
                                )
                            }

                            if let timeDelta =
                                    workout
                                        .ghostTimeDeltaSeconds {
                                LabeledContent(
                                    "Estimated gap",
                                    value:
                                        ghostTimeText(
                                            timeDelta
                                        )
                                )
                            }

                            if workout
                                .ghostAudioConfiguration?
                                .enabled == true {
                                Label(
                                    "Ghost Updates active",
                                    systemImage:
                                        "waveform"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                    }

                    if workout.plannedRouteTitle != nil {
                        Section("Route Guardian") {
                            HStack {
                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(
                                        workout
                                            .plannedRouteTitle ??
                                        "Route"
                                    )
                                    .font(
                                        .headline
                                    )

                                    if let remaining =
                                        workout
                                            .routeRemainingMeters {
                                        Text(
                                            routeDistanceText(
                                                remaining
                                            ) +
                                            " remaining"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }

                                Spacer()

                                if let progress =
                                    workout
                                        .routeProgressPercent {
                                    Text(
                                        "\(Int(progress.rounded()))%"
                                    )
                                    .font(
                                        .title3
                                            .weight(.bold)
                                    )
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        ATHLTHTheme.vitality
                                    )
                                }
                            }

                            if let progress =
                                workout
                                    .routeProgressPercent {
                                ProgressView(
                                    value:
                                        min(
                                            max(
                                                progress,
                                                0
                                            ),
                                            100
                                        ),
                                    total: 100
                                )
                                .tint(
                                    ATHLTHTheme.vitality
                                )
                            }

                            if let deviation =
                                workout
                                    .routeDeviationMeters {
                                let threshold =
                                    workout
                                        .routeAlertConfiguration?
                                        .deviationMeters ??
                                    80
                                Label(
                                    deviation > threshold
                                        ? "\(Int(deviation.rounded())) m off route"
                                        : "On route",
                                    systemImage:
                                        deviation > threshold
                                            ? "exclamationmark.triangle.fill"
                                            : "location.fill"
                                )
                                .foregroundStyle(
                                    deviation > threshold
                                        ? .orange
                                        : ATHLTHTheme
                                            .vitality
                                )
                            }

                            if let bearing =
                                workout
                                    .routeNextBearingDegrees {
                                HStack {
                                    Image(
                                        systemName:
                                            "location.north.fill"
                                    )
                                    .rotationEffect(
                                        .degrees(
                                            bearing
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.vitality
                                    )

                                    Text(
                                        "Next route segment"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }

                            if let toStart =
                                workout
                                    .routeDistanceToStartMeters,
                               toStart > 250,
                               (
                                    workout
                                        .routeProgressPercent ??
                                    0
                               ) < 3 {
                                Button {
                                    openDirectionsToStart(
                                        workout
                                    )
                                } label: {
                                    Label(
                                        routeDistanceText(
                                            toStart
                                        ) +
                                        " to start · Directions",
                                        systemImage:
                                            "arrow.triangle.turn.up.right.diamond.fill"
                                    )
                                }
                            }
                        }
                    }

                    if let step =
                        recorder.currentStructuredStep {
                        Section("Workout step") {
                            TimelineView(
                                .periodic(
                                    from: .now,
                                    by: 1
                                )
                            ) { context in
                                let progress =
                                    recorder
                                        .currentStructuredStepProgress(
                                            at:
                                                context.date
                                        )

                                VStack(
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    HStack {
                                        Text(step.title)
                                            .font(
                                                .headline
                                            )

                                        Spacer()

                                        if let active =
                                            recorder.active,
                                           let plan =
                                            active
                                                .structuredRunningWorkout {
                                            Text(
                                                "Step \((active.structuredStepIndex ?? 0) + 1) / \(plan.steps.count)"
                                            )
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
                                    }

                                    ProgressView(
                                        value: progress
                                    )
                                    .tint(
                                        ATHLTHTheme.accent
                                    )

                                    Text(
                                        structuredRemainingText(
                                            step: step,
                                            workout:
                                                workout,
                                            date:
                                                context.date
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )

                                    if let next =
                                        recorder
                                            .nextStructuredStep {
                                        Label(
                                            "Next: \(next.title)",
                                            systemImage:
                                                "arrow.right.circle.fill"
                                        )
                                        .font(
                                            .caption
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if let liveSession = realtime.currentSession,
                       realtime.isSharingLiveLocation {
                        Section("Live") {
                            NavigationLink {
                                ATHLTHLiveWorkoutMapView(
                                    session: liveSession
                                )
                            } label: {
                                Label(
                                    liveSession.ghostChallengeID == nil
                                        ? "View live workout"
                                        : "View live Ghost Run",
                                    systemImage:
                                        "location.circle.fill"
                                )
                            }

                            Text(
                                liveSession.ghostChallengeID == nil
                                    ? "Your latest position is shared only with the audience selected in Social Privacy."
                                    : "This Ghost Run live position is private to the race participants."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if (
                        workout
                            .plannedRouteCoordinates?
                            .count ?? 0
                    ) >= 2 {
                        premiumWorkoutMap(
                            workout
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: 14,
                                bottom: 8,
                                trailing: 14
                            )
                        )
                        .listRowBackground(
                            Color.clear
                        )
                        .listRowSeparator(
                            .hidden
                        )
                    }
                }
                if recorder.active == nil {
                    premiumHistoryHeader
                        .listRowInsets(
                            EdgeInsets(
                                top: 10,
                                leading: 14,
                                bottom: 4,
                                trailing: 14
                            )
                        )
                        .listRowBackground(
                            Color.clear
                        )
                        .listRowSeparator(
                            .hidden
                        )

                    if let completion =
                        recorder.lastRouteCompletion {
                        Section("Route complete") {
                            HStack {
                                completionMetric(
                                    title: "MATCH",
                                    value:
                                        "\(Int(completion.routeMatchPercent.rounded()))%"
                                )
                                completionMetric(
                                    title: "AVG DEV.",
                                    value:
                                        "\(Int(completion.averageDeviationMeters.rounded())) m"
                                )
                                completionMetric(
                                    title: "MAX DEV.",
                                    value:
                                        "\(Int(completion.maxDeviationMeters.rounded())) m"
                                )
                            }

                            if completion.personalBest {
                                Label(
                                    "New personal best",
                                    systemImage:
                                        "trophy.fill"
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .premiumGold
                                )
                            }

                            if let rank =
                                    completion
                                        .leaderboardRank,
                               let fieldSize =
                                    completion
                                        .leaderboardFieldSize {
                                Label(
                                    "Leaderboard #\(rank) of \(fieldSize)",
                                    systemImage:
                                        "list.number"
                                )
                                .font(
                                    .caption
                                        .weight(.semibold)
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.vitality
                                )
                            } else {
                                Label(
                                    completion.leaderboardEligible
                                        ? "Eligible for route leaderboard"
                                        : "Route match was below leaderboard requirements",
                                    systemImage:
                                        completion.leaderboardEligible
                                            ? "checkmark.seal.fill"
                                            : "info.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    completion.leaderboardEligible
                                        ? ATHLTHTheme.vitality
                                        : .secondary
                                )
                            }
                        }
                    }

                    if let message = recorder.message {
                        Section {
                            Text(message)
                                .font(.footnote)
                        }
                    }

                    Section("Saved iPhone workouts") {
                        ForEach(
                            recorder.history.prefix(20)
                        ) { workout in
                            VStack(
                                alignment: .leading,
                                spacing: 6
                            ) {
                                Text(workout.title)
                                    .font(.headline)
                                Text(
                                    workout.start.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )
                                Text(
                                    String(
                                        format:
                                            "%.2f km · %.0f min",
                                        workout.distanceMeters / 1000,
                                        workout.accumulatedSeconds / 60
                                    )
                                )

                                if workout.healthID == nil {
                                    Button(
                                        "Copy to Apple Health"
                                    ) {
                                        Task {
                                            await health
                                                .requestAuthorization()
                                            await recorder
                                                .retryHealthSave(
                                                    workout
                                                )
                                        }
                                    }
                                    .disabled(
                                        recorder.saving
                                    )
                                } else {
                                    Label(
                                        "Saved to Apple Health",
                                        systemImage:
                                            "checkmark.circle"
                                    )
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .accentDeep
                            .opacity(0.12)
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if let workout =
                    recorder.active {
                    premiumWorkoutControls(
                        workout
                    )
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
                    recorder
                        .setTreadmillInclinePercent(
                            value
                        )
                    treadmillInclineDraft =
                        value
                }
            }
            .confirmationDialog(
                "Finish this workout?",
                isPresented: $confirmFinish,
                titleVisibility: .visible
            ) {
                Button("Finish & save") {
                    Task {
                        await recorder.finish()
                        await realtime
                            .leaveCurrentLiveWorkout()
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(
                        for: .seconds(5)
                    )

                    guard !Task.isCancelled else {
                        break
                    }

                    recorder.checkpoint()
                    await publishLivePointIfNeeded()
                }
            }
        }
        .onAppear {
            recorder.liveViewDidAppear()
            updateScreenAwakeState()
        }
        .onDisappear {
            recorder.liveViewDidDisappear()
            ATHLTHWorkoutScreenAwake.set(
                false,
                reason: "iphone-live-workout"
            )
        }
        .onChange(
            of: recorder.active?.id
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
            recorder.active != nil &&
                scenePhase == .active,
            reason: "iphone-live-workout"
        )
    }

    private var premiumHistoryHeader:
        some View {
        HStack {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "iPhone workouts",
                        norwegian:
                            "iPhone-økter"
                    )
                )
                .font(
                    .system(
                        size: 31,
                        weight: .bold,
                        design: .rounded
                    )
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Workouts recorded on this iPhone",
                        norwegian:
                            "Økter registrert på denne iPhonen"
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .background(
                        Color.white
                            .opacity(0.90),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func premiumWorkoutHeader(
        _ workout: PhoneWorkout
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Button {
                    recorder.minimizeWorkout()
                    dismiss()
                } label: {
                    Image(
                        systemName:
                            "chevron.down"
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                    .frame(
                        width: 43,
                        height: 43
                    )
                    .background(
                        Color.white
                            .opacity(0.90),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.black
                                    .opacity(
                                        0.045
                                    ),
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    guard workout.runEnvironment ==
                            .treadmill
                    else {
                        return
                    }

                    treadmillInclineDraft =
                        workout
                            .treadmillInclinePercent ??
                        0
                    showingTreadmillInclineEditor =
                        true
                } label: {
                    HStack(spacing: 6) {
                        Image(
                            systemName:
                                workout.runEnvironment ==
                                .treadmill
                                    ? "figure.run.treadmill"
                                    : "location.fill"
                        )

                        Text(
                            workout.runEnvironment ==
                                .treadmill
                                ? ATHLTHLocalization.format(
                                    english:
                                        "Treadmill · %.1f%%",
                                    norwegian:
                                        "Tredemølle · %.1f%%",
                                    workout
                                        .treadmillInclinePercent ??
                                    0
                                )
                                : (
                                    workout.points.last == nil
                                        ? ATHLTHLocalization.choose(
                                            english: "GPS waiting",
                                            norwegian: "Venter på GPS"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "GPS on",
                                            norwegian: "GPS på"
                                        )
                                )
                        )
                        .font(
                            .caption.weight(
                                .semibold
                            )
                        )

                        if workout.runEnvironment ==
                            .treadmill {
                            Image(
                                systemName:
                                    "chevron.down"
                            )
                            .font(.caption2)
                        }
                    }
                    .foregroundStyle(
                        workout.runEnvironment == .treadmill
                            ? ATHLTHTheme.accentDeep
                            : workout.points.last == nil
                                ? Color.orange
                                : ATHLTHTheme.vitality
                    )
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(
                        Color.white.opacity(0.88),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.black.opacity(0.04),
                                lineWidth: 0.7
                            )
                    }
                }
                .buttonStyle(.plain)
                ATHLTHAudioRouteControl()
            }

            Text(workout.title)
                .font(
                    .system(
                        size: 35,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 7) {
                Image(
                    systemName:
                        "location.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )

                Text(
                    workout.runEnvironment == .treadmill
                        ? ATHLTHLocalization.choose(
                            english:
                                "Indoor run · recorded with iPhone",
                            norwegian:
                                "Innendørs · registreres med iPhone"
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Outdoor run · recorded with iPhone",
                            norwegian:
                                "Utendørs · registreres med iPhone"
                        )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }
        }
    }

    private func compactStatusMessage(
        _ message: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(
                systemName:
                    message
                        .localizedCaseInsensitiveContains(
                            "GPS"
                        )
                        ? "location.circle"
                        : "info.circle"
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )

            Text(message)
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(
            .horizontal,
            12
        )
        .frame(minHeight: 42)
        .background(
            Color.white.opacity(0.82),
            in:
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
        )
    }

    private func premiumWorkoutMap(
        _ workout: PhoneWorkout
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Text(
                    workout.plannedRouteTitle ==
                        nil
                        ? ATHLTHLocalization
                            .choose(
                                english: "Route",
                                norwegian: "Rute"
                            )
                        : workout
                            .plannedRouteTitle ??
                            "Route"
                )
                .font(
                    .headline.weight(
                        .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )
                .lineLimit(1)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(
                            ATHLTHTheme
                                .vitality
                        )
                        .frame(
                            width: 7,
                            height: 7
                        )

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Live",
                            norwegian: "Live"
                        )
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                }
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
                .padding(
                    .horizontal,
                    10
                )
                .frame(height: 29)
                .background(
                    ATHLTHTheme
                        .vitality
                        .opacity(0.09),
                    in: Capsule()
                )
            }

            Map(
                position: $routeCamera
            ) {
                if let route =
                    workout
                        .plannedRouteCoordinates,
                   route.count >= 2 {
                    MapPolyline(
                        coordinates:
                            displayRouteCoordinates(
                                route
                            )
                    )
                    .stroke(
                        ATHLTHTheme
                            .vitality
                            .opacity(0.75),
                        style:
                            StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round,
                                lineJoin: .round
                            )
                    )
                }

                if workout.points.count >= 2 {
                    MapPolyline(
                        coordinates:
                            displayWorkoutCoordinates(
                                workout.points
                            )
                    )
                    .stroke(
                        ATHLTHTheme
                            .accentDeep,
                        style:
                            StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                    )
                }

                if let last =
                    workout.points.last {
                    Annotation(
                        "",
                        coordinate:
                            last.location
                                .coordinate
                    ) {
                        ZStack {
                            Circle()
                                .fill(
                                    ATHLTHTheme
                                        .accentDeep
                                        .opacity(
                                            0.16
                                        )
                                )
                                .frame(
                                    width: 34,
                                    height: 34
                                )

                            Circle()
                                .fill(
                                    ATHLTHTheme
                                        .accentDeep
                                )
                                .frame(
                                    width: 13,
                                    height: 13
                                )
                                .overlay {
                                    Circle()
                                        .stroke(
                                            .white,
                                            lineWidth:
                                                3
                                        )
                                }
                        }
                    }
                }
            }
            .frame(height: 265)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    Color.black.opacity(
                        0.05
                    ),
                    lineWidth: 0.8
                )
            }
            .mapControls {
                MapCompass()
            }
            .onAppear {
                routeCamera =
                    .region(
                        workoutMapRegion(
                            for: workout
                        )
                    )
            }
            .onChange(
                of:
                    recorder
                        .active?
                        .points
                        .count
            ) { _, _ in
                guard followMe,
                      let last =
                        recorder
                            .active?
                            .points
                            .last
                else {
                    return
                }

                routeCamera =
                    .region(
                        followRegion(
                            around:
                                last
                                    .location
                                    .coordinate
                        )
                    )
            }

            HStack(spacing: 9) {
                Button {
                    followMe.toggle()

                    if followMe,
                       let last =
                        recorder
                            .active?
                            .points
                            .last {
                        routeCamera =
                            .region(
                                followRegion(
                                    around:
                                        last
                                            .location
                                            .coordinate
                                )
                            )
                    }
                } label: {
                    Label(
                        followMe
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Following",
                                    norwegian:
                                        "Følger"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "Follow",
                                    norwegian:
                                        "Følg"
                                ),
                        systemImage:
                            followMe
                                ? "location.fill"
                                : "location"
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        followMe
                            ? Color.white
                            : ATHLTHTheme
                                .accentDeep
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 46)
                    .background(
                        followMe
                            ? ATHLTHTheme
                                .accentDeep
                            : Color.white,
                        in:
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                    )
                }
                .buttonStyle(.plain)

                Button {
                    routeCamera =
                        .region(
                            workoutMapRegion(
                                for: workout
                            )
                        )
                    followMe = false
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Show route",
                            norwegian:
                                "Vis rute"
                        ),
                        systemImage: "map"
                    )
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 46)
                    .background(
                        Color.white,
                        in:
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                        .stroke(
                            Color.black
                                .opacity(
                                    0.045
                                ),
                            lineWidth: 0.7
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            Color.white.opacity(0.88),
            in:
                RoundedRectangle(
                    cornerRadius: 23,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 23,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.045),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                ATHLTHTheme.accentDeep
                    .opacity(0.06),
            radius: 14,
            y: 5
        )
    }

    private func premiumWorkoutControls(
        _ workout: PhoneWorkout
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                if workout.resumedAt == nil {
                    recorder.resume()
                } else {
                    recorder.pause()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(
                        systemName:
                            workout.resumedAt ==
                                nil
                                ? "play.fill"
                                : "pause.fill"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .bold
                        )
                    )
                    .frame(
                        width: 32,
                        height: 32
                    )
                    .background(
                        ATHLTHTheme
                            .accentDeep,
                        in: Circle()
                    )
                    .foregroundStyle(
                        .white
                    )

                    Text(
                        workout.resumedAt == nil
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Resume",
                                    norwegian:
                                        "Fortsett"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "Pause",
                                    norwegian:
                                        "Pause"
                                )
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                }
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 56)
                .background(
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.92),
                    in:
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                confirmFinish = true
            } label: {
                HStack(spacing: 9) {
                    Image(
                        systemName:
                            "stop.fill"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .bold
                        )
                    )
                    .frame(
                        width: 32,
                        height: 32
                    )
                    .background(
                        Color.black.opacity(
                            0.14
                        ),
                        in: Circle()
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Finish & save",
                            norwegian:
                                "Avslutt og lagre"
                        )
                    )
                    .font(
                        .headline.weight(
                            .semibold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                }
                .foregroundStyle(.white)
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [
                            Color.red
                                .opacity(0.88),
                            Color.red
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    in:
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(recorder.saving)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    private func displayRouteCoordinates(
        _ coordinates: [RouteCoordinate]
    ) -> [CLLocationCoordinate2D] {
        let sorted =
            coordinates.sorted {
                $0.sequence < $1.sequence
            }

        guard sorted.count > 800 else {
            return sorted.map(\.coordinate)
        }

        let step =
            max(
                sorted.count / 800,
                1
            )
        var sampled =
            stride(
                from: 0,
                to: sorted.count,
                by: step
            )
            .map {
                sorted[$0].coordinate
            }

        if let last = sorted.last?.coordinate,
           sampled.last?.latitude !=
                last.latitude ||
            sampled.last?.longitude !=
                last.longitude {
            sampled.append(last)
        }

        return sampled
    }

    private func displayWorkoutCoordinates(
        _ points: [PhoneRoutePoint]
    ) -> [CLLocationCoordinate2D] {
        guard points.count > 600 else {
            return points.map {
                $0.location.coordinate
            }
        }

        let step =
            max(
                points.count / 600,
                1
            )
        var sampled =
            stride(
                from: 0,
                to: points.count,
                by: step
            )
            .map {
                points[$0]
                    .location.coordinate
            }

        if let last =
            points.last?.location.coordinate,
           sampled.last?.latitude !=
                last.latitude ||
            sampled.last?.longitude !=
                last.longitude {
            sampled.append(last)
        }

        return sampled
    }

    private func routeDistanceText(
        _ meters: Double
    ) -> String {
        if meters >= 1_000 {
            return String(
                format: "%.1f km",
                meters / 1_000
            )
        }

        return "\(Int(meters.rounded())) m"
    }

    private func structuredRemainingText(
        step: WatchRunningWorkoutStep,
        workout: PhoneWorkout,
        date: Date
    ) -> String {
        switch step.measure {
        case .time:
            guard let target =
                step.durationSeconds
            else {
                return "Open step"
            }

            let used =
                max(
                    workout.elapsed(at: date) -
                        (
                            workout
                                .structuredStepStartElapsedTime ??
                            0
                        ),
                    0
                )
            let remaining =
                max(target - used, 0)

            return
                "\(Int(remaining.rounded())) sec remaining"

        case .distance:
            guard let target =
                step.distanceMeters
            else {
                return "Open step"
            }

            let used =
                max(
                    workout.distanceMeters -
                        (
                            workout
                                .structuredStepStartDistanceMeters ??
                            0
                        ),
                    0
                )

            return routeDistanceText(
                max(target - used, 0)
            ) + " remaining"

        case .open:
            return "Open step · advance by finishing the workout"
        }
    }

    private func followRegion(
        around coordinate:
            CLLocationCoordinate2D
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span:
                MKCoordinateSpan(
                    latitudeDelta: 0.008,
                    longitudeDelta: 0.008
                )
        )
    }

    private func openDirectionsToStart(
        _ workout: PhoneWorkout
    ) {
        guard let first =
                workout
                    .plannedRouteCoordinates?
                    .min(
                        by: {
                            $0.sequence <
                                $1.sequence
                        }
                    )
        else {
            return
        }

        let item =
            MKMapItem(
                placemark:
                    MKPlacemark(
                        coordinate:
                            CLLocationCoordinate2D(
                                latitude:
                                    first.latitude,
                                longitude:
                                    first.longitude
                            )
                    )
            )

        item.name =
            (workout.plannedRouteTitle ??
                "Route") +
            " · Start"

        item.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey:
                    MKLaunchOptionsDirectionsModeWalking
            ]
        )
    }

    @ViewBuilder
    private func completionMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .monospacedDigit()

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func workoutMapRegion(
        for workout: PhoneWorkout
    ) -> MKCoordinateRegion {
        let routeCoordinates =
            workout.plannedRouteCoordinates?
                .map(\.coordinate) ?? []
        let recordedCoordinates =
            workout.points.map {
                $0.location.coordinate
            }
        let coordinates =
            routeCoordinates.isEmpty
                ? recordedCoordinates
                : routeCoordinates + recordedCoordinates

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center:
                    CLLocationCoordinate2D(
                        latitude: 0,
                        longitude: 0
                    ),
                span:
                    MKCoordinateSpan(
                        latitudeDelta: 0.01,
                        longitudeDelta: 0.01
                    )
            )
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude =
                min(minLatitude, coordinate.latitude)
            maxLatitude =
                max(maxLatitude, coordinate.latitude)
            minLongitude =
                min(minLongitude, coordinate.longitude)
            maxLongitude =
                max(maxLongitude, coordinate.longitude)
        }

        let latitudeDelta =
            max(
                (maxLatitude - minLatitude) * 1.28,
                0.008
            )
        let longitudeDelta =
            max(
                (maxLongitude - minLongitude) * 1.28,
                0.008
            )

        return MKCoordinateRegion(
            center:
                CLLocationCoordinate2D(
                    latitude:
                        (minLatitude + maxLatitude) / 2,
                    longitude:
                        (minLongitude + maxLongitude) / 2
                ),
            span:
                MKCoordinateSpan(
                    latitudeDelta: latitudeDelta,
                    longitudeDelta: longitudeDelta
                )
        )
    }

    private func ghostTimeText(
        _ seconds: TimeInterval
    ) -> String {
        let amount =
            max(
                Int(
                    abs(seconds)
                        .rounded()
                ),
                0
            )
        let minutes = amount / 60
        let remainder = amount % 60
        let value =
            String(
                format:
                    "%d:%02d",
                minutes,
                remainder
            )

        if abs(seconds) < 1 {
            return "Even"
        }

        return seconds >= 0
            ? "\(value) ahead"
            : "\(value) behind"
    }

    @ViewBuilder
    private var liveGhostConnectionLabel:
        some View {
        switch realtime
            .liveGhostConnectionState {
        case .live:
            Label(
                ATHLTHLocalization.choose(
                    english: "Live GPS",
                    norwegian: "Live GPS"
                ),
                systemImage:
                    "dot.radiowaves.left.and.right"
            )
            .foregroundStyle(
                ATHLTHTheme.vitality
            )

        case .delayed(let seconds):
            Label(
                ATHLTHLocalization.format(
                    english:
                        "Delayed · %d s",
                    norwegian:
                        "Forsinket · %d s",
                    seconds
                ),
                systemImage:
                    "clock.badge.exclamationmark"
            )
            .foregroundStyle(.orange)

        case .reconnecting(let seconds):
            Label(
                ATHLTHLocalization.format(
                    english:
                        "Reconnecting · %d s",
                    norwegian:
                        "Kobler til på nytt · %d s",
                    seconds
                ),
                systemImage:
                    "arrow.triangle.2.circlepath"
            )
            .foregroundStyle(.orange)

        case .waiting:
            Label(
                ATHLTHLocalization.choose(
                    english: "Waiting for GPS",
                    norwegian: "Venter på GPS"
                ),
                systemImage:
                    "location.slash"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func liveGhostText(
        _ meters: Double
    ) -> String {
        let amount =
            Int(
                abs(meters)
                    .rounded()
            )

        if abs(meters) < 5 {
            return "Side by side"
        }

        return meters >= 0
            ? "You +\(amount) m"
            : "Ghost +\(amount) m"
    }

    @MainActor
    private func publishLivePointIfNeeded() async {
        guard let workout = recorder.active,
              workout.resumedAt != nil,
              let lastPoint =
                workout.points.last?
                    .location
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

            let visibility =
                ATHLTHLiveWorkoutVisibility(
                    rawValue:
                        social.privacy?
                            .liveLocationVisibility ??
                        "followers"
                ) ?? .followers

            _ = await realtime
                .beginLiveWorkout(
                    title: workout.title,
                    activity:
                        workout.walking
                            ? "walking"
                            : "running",
                    visibility: visibility,
                    routeKey:
                        workout
                            .plannedComparisonRouteID,
                    routeDistanceMeters:
                        workout
                            .plannedRouteDistanceKilometers
                            .map {
                                max(
                                    $0 * 1_000,
                                    0
                                )
                            },
                    routeTitle:
                        workout
                            .plannedRouteTitle
                )
        }

        await realtime.publishLocation(
            lastPoint,
            distanceMeters:
                workout.distanceMeters,
            elapsedSeconds:
                workout.elapsed(at: Date()),
            routeProgressPercent:
                workout.routeProgressPercent,
            routeDeviationMeters:
                workout.routeDeviationMeters,
            routeKey:
                workout
                    .plannedComparisonRouteID,
            routeDistanceMeters:
                workout
                    .plannedRouteDistanceKilometers
                    .map {
                        max(
                            $0 * 1_000,
                            0
                        )
                    },
            routeTitle:
                workout
                    .plannedRouteTitle
        )
    }
}


private struct TreadmillInclineEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Double) -> Void
    @State private var value: Double

    init(
        initialValue: Double,
        onSave: @escaping (Double) -> Void
    ) {
        self.onSave = onSave
        _value = State(
            initialValue:
                min(
                    max(initialValue, 0),
                    20
                )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    ATHLTHLocalization.choose(
                        english: "Treadmill",
                        norwegian: "Tredemølle"
                    )
                ) {
                    Stepper(
                        value: $value,
                        in: 0...20,
                        step: 0.5
                    ) {
                        HStack {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Incline",
                                    norwegian: "Stigning"
                                )
                            )

                            Spacer()

                            Text(
                                String(
                                    format:
                                        "%.1f%%",
                                    value
                                )
                            )
                            .monospacedDigit()
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

                    Slider(
                        value: $value,
                        in: 0...20,
                        step: 0.5
                    )
                }

                Section {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "You can change incline while the workout is running. The current value is stored with the workout.",
                            norwegian:
                                "Du kan endre stigning mens økten pågår. Gjeldende verdi lagres med økten."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Incline",
                    norwegian: "Stigning"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Save",
                            norwegian: "Lagre"
                        )
                    ) {
                        onSave(value)
                        dismiss()
                    }
                }
            }
        }
    }
}
