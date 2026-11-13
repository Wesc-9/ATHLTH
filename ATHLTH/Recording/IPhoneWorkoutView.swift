import SwiftUI
import MapKit
import AVFoundation

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
            let isIndoor = ATHLTHPhoneRunEnvironmentPolicy.isIndoor(workout.runEnvironment)
            let isTreadmill = workout.runEnvironment == .treadmill &&
                workout.indoorVenue != .indoorRunning
            // Neither type of indoor running may reuse GPS pace. Indoor
            // tracks have no belt-speed source; never imply measured pace.
            let paceSeconds = isIndoor
                ? (isTreadmill
                    ? workout.treadmillSpeedKilometersPerHour.flatMap {
                        $0 > 0 ? 3_600 / $0 : nil
                    } : nil)
                : workout.currentPaceSecondsPerKilometer
            let currentPace = paceSeconds.map { isMetric ? $0 : $0 * 1.609344 }
            let treadmillAveragePace = isTreadmill
                ? ATHLTHRunningPace.average(
                    elapsedSeconds: elapsed,
                    distanceMeters: workout.distanceMeters
                ).map { isMetric ? $0 : $0 * 1.609344 }
                : nil
            let measuredAveragePace = ATHLTHRunningPace.average(
                elapsedSeconds: elapsed, distanceMeters: workout.distanceMeters
            ).map { isMetric ? $0 : $0 * 1.609344 }
            // Manual belt speed is clearly a user-entered target, not GPS.
            let displayedPace = currentPace

            if workout.walking {
                walkingMetricsPanel(
                    distance: distance,
                    elapsed: elapsed,
                    averagePace: measuredAveragePace,
                    at: context.date
                )
            } else {
            VStack(spacing: 0) {
                let hierarchy = ATHLTHPhoneLiveHierarchyResolver.resolve(
                    kind: .running
                )

                heroMetric(
                    title: hierarchy.primary == .pace
                        ? ATHLTHLocalization.choose(
                            english: isTreadmill ? "BELT PACE" : "CURRENT PACE",
                            norwegian: isTreadmill ? "MØLLETEMPO" : "TEMPO NÅ"
                          )
                        : ATHLTHLocalization.choose(
                            english: "DISTANCE", norwegian: "DISTANSE"
                          ),
                    value: hierarchy.primary == .pace
                        ? paceValue(displayedPace)
                        : String(format: "%.2f", distance),
                    unit: hierarchy.primary == .pace
                        ? (isMetric ? "/km" : "/mi")
                        : (isMetric ? "km" : "mi")
                )

                Divider()
                    .opacity(0.42)
                    .padding(.horizontal, 15)

                HStack(spacing: 0) {
                    focusedMetric(
                        title: ATHLTHLocalization.choose(
                            english: "DISTANCE", norwegian: "DISTANSE"
                        ),
                        value: String(format: "%.2f", distance),
                        unit: isMetric ? "km" : "mi"
                    )

                    focusedDivider

                    focusedMetric(
                        title: ATHLTHLocalization.choose(
                            english: "ELAPSED TIME", norwegian: "ØKTTID"
                        ),
                        value: elapsedText(elapsed),
                        unit: nil
                    )
                }

                Divider()
                    .opacity(0.42)
                    .padding(.horizontal, 15)
                HStack(spacing: 0) {
                    focusedMetric(
                        title: ATHLTHLocalization.choose(
                            english: "WORKOUT AVERAGE PACE",
                            norwegian: "SNITTEMPO ØKTEN"),
                        value: paceValue(measuredAveragePace),
                        unit: isMetric ? "/km" : "/mi"
                    )
                    focusedDivider
                    focusedMetric(
                        title: ATHLTHLocalization.choose(
                            english: "PACE SOURCE",
                            norwegian: "TEMPOKILDE"),
                        value: isTreadmill
                            ? ATHLTHLocalization.choose(
                                english: "Belt", norwegian: "Mølle")
                            : isIndoor
                                ? ATHLTHLocalization.choose(
                                    english: "Indoor", norwegian: "Inne")
                                : "GPS",
                        unit: nil
                    )
                }

                if isTreadmill {
                    Divider()
                        .opacity(0.42)
                        .padding(.horizontal, 15)

                    HStack(spacing: 12) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "TREADMILL INCLINE",
                                norwegian: "STIGNING PÅ TREDEMØLLE"
                            ),
                            systemImage: "arrow.up.right"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)

                        Spacer(minLength: 0)

                        Text(String(
                            format: "%.1f%%",
                            workout.treadmillInclinePercent ?? 0
                        ))
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }

                stepFooter(at: context.date)
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
    }

    /// Walking uses a deliberately simpler Basic layout. Same recording
    /// values, one stable compact card, no redundant running pace hero.
    private func walkingMetricsPanel(
        distance: Double,
        elapsed: TimeInterval,
        averagePace: Double?,
        at date: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(ATHLTHLocalization.choose(
                    english: "WALK IN PROGRESS", norwegian: "GÅTUR PÅGÅR"
                ), systemImage: "figure.walk")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Spacer()
                Circle().fill(ATHLTHTheme.accentDeep).frame(width: 7, height: 7)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(ATHLTHLocalization.choose(
                        english: "DISTANCE", norwegian: "DISTANSE"
                    ))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f", distance))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(isMetric ? "km" : "mi")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 1, height: 97)

                VStack(alignment: .leading, spacing: 7) {
                    Text(ATHLTHLocalization.choose(
                        english: "ACTIVE TIME", norwegian: "AKTIV TID"
                    ))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(elapsedText(elapsed))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().opacity(0.55)

            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Text(ATHLTHLocalization.choose(
                    english: "Average pace", norwegian: "Snittempo"
                ))
                Spacer(minLength: 8)
                Text(paceValue(averagePace) + (isMetric ? " /km" : " /mi"))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)

            stepFooter(at: date)
        }
        .foregroundStyle(ATHLTHTheme.primaryText)
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthPlanCard(radius: 23)
        .transaction { $0.animation = nil }
    }

    /// One compact, stable footer inside the main metric card; never show
    /// the previous 242-point circular step card above workout metrics.
    @ViewBuilder
    private func stepFooter(at date: Date) -> some View {
        if let plan = workout.structuredRunningWorkout,
           let index = workout.structuredStepIndex,
           plan.steps.indices.contains(index),
           workout.structuredWorkoutComplete != true {
            let step = plan.steps[index]
            let interval = ATHLTHRunningIntervalPosition.resolve(
                steps: plan.steps, currentIndex: index
            )
            let remainingTime = step.durationSeconds.map { target in
                max(0, target - max(0,
                    workout.elapsed(at: date) -
                        (workout.structuredStepStartElapsedTime ?? 0)
                ))
            }
            let elapsed = max(0, workout.elapsed(at: date) -
                (workout.structuredStepStartElapsedTime ?? 0))
            let remainingMeters = step.distanceMeters.map { target in
                max(0, target - max(0,
                    workout.distanceMeters -
                        (workout.structuredStepStartDistanceMeters ?? 0)
                ))
            }
            VStack(alignment: .leading, spacing: 8) {
                Divider().opacity(0.45)
                HStack(alignment: .center, spacing: 13) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.phase == "free"
                            ? ATHLTHLocalization.choose(
                                english: "Free running", norwegian: "Fri løping")
                            : (interval?.isRecovery == true
                                ? ATHLTHLocalization.choose(
                                    english: "Recovery", norwegian: "Pause")
                                : step.title))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if let interval {
                            Text(interval.isRecovery
                                ? ATHLTHLocalization.choose(
                                    english: "Next", norwegian: "Neste") +
                                    " \(interval.nextOrdinal) / \(interval.total)"
                                : "\(interval.ordinal) / \(interval.total)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                        } else if let next = plan.steps.dropFirst(index + 1).first {
                            Text(ATHLTHLocalization.choose(
                                english: "Next", norwegian: "Neste"
                            ) + ": " + next.title)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 5)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(step.measure == .open
                             ? ATHLTHLocalization.choose(
                                english: "ELAPSED", norwegian: "MEDGÅTT")
                             : ATHLTHLocalization.choose(
                                english: "REMAINING", norwegian: "GJENSTÅR"))
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                        if let remainingTime, step.measure == .time {
                            Text(ATHLTHRunStepCountdown.display(remainingTime))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        } else if let remainingMeters, step.measure == .distance {
                            Text(String(format: "%.0f m", remainingMeters))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        } else {
                            Text(ATHLTHRunStepCountdown.display(elapsed))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.73)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    ATHLTHTrainDesign.paleGold.opacity(0.32),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .padding(.horizontal, workout.walking ? 0 : 15)
                .padding(.bottom, workout.walking ? 0 : 14)
            }
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
                            size: 35,
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
            minHeight: 105,
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

/// Isolated live interval card keeps the heavyweight SwiftUI timeline
/// metadata out of the already-large iPhone workout screen view tree.
private struct IPhoneStructuredStepCard: View {
    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    let workout: PhoneWorkout
    let step: WatchRunningWorkoutStep

    var body: some View {
        if step.phase == "free" {
            freeRunningStageCard
        } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(ATHLTHLocalization.choose(
                                english: "WORKOUT STEP", norwegian: "ØKTSTEG"
                            ))
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
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
                                            .font(.headline)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)

                                        Spacer()

                                        if let active =
                                            recorder.active,
                                           let plan =
                                            active
                                                .structuredRunningWorkout {
                                            if plan.steps.count > 1 {
                                                Text(ATHLTHLocalization.choose(
                                                    english: "Step", norwegian: "Steg"
                                                ) + " \((active.structuredStepIndex ?? 0) + 1) / \(plan.steps.count)")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }

                                    Text("DENNE DELEN")
                                        .font(.caption2.weight(.semibold))
                                    ProgressView(value: step.measure == .open ? 0 : progress)
                                        .tint(ATHLTHTheme.accent)
                                        .opacity(step.measure == .open ? 0.3 : 1)
                                    if let plan = workout.structuredRunningWorkout {
                                        Text("HELE ØKTEN")
                                            .font(.caption2.weight(.semibold))
                                        ProgressView(value:
                                            ATHLTHRunningStepEngine.overallProgress(
                                                steps: plan.steps,
                                                index: workout.structuredStepIndex ?? 0,
                                                currentStepProgress: progress
                                            )
                                        )
                                        .tint(ATHLTHTheme.accentDeep)
                                    }

                                    if workout.awaitingMainStart == true {
                                        Label(ATHLTHLocalization.choose(
                                            english: "Ready for main section",
                                            norwegian: "Klar for hoveddel"
                                        ), systemImage: "figure.run.circle.fill")
                                            .font(.title3.weight(.bold))
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    } else {
                                    ZStack {
                                        Circle()
                                            .stroke(ATHLTHTheme.accent.opacity(0.14),
                                                    lineWidth: 8)
                                        Circle()
                                            .trim(from: 0, to: min(max(progress, 0), 1))
                                            .stroke(ATHLTHTheme.accentDeep,
                                                    style: StrokeStyle(
                                                        lineWidth: 8, lineCap: .round))
                                            .rotationEffect(.degrees(-90))

                                        VStack(spacing: 6) {
                                            Text(structuredRemainingText(
                                                step: step, workout: workout,
                                                date: context.date
                                            ))
                                            .font(.system(
                                                size: 57, weight: .bold, design: .rounded))
                                            .monospacedDigit()
                                            .minimumScaleFactor(0.45)
                                            .lineLimit(1)
                                            .contentTransition(.numericText(countsDown: true))
                                            Text(ATHLTHLocalization.choose(
                                                english: step.measure == .open ? "ELAPSED" : "REMAINING",
                                                norwegian: step.measure == .open ? "MEDGÅTT" : "GJENSTÅR"))
                                                .font(.caption2.weight(.bold))
                                                .tracking(1.5)
                                        }
                                        .padding(.horizontal, 16)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    }
                                    .frame(width: 242, height: 242)
                                    .frame(maxWidth: .infinity)

                                    }

                                    if let pace = step.targetPaceMinSecondsPerKilometer,
                                       pace.isFinite, pace > 0 {
                                        Label(String(format: "%.1f km/t · %d:%02d /km",
                                            3_600 / pace, Int(pace) / 60, Int(pace) % 60),
                                            systemImage: "speedometer")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    if let incline = step.targetTreadmillInclinePercent,
                                       incline.isFinite {
                                        Label(String(format: "%.1f %% mål stigning", incline),
                                              systemImage: "mountain.2")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(ATHLTHLocalization.choose(
                                                english: "PACE", norwegian: "TEMPO"
                                            ))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            if let pace = workout.currentPaceSecondsPerKilometer,
                                               pace.isFinite, pace > 0 {
                                                Text(String(format: "%d:%02d /km",
                                                    Int(pace) / 60, Int(pace) % 60))
                                                .font(.headline.monospacedDigit())
                                            } else {
                                                Text("—").font(.headline)
                                            }
                                        }
                                        if let zone = step.targetHeartRateZone {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(ATHLTHLocalization.choose(
                                                    english: "TARGET ZONE", norwegian: "MÅLSONE"
                                                ))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                Text("\(zone)")
                                                    .font(.headline.monospacedDigit())
                                            }
                                        }
                                        Spacer()
                                    }

                                    let effortSeconds = max(
                                        workout.elapsed(at: context.date) -
                                            (workout.structuredStepStartElapsedTime ?? 0), 0
                                    )
                                    let effortMeters = max(
                                        workout.distanceMeters -
                                            (workout.structuredStepStartDistanceMeters ?? 0), 0
                                    )
                                    if let ghostLead = ATHLTHIntervalGhostPacer.leadMeters(
                                        step: step,
                                        elapsedSeconds: effortSeconds,
                                        distanceMeters: effortMeters
                                    ) {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Interval Ghost",
                                                norwegian: "Intervall-Ghost"
                                            ) + " · \(Int(abs(ghostLead).rounded())) m " +
                                            ATHLTHLocalization.choose(
                                                english: ghostLead >= 0 ? "ahead" : "behind",
                                                norwegian: ghostLead >= 0 ? "foran" : "bak"
                                            ),
                                            systemImage: "figure.run.circle"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                    }

                                    HStack(spacing: 8) {
                                        if let next = recorder.nextStructuredStep {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Next", norwegian: "Neste"
                                                ) + ": \(next.title)",
                                                systemImage: "arrow.right.circle"
                                            )
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: 42, alignment: .leading)
                                }
                            }
                        }
        .padding(17)
        .frame(maxWidth: .infinity)
        .athlthPlanCard(radius: 21)
        }
    }

    /// Interval selection does not replace an already-running free segment:
    /// show the real elapsed time and distance until Start interval is tapped.
    private var freeRunningStageCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 44, height: 44)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.55),
                                    in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "FREE RUNNING", norwegian: "FRI LØPING"
                        ))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        Text(ATHLTHLocalization.choose(
                            english: "Recording continues", norwegian: "Registreringen fortsetter"
                        ))
                        .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }

                HStack(alignment: .firstTextBaseline, spacing: 13) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "TIME SO FAR", norwegian: "TID SÅ LANGT"
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Text(ATHLTHRunStepCountdown.display(
                            max(workout.elapsed(at: context.date), 0)
                        ))
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "DISTANCE SO FAR", norwegian: "DISTANSE SÅ LANGT"
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Text(String(format: "%.2f km", workout.distanceMeters / 1000))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }

                if let next = recorder.nextStructuredStep {
                    Divider().opacity(0.6)
                    Label(ATHLTHLocalization.choose(
                        english: "Ready when you are: ", norwegian: "Klar når du er: "
                    ) + next.title, systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .lineLimit(2)
                    Text(ATHLTHLocalization.choose(
                        english: "Start the next part with the button below. All running up to that moment is included in the summary.",
                        norwegian: "Start neste del med knappen nedenfor. All løping fram til da blir med i sammendraget."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .athlthPlanCard(radius: 21)
            .transaction { $0.animation = nil }
        }
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
                return ATHLTHLocalization.choose(english: "Open step", norwegian: "Åpent steg")
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
                ATHLTHRunStepCountdown.display(remaining)

        case .distance:
            guard let target =
                step.distanceMeters
            else {
                return ATHLTHLocalization.choose(english: "Open step", norwegian: "Åpent steg")
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
            let elapsed = max(workout.elapsed(at: date) -
                (workout.structuredStepStartElapsedTime ?? 0), 0)
            return ATHLTHRunStepCountdown.display(elapsed)
        }
    }


}

struct IPhoneWorkoutView: View {
    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var pets: ATHLTHPetStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var realtime: ATHLTHRealtimeSocialStore
    @EnvironmentObject private var ghostRace: GhostRaceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var socialCompanion =
        SocialWorkoutCompanionStore()
    @State private var confirmFinish = false
    @State private var showingSpotifyControls = false
    @State private var followMe = true
    @State private var showingTreadmillInclineEditor = false
    @State private var showingLiveAudioCoach = false
    @State private var showingAIConversation = false
    @State private var showingTreadmillSpeedEditor = false
    @State private var showingAddRunningWorkout = false
    @State private var showingWorkoutOverview = false
    @State private var showingManualEnvironmentChoice = false
    @State private var showingAutomaticIndoorSuggestion = false
    @State private var treadmillInclineDraft = 0.0
    @State private var treadmillInclineEditingWorkoutID:
        UUID?
    @State private var routeCamera:
        MapCameraPosition = .automatic

    private func runningPulseZones(
        for workout: PhoneWorkout, at now: Date
    ) -> some View {
        let activeStep: WatchRunningWorkoutStep? = {
            guard let plan = workout.structuredRunningWorkout,
                  let index = workout.structuredStepIndex,
                  plan.steps.indices.contains(index)
            else { return nil }
            return plan.steps[index]
        }()
        // History cache is not live telemetry. Show an actual heart rate only
        // when HealthKit has a suitably recent sensor sample.
        let freshPulse: Double? = {
            guard let sample = health.heart.latestHeartRate,
                  let time = health.heart.latestHeartRateDate,
                  now.timeIntervalSince(time) >= -2,
                  now.timeIntervalSince(time) <= 15
            else { return nil }
            return sample
        }()
        let maximum = workout.structuredRunningWorkout?.heartRateZoneMaximumBPM ??
            ATHLTHHeartRateZones.resolvedMaximumBPM(
                configured: session.onboardingProfile?.maximumHeartRateBPM,
                dateOfBirth: session.onboardingProfile?.dateOfBirth,
                now: now,
                usesFemaleEstimate: session.onboardingProfile?.healthSex == .female
            )
        return ATHLTHRunningPulseZoneGauge(
            heartRateBPM: freshPulse,
            maximumHeartRateBPM: maximum,
            targetHeartRateZone: activeStep?.targetHeartRateZone,
            targetMinimumBPM: nil,
            targetMaximumBPM: nil,
            targetPercentMin: activeStep?.targetHeartRatePercentMin,
            targetPercentMax: activeStep?.targetHeartRatePercentMax
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if let workout = recorder.active {
                    VStack(
                        alignment: .leading,
                        spacing: 13
                    ) {
                        premiumWorkoutHeader(workout)

                        IPhoneWorkoutLiveMetricsPanel(
                            workout: workout,
                            isMetric:
                                settings
                                    .measurementPreference ==
                                .metric
                        )
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            runningPulseZones(
                                for: workout, at: context.date
                            )
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                        }

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

                    if let ghostTitle = workout.ghostRaceTitle {
                        Section {
                            ATHLTHGhostLiveComparisonTable(
                                name: ghostTitle,
                                distanceMeters: workout.distanceMeters,
                                signedLeadMeters: workout.ghostDistanceDeltaMeters,
                                timeGapSeconds: workout.ghostTimeDeltaSeconds
                            )
                            if realtime.selectedLiveGhostSessionID != nil {
                                liveGhostConnectionLabel
                            }
                            Button {
                                recorder.disableGhostDuringWorkout()
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Turn off Ghost Race",
                                        norwegian: "Slå av Ghost Race"
                                    ), systemImage: "eye.slash"
                                )
                                .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        } header: {
                            Text("Ghost")
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

                            HStack(alignment: .center, spacing: 12) {
                                let cue = recorder.liveRouteNavigationCue
                                Image(systemName: cue?.symbol ?? "arrow.up")
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundStyle(
                                        cue?.offRoute == true
                                            ? Color.orange : ATHLTHPlanDesign.accentInk
                                    )
                                    .frame(width: 37)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(ATHLTHLocalization.choose(
                                        english: cue?.offRoute == true
                                            ? "BACK TO ROUTE" : "NEXT TURN",
                                        norwegian: cue?.offRoute == true
                                            ? "TILBAKE TIL RUTEN" : "NESTE SVING"
                                    ))
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    Text(cue?.text(norwegian: ATHLTHLocalization.isNorwegian)
                                        ?? ATHLTHLocalization.choose(
                                            english: "Follow the highlighted route.",
                                            norwegian: "Følg den markerte ruten videre."
                                        ))
                                        .font(.subheadline.weight(.semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 2)
                                if let meters = cue?.distanceMeters {
                                    Text(meters < 1000
                                        ? String(format: "%.0f m", meters)
                                        : String(format: "%.1f km", meters / 1000))
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                }
                            }
                            .padding(11)
                            .background(
                                ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 15)
                            )

                            if recorder.canRunBackToStart {
                                Button {
                                    recorder.startReturnToRouteStart()
                                } label: {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english: "Run back to start",
                                            norwegian: "Løp tilbake til start"
                                        ),
                                        systemImage: "arrow.uturn.backward"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ATHLTHPlanDesign.accentInk)
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

                    // Historical and target Ghost races use a fixed route,
                    // not the cloud-based Live Ghost location feed.
                    if let reference = ghostRace.reference,
                       workout.ghostRaceTitle != nil,
                       workout.runEnvironment == .outdoor {
                        ATHLTHGhostRaceLiveCourseMap(
                            reference: reference,
                            comparison: ghostRace.comparison,
                            runnerTrail: workout.points.map {
                                $0.location.coordinate
                            },
                            paused: workout.resumedAt == nil,
                            mapHeight: 300
                        )
                        .listRowInsets(EdgeInsets(
                            top: 8, leading: 14, bottom: 10, trailing: 14
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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

                    if workout.runEnvironment == .outdoor &&
                       ghostRace.reference == nil {
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

                                if let recorded = workout.recordedRunningSteps,
                                   !recorded.isEmpty {
                                    DisclosureGroup(
                                        ATHLTHLocalization.choose(
                                            english: "Time per workout phase",
                                            norwegian: "Tid per øktdel"
                                        )
                                    ) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            ForEach(recorded.sorted {
                                                $0.index < $1.index
                                            }, id: \.index) { phase in
                                                HStack(alignment: .firstTextBaseline) {
                                                    Text(phase.title)
                                                        .font(.subheadline.weight(.medium))
                                                    Spacer(minLength: 8)
                                                    VStack(alignment: .trailing, spacing: 3) {
                                                        Text(ATHLTHRunStepCountdown.display(
                                                            phase.activeSeconds
                                                        ))
                                                        .font(.subheadline.monospacedDigit())
                                                        Text(String(
                                                            format: "%.2f km",
                                                            max(0, phase.distanceMeters) / 1000
                                                        ))
                                                        .font(.caption.monospacedDigit())
                                                        .foregroundStyle(.secondary)
                                                    }
                                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                                }
                                            }
                                        }
                                        .padding(.top, 9)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                }

                                if workout.runEnvironment == .treadmill &&
                                   workout.indoorVenue != .indoorRunning {
                                    if workout.treadmillSpeedKilometersPerHour != nil {
                                        Text(ATHLTHLocalization.choose(
                                            english: "Distance from entered belt speed",
                                            norwegian: "Distanse fra oppgitt møllehastighet"
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    if let loggedAverage =
                                        workout.averageLoggedTreadmillSpeedKilometersPerHour {
                                        Text(ATHLTHLocalization.format(
                                            english: "Logged average belt speed: %.1f km/h",
                                            norwegian: "Registrert snitthastighet: %.1f km/t",
                                            loggedAverage
                                        ))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    }
                                    if let entries = workout.treadmillSpeedHistory,
                                       entries.count > 1 {
                                        Text(ATHLTHLocalization.format(
                                            english: "%d manual speed entries saved",
                                            norwegian: "%d manuelle hastighetsmålinger lagret",
                                            entries.count
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 8) {
                                        Label(
                                            ATHLTHLocalization.format(
                                                english:
                                                    "%.1f%% incline",
                                                norwegian:
                                                    "%.1f%% stigning",
                                                workout
                                                    .treadmillInclinePercent ??
                                                0
                                            ),
                                            systemImage:
                                                "arrow.up.right"
                                        )
                                        .font(
                                            .caption
                                                .weight(
                                                    .semibold
                                                )
                                        )

                                        Spacer()

                                        Button(
                                            ATHLTHLocalization.choose(
                                                english: "Adjust",
                                                norwegian: "Juster"
                                            )
                                        ) {
                                            treadmillInclineEditingWorkoutID =
                                                workout.id
                                            treadmillInclineDraft =
                                                recorder
                                                    .treadmillInclinePercent(
                                                        for:
                                                            workout.id
                                                    ) ??
                                                workout
                                                    .treadmillInclinePercent ??
                                                0
                                            showingTreadmillInclineEditor =
                                                true
                                        }
                                        .buttonStyle(.borderless)
                                        .font(
                                            .caption
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                    }
                                }

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
            // Realtime sensor updates must not change the viewport anchor.
            // Particularly important when a planned phase adds/removes labels.
            .defaultScrollAnchor(.top, for: .sizeChanges)
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
            .safeAreaInset(edge: .top, spacing: 0) {
                if let workout = recorder.active {
                    VStack(spacing: 6) {
                        ATHLTHLiveWorkoutTopStrip(
                            title: workout.walking
                                ? ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
                                : ATHLTHLocalization.choose(english: "Running", norwegian: "Løping"),
                            subtitle: workout.title,
                            spotifyExpanded: showingSpotifyControls,
                            addEnabled: !workout.walking,
                            finishDisabled: recorder.saving,
                            onOverview: { showingWorkoutOverview = true },
                            onMinimize: {
                                recorder.minimizeWorkout()
                                dismiss()
                            },
                            onSpotify: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingSpotifyControls.toggle()
                                }
                            },
                            onAdd: { showingAddRunningWorkout = true },
                            onFinish: { confirmFinish = true }
                        )
                        if showingSpotifyControls {
                            ATHLTHLiveSpotifyExpandedBar()
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if workout.audioCoachConfiguration?.enabled == true {
                            HStack {
                                ATHLTHWorkoutAudioDock(
                                    showSpotifyLauncher: false,
                                    inlinePopovers: true,
                                    compactAlignment: .leading,
                                    coachVisible: true,
                                    coachEnabled: true,
                                    coachPaused: recorder.coachSpeechPaused,
                                    coachManagedOnWatch: false,
                                    canReplayCoach: recorder.canReplayLastCoachMessage,
                                    onCoachStatus: { recorder.announceCoachStatusNow() },
                                    onCoachTogglePause: {
                                        recorder.setCoachSpeechPaused(!recorder.coachSpeechPaused)
                                    },
                                    onCoachReplay: { recorder.replayLastCoachMessage() },
                                    onCoachSettings: { showingLiveAudioCoach = true }
                                )
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .background(ATHLTHTheme.canvasTop)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let workout = recorder.active {
                    VStack(spacing: 0) {
                        runningNextControl(workout)
                    }
                }
            }
            .onAppear {
                if recorder.indoorSuggestionAvailable {
                    showingAutomaticIndoorSuggestion = true
                }
            }
            .onChange(of: recorder.indoorSuggestionAvailable) { _, available in
                if available { showingAutomaticIndoorSuggestion = true }
            }
            .confirmationDialog(
                ATHLTHLocalization.choose(
                    english: "Are you running indoors?",
                    norwegian: "Trener du innendørs?"
                ),
                isPresented: $showingAutomaticIndoorSuggestion,
                titleVisibility: .visible
            ) {
                ForEach(ATHLTHIndoorRunVenue.allCases) { venue in
                    Button(venue.title) {
                        _ = recorder.switchRunningEnvironmentToIndoor(venue)
                    }
                }
                Button(ATHLTHLocalization.choose(
                    english: "Continue outdoors", norwegian: "Fortsett utendørs"
                )) {
                    recorder.dismissIndoorSuggestion()
                }
            } message: {
                Text(ATHLTHLocalization.choose(
                    english: "Less than 100 metres of reliable GPS movement in 15 minutes. Choose your running environment. Your workout continues.",
                    norwegian: "Under 100 meter pålitelig GPS-forflytning på 15 minutter. Velg treningsmiljø – økten fortsetter."
                ))
            }
            .confirmationDialog(
                ATHLTHLocalization.choose(
                    english: "Change running environment",
                    norwegian: "Endre treningsmiljø"
                ),
                isPresented: $showingManualEnvironmentChoice,
                titleVisibility: .visible
            ) {
                ForEach(ATHLTHIndoorRunVenue.allCases) { venue in
                    Button(venue.title) {
                        _ = recorder.switchRunningEnvironmentToIndoor(venue)
                    }
                }
                Button(ATHLTHLocalization.choose(
                    english: recorder.active?.runEnvironment == .outdoor
                        ? "Continue outdoors" : "Cancel",
                    norwegian: recorder.active?.runEnvironment == .outdoor
                        ? "Fortsett utendørs" : "Avbryt"
                )) {
                    recorder.dismissIndoorSuggestion()
                }
            } message: {
                Text(ATHLTHLocalization.choose(
                    english: "Indoor running does not use GPS. Treadmill distance needs entered belt speed.",
                    norwegian: "Innendørs løping bruker ikke GPS. Distanse på tredemølle krever oppgitt møllehastighet."
                ))
            }
            .sheet(isPresented: $showingLiveAudioCoach) {
                IPhoneAudioCoachLiveSheet()
                    .environmentObject(recorder)
                    .environmentObject(settings)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingWorkoutOverview) {
                NavigationStack {
                    List {
                        if let workout = recorder.active {
                            let steps = workout.structuredRunningWorkout?.steps ?? []
                            if !steps.isEmpty {
                                ForEach(steps.indices, id: \.self) { index in
                                    let step = steps[index]
                                    HStack(spacing: 11) {
                                        Image(systemName: "list.number")
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(index + 1). " + step.title)
                                                .font(.subheadline.weight(.semibold))
                                            if let duration = step.durationSeconds, duration > 0 {
                                                Text(ATHLTHWorkoutDurationEstimator.conciseDuration(duration))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            } else if let meters = step.distanceMeters, meters > 0 {
                                                Text(String(format: "%.0f m", meters))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if index == (workout.structuredStepIndex ?? 0) {
                                            Text(ATHLTHLocalization.choose(
                                                english: "Now", norwegian: "Nå"
                                            ))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                        }
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            } else {
                                Label(
                                    workout.walking
                                        ? ATHLTHLocalization.choose(
                                            english: "Free walk", norwegian: "Fri gåtur"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Free run", norwegian: "Fri løping"
                                        ),
                                    systemImage: workout.walking
                                        ? "figure.walk" : "figure.run"
                                )
                            }
                        }
                    }
                    .navigationTitle(ATHLTHLocalization.choose(
                        english: "Workout overview", norwegian: "Øktoversikt"
                    ))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(ATHLTHLocalization.choose(
                                english: "Done", norwegian: "Ferdig"
                            )) { showingWorkoutOverview = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .accessibilityIdentifier("athlth-run-live-workout-overview")
            }
            .sheet(isPresented: $showingAddRunningWorkout) {
                ActiveHybridWorkoutPicker(runningOnly: true) { session, startNow in
                    guard let template = session.runningWorkout else {
                        return false
                    }
                    return recorder.appendRunningIntervalsDuringWorkout(
                        template, startNow: startNow
                    )
                }
                .environmentObject(runningLibrary)
            }
            .sheet(isPresented: $showingTreadmillSpeedEditor) {
                TreadmillSpeedEditorView(
                    initialValue:
                        recorder.active?.treadmillSpeedHistory?.last?.kilometersPerHour ??
                        recorder.active?.treadmillSpeedKilometersPerHour ?? 0,
                    onSave: { recorder.setTreadmillSpeedKilometersPerHour($0) },
                    onHistorySave: { recorder.recordTreadmillHistoricalSpeedKilometersPerHour($0) }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingAIConversation) {
                ATHLTHGroqVoiceCoachView()
                    .environmentObject(recorder)
                    .environmentObject(settings)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(
                isPresented:
                    $showingTreadmillInclineEditor
            ) {
                TreadmillInclineEditorView(
                    initialValue:
                        treadmillInclineDraft
                ) { value in
                    if let workoutID =
                            treadmillInclineEditingWorkoutID {
                        recorder
                            .setCompletedTreadmillInclinePercent(
                                value,
                                workoutID:
                                    workoutID
                            )
                        treadmillInclineEditingWorkoutID =
                            nil
                    } else {
                        recorder
                            .setTreadmillInclinePercent(
                                value
                            )
                    }

                    treadmillInclineDraft =
                        value
                }
            }
            .sheet(isPresented: $confirmFinish) {
                if let active = recorder.active {
                    ATHLTHWorkoutFinishSheet(
                        metrics: [
                            ATHLTHWorkoutFinishMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Elapsed", norwegian: "Varighet"
                                ),
                                value: "\(Int(max(0, active.elapsed(at: Date())) / 60)) min",
                                symbol: "clock"
                            ),
                            ATHLTHWorkoutFinishMetric(
                                title: ATHLTHLocalization.choose(
                                    english: "Distance", norwegian: "Distanse"
                                ),
                                value: String(
                                    format: "%.2f km",
                                    max(active.distanceMeters, 0) / 1000
                                ),
                                symbol: active.walking ? "figure.walk" : "figure.run"
                            )
                        ],
                        progress: nil,
                        remainingWarning: nil,
                        saveExplanation: ATHLTHLocalization.choose(
                            english: "The recorded activity will be saved. You can review the full workout summary afterwards.",
                            norwegian: "Den registrerte aktiviteten lagres. Du kan se hele treningssammendraget etterpå."
                        ),
                        saving: recorder.saving,
                        onFinish: {
                            Task {
                                await recorder.finish()
                                guard recorder.active == nil else { return }
                                confirmFinish = false
                                await realtime.leaveCurrentLiveWorkout()
                            }
                        },
                        onContinue: { confirmFinish = false }
                    )
                }
            }
            .interactiveDismissDisabled(recorder.saving)
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
        .task(
            id:
                social.recordingWorkoutSessionID
        ) {
            guard
                let sessionID =
                    social.recordingWorkoutSessionID,
                let userID =
                    social.currentUserID
            else {
                return
            }

            while !Task.isCancelled {
                guard let workout =
                        recorder.active
                else {
                    return
                }

                let displayName =
                    social
                        .workoutParticipants
                        .first {
                            $0.sessionID ==
                                sessionID &&
                            $0.userID ==
                                userID
                        }?
                        .displayNameSnapshot ??
                    ATHLTHLocalization.choose(
                        english: "You",
                        norwegian: "Deg"
                    )

                let elapsed =
                    workout
                        .accumulatedSeconds +
                    (
                        workout
                            .resumedAt
                            .map {
                                max(
                                    Date()
                                        .timeIntervalSince(
                                            $0
                                        ),
                                    0
                                )
                            } ??
                        0
                    )

                await socialCompanion
                    .publishCardio(
                        sessionID:
                            sessionID,
                        userID:
                            userID,
                        displayName:
                            displayName,
                        walking:
                            workout.walking,
                        title:
                            workout
                                .workoutTitle,
                        distanceMeters:
                            workout
                                .distanceMeters,
                        elapsedSeconds:
                            elapsed,
                        paceSecondsPerKilometer:
                            workout
                                .currentPaceSecondsPerKilometer
                    )

                try? await Task.sleep(
                    for: .seconds(3)
                )
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
            Button {
                if workout.runEnvironment == .treadmill &&
                   workout.indoorVenue != .indoorRunning {
                    treadmillInclineEditingWorkoutID = nil
                    treadmillInclineDraft = workout.treadmillInclinePercent ?? 0
                    showingTreadmillInclineEditor = true
                } else {
                    showingManualEnvironmentChoice = true
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: workout.runEnvironment == .treadmill
                          ? "figure.run.treadmill" : "location.fill")
                    Text(workout.runEnvironment == .treadmill
                         ? ATHLTHLocalization.choose(english: "Indoor", norwegian: "Inne")
                         : "GPS")
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(Color.white.opacity(0.88), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-run-environment-menu")

            if workout.runEnvironment == .treadmill &&
               workout.indoorVenue != .indoorRunning {
                Button { showingTreadmillSpeedEditor = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "speedometer")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.treadmillSpeedKilometersPerHour.map {
                                ATHLTHLocalization.format(
                                    english: "Belt speed · %.1f km/h",
                                    norwegian: "Møllehastighet · %.1f km/t", $0
                                )
                            } ?? ATHLTHLocalization.choose(
                                english: "Enter belt speed", norwegian: "Oppgi møllehastighet"
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: "Distance calculated from entered speed and active time",
                                norwegian: "Distanse beregnes fra oppgitt hastighet og aktiv tid"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                        Spacer()
                        Image(systemName: "slider.horizontal.3")
                    }
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .padding(14)
                    .background(Color.white.opacity(0.93), in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(.plain)
            }

            Text(workout.title == "Free Run"
                 ? ATHLTHLocalization.choose(english: "Free Run", norwegian: "Fri løping")
                 : workout.title)
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
                            english: "Indoor run · recorded with iPhone",
                            norwegian: "Innendørs løping · registreres med iPhone"
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

                if let last = workout.points.last,
                   (-5...30).contains(Date().timeIntervalSince(last.timestamp)) {
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
                } else {
                    // Immediately shows the operating system's live blue dot
                    // before the route recorder has accepted its first point.
                    UserAnnotation()
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
                MapUserLocationButton()
            }
            .onAppear {
                routeCamera = followMe
                    ? .userLocation(fallback: .region(workoutMapRegion(for: workout)))
                    : .region(workoutMapRegion(for: workout))
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

    /// One primary progression action, separate from the stop confirmation.
    private func runningNextControl(_ workout: PhoneWorkout) -> some View {
        let hasNext = recorder.nextStructuredStep != nil ||
            workout.awaitingMainStart == true
        // Every explicit Next press must be actionable. Automatic advancement
        // is controlled independently in the recording engine.
        let mayAdvance = hasNext
        return Button {
            if mayAdvance {
                recorder.advanceStructuredStepManually()
            } else {
                showingAddRunningWorkout = true
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: mayAdvance ? "arrow.right.circle.fill" : "plus.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(mayAdvance
                         ? (workout.awaitingMainStart == true
                            ? ATHLTHLocalization.choose(english: "Start main section", norwegian: "Start hoveddel")
                            : ATHLTHLocalization.choose(
                                english: (recorder.nextStructuredStep?.phase == "interval" ||
                                 recorder.nextStructuredStep?.phase == "work")
                                    ? "Start interval" : "Next step",
                                norwegian: (recorder.nextStructuredStep?.phase == "interval" ||
                                 recorder.nextStructuredStep?.phase == "work")
                                    ? "Start intervall" : "Neste steg"
                            ))
                         : ATHLTHLocalization.choose(english: "Add an interval", norwegian: "Legg til intervall"))
                        .font(.headline.weight(.semibold))
                    if mayAdvance, let next = recorder.nextStructuredStep {
                        Text(next.title).font(.caption).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(ATHLTHTheme.accentDeep,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(recorder.saving || workout.resumedAt == nil)
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
                return ATHLTHLocalization.choose(english: "Open step", norwegian: "Åpent steg")
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
                ATHLTHRunStepCountdown.display(remaining)

        case .distance:
            guard let target =
                step.distanceMeters
            else {
                return ATHLTHLocalization.choose(english: "Open step", norwegian: "Åpent steg")
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
            return ATHLTHLocalization.choose(english: "Open step", norwegian: "Åpent steg")
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



private struct IPhoneAudioCoachLiveSheet: View {
    @State private var audioOutputName: String?
    @State private var showDetailedOptions = false
    @EnvironmentObject private var recorder: IPhoneWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    private var configuration: WatchAudioCoachConfiguration {
        recorder.active?.audioCoachConfiguration ?? .disabled
    }

    private var selectedExperience: ATHLTHCoachExperiencePreset? {
        ATHLTHCoachExperiencePreset.allCases.first { preset in
            ATHLTHCoachContentLevel.matching(configuration) == preset.contentLevel
                && configuration.timeIntervalSeconds == nil
                && abs((configuration.distanceIntervalMeters ?? -1)
                    - preset.distanceIntervalKilometers * 1_000) < 0.01
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                ATHLTHPlusFeatureGate(
                    feature: .audioCoach,
                    title: "Audio Coach · ATHLTH+",
                    message: ATHLTHLocalization.choose(
                        english: "Live spoken workout updates are part of ATHLTH+.",
                        norwegian: "Talte oppdateringer under trening er en del av ATHLTH+."
                    )
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        coachCard {
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .font(.title2)
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Audio Coach").font(.headline)
                                    Text(ATHLTHLocalization.choose(
                                        english: "Only for this workout",
                                        norwegian: "Gjelder bare denne økten"
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("Audio Coach", isOn: enabledBinding)
                                    .labelsHidden()
                                    .tint(ATHLTHTheme.accentDeep)
                            }
                        }

                        if configuration.enabled {
                            coachCard {
                                HStack(spacing: 11) {
                                    Image(systemName: "airpodspro")
                                        .font(.title2)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ATHLTHLocalization.choose(
                                            english: "Audio output",
                                            norwegian: "Lydutgang"
                                        ))
                                        .font(.subheadline.weight(.semibold))
                                        Text(audioOutputName ??
                                            ATHLTHLocalization.choose(
                                                english: "System output",
                                                norwegian: "Systemets lydutgang"
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                        .lineLimit(1)
                                    }
                                    Spacer(minLength: 5)
                                    ATHLTHAudioRouteControl(compact: true)
                                }
                                .accessibilityElement(children: .contain)
                            }

                            coachCard {
                                VStack(alignment: .leading, spacing: 11) {
                                    HStack {
                                        Label(
                                            ATHLTHLocalization.choose(
                                                english: "Last coach message",
                                                norwegian: "Siste coachbeskjed"
                                            ),
                                            systemImage: "text.bubble"
                                        )
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                        Spacer()
                                        Text(ATHLTHLocalization.choose(
                                            english: "This workout only",
                                            norwegian: "Kun denne økten"
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                    }

                                    Text(recorder.lastCoachMessage ??
                                        ATHLTHLocalization.choose(
                                            english: "No spoken message yet",
                                            norwegian: "Ingen beskjed ennå"
                                        )
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .lineLimit(3)

                                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                                        Button {
                                            recorder.replayLastCoachMessage()
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Listen again",
                                                    norwegian: "Hør igjen"
                                                ),
                                                systemImage: "arrow.counterclockwise"
                                            )
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 43)
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(!recorder.canReplayLastCoachMessage)
                                    }
                                    Text(ATHLTHLocalization.choose(
                                        english: "Recent messages can be replayed for 45 seconds. Never stored.",
                                        norwegian: "Nylige beskjeder kan høres igjen i 45 sekunder. Lagres ikke."
                                    ))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                            }

                            coachCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 10) {
                                        Image(systemName:
                                            recorder.coachSpeechPaused
                                                ? "speaker.slash.circle.fill"
                                                : "waveform.circle.fill"
                                        )
                                        .foregroundStyle(
                                            recorder.coachSpeechPaused
                                                ? ATHLTHTheme.mutedText
                                                : ATHLTHTheme.accentDeep
                                        )
                                        .font(.title2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ATHLTHLocalization.choose(
                                                english: "Live voice control",
                                                norwegian: "Talekontroll under økten"
                                            ))
                                            .font(.subheadline.weight(.semibold))
                                            Text(ATHLTHLocalization.choose(
                                                english: recorder.coachSpeechPaused
                                                    ? "Voice paused · workout keeps recording"
                                                    : "Voice on · workout keeps recording",
                                                norwegian: recorder.coachSpeechPaused
                                                    ? "Tale pauset · økten registreres videre"
                                                    : "Tale aktiv · økten registreres videre"
                                            ))
                                            .font(.caption)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                        }
                                    }
                                    HStack(spacing: 9) {
                                        Button {
                                            recorder.setCoachSpeechPaused(
                                                !recorder.coachSpeechPaused
                                            )
                                        } label: {
                                            Label(
                                                recorder.coachSpeechPaused
                                                    ? ATHLTHLocalization.choose(
                                                        english: "Resume voice",
                                                        norwegian: "Fortsett tale"
                                                    )
                                                    : ATHLTHLocalization.choose(
                                                        english: "Pause voice",
                                                        norwegian: "Pause tale"
                                                    ),
                                                systemImage: recorder.coachSpeechPaused
                                                    ? "play.fill"
                                                    : "pause.fill"
                                            )
                                            .frame(maxWidth: .infinity, minHeight: 45)
                                        }
                                        .buttonStyle(.bordered)
                                        .accessibilityHint(ATHLTHLocalization.choose(
                                            english: "Does not pause workout recording",
                                            norwegian: "Pauser ikke treningsregistreringen"
                                        ))

                                        Button {
                                            recorder.announceCoachStatusNow()
                                        } label: {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "Status now",
                                                    norwegian: "Status nå"
                                                ),
                                                systemImage: "waveform"
                                            )
                                            .frame(maxWidth: .infinity, minHeight: 45)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(ATHLTHTheme.accentDeep)
                                        .disabled(recorder.coachSpeechPaused)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                }
                            }

                            coachCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "waveform.path")
                                            .foregroundStyle(ATHLTHTheme.accentDeep)
                                        Text(ATHLTHLocalization.choose(
                                            english: "How much guidance?",
                                            norwegian: "Hvor mye veiledning?"
                                        ))
                                        .font(.headline)
                                    }
                                    HStack(spacing: 7) {
                                        ForEach(ATHLTHCoachExperiencePreset.allCases) { preset in
                                            Button {
                                                update { value in
                                                    value = preset.contentLevel.applying(to: value)
                                                    value.distanceIntervalMeters =
                                                        preset.distanceIntervalKilometers * 1_000
                                                    value.timeIntervalSeconds = nil
                                                }
                                            } label: {
                                                VStack(spacing: 4) {
                                                    Text(preset.title)
                                                        .font(.subheadline.weight(.semibold))
                                                    Text(preset.subtitle)
                                                        .font(.caption2)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.center)
                                                        .minimumScaleFactor(0.85)
                                                }
                                                .frame(maxWidth: .infinity, minHeight: 66)
                                                .foregroundStyle(selectedExperience == preset
                                                    ? Color.white : ATHLTHTheme.primaryText)
                                                .background(selectedExperience == preset
                                                    ? ATHLTHTheme.accentDeep : ATHLTHTheme.canvasBottom,
                                                    in: RoundedRectangle(cornerRadius: 13))
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityAddTraits(
                                                selectedExperience == preset ? .isSelected : []
                                            )
                                        }
                                    }
                                    if selectedExperience == nil {
                                        Text(ATHLTHLocalization.choose(
                                            english: "Your custom settings are preserved until you choose a level.",
                                            norwegian: "Ditt tilpassede oppsett beholdes til du velger et nivå."
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                    HStack(spacing: 8) {
                                        ForEach([
                                            ATHLTHCoachSpeechStyle.balanced,
                                            .motivating
                                        ]) { style in
                                            Button {
                                                update { $0.speechStyle = style }
                                            } label: {
                                                Label(style.title, systemImage: style == .motivating
                                                    ? "flame.fill" : "waveform")
                                                    .font(.caption.weight(.semibold))
                                                    .frame(maxWidth: .infinity, minHeight: 42)
                                                    .foregroundStyle((configuration.speechStyle ?? .balanced) == style
                                                        ? Color.white : ATHLTHTheme.primaryText)
                                                    .background((configuration.speechStyle ?? .balanced) == style
                                                        ? ATHLTHTheme.accentDeep : ATHLTHTheme.canvasBottom,
                                                        in: RoundedRectangle(cornerRadius: 13))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showDetailedOptions.toggle()
                                        }
                                    } label: {
                                        HStack {
                                            Label(
                                                ATHLTHLocalization.choose(
                                                    english: "More settings",
                                                    norwegian: "Flere innstillinger"
                                                ),
                                                systemImage: "slider.horizontal.3"
                                            )
                                            Spacer()
                                            Image(systemName: showDetailedOptions
                                                ? "chevron.up" : "chevron.down")
                                        }
                                        .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if showDetailedOptions {
                            coachCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "quote.bubble")
                                            .foregroundStyle(ATHLTHTheme.accentDeep)
                                        Text(ATHLTHLocalization.choose(
                                            english: "Speaking style",
                                            norwegian: "Talemåte"
                                        ))
                                        .font(.headline)
                                    }
                                    LazyVGrid(
                                        columns: [
                                            GridItem(.flexible(), spacing: 8),
                                            GridItem(.flexible(), spacing: 8)
                                        ],
                                        spacing: 8
                                    ) {
                                        ForEach(ATHLTHCoachSpeechStyle.allCases) { style in
                                            Button {
                                                update { $0.speechStyle = style }
                                            } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(style.title)
                                                        .font(.subheadline.weight(.semibold))
                                                    Text(style.subtitle)
                                                        .font(.caption2)
                                                        .lineLimit(2)
                                                        .frame(
                                                            maxWidth: .infinity,
                                                            alignment: .leading
                                                        )
                                                }
                                                .foregroundStyle(
                                                    (configuration.speechStyle ?? .balanced) == style
                                                        ? Color.white
                                                        : ATHLTHTheme.primaryText
                                                )
                                                .frame(maxWidth: .infinity, minHeight: 54)
                                                .padding(10)
                                                .background(
                                                    (configuration.speechStyle ?? .balanced) == style
                                                        ? ATHLTHTheme.accentDeep
                                                        : ATHLTHTheme.canvasBottom,
                                                    in: RoundedRectangle(cornerRadius: 13)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    Text(ATHLTHLocalization.choose(
                                        english: "Only for this workout. Does not affect message frequency.",
                                        norwegian: "Kun denne økten. Påvirker ikke talefrekvensen."
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                            }

                            coachCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Frequency", norwegian: "Hvor ofte?"
                                    ))
                                    .font(.headline)
                                    Toggle(
                                        ATHLTHLocalization.choose(
                                            english: "By distance", norwegian: "Etter distanse"
                                        ),
                                        isOn: distanceTriggerBinding
                                    )
                                    if configuration.distanceIntervalMeters != nil {
                                        Stepper(
                                            distanceIntervalTitle,
                                            value: distanceIntervalBinding,
                                            in: 250...10_000,
                                            step: 250
                                        )
                                    }
                                    Divider()
                                    Toggle(
                                        ATHLTHLocalization.choose(
                                            english: "By time", norwegian: "Etter tid"
                                        ),
                                        isOn: timeTriggerBinding
                                    )
                                    if configuration.timeIntervalSeconds != nil {
                                        Stepper(
                                            timeIntervalTitle,
                                            value: timeIntervalBinding,
                                            in: 60...3_600,
                                            step: 60
                                        )
                                    }
                                }
                                .tint(ATHLTHTheme.accentDeep)
                            }

                            coachCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "What should I hear?",
                                        norwegian: "Hva skal coachen si?"
                                    ))
                                    .font(.headline)
                                    coachToggle(
                                        ATHLTHLocalization.choose(
                                            english: "Distance", norwegian: "Distanse"
                                        ), \.announceDistance
                                    )
                                    coachToggle(
                                        ATHLTHLocalization.choose(
                                            english: "Elapsed time", norwegian: "Tid"
                                        ), \.announceElapsedTime
                                    )
                                    coachToggle(
                                        ATHLTHLocalization.choose(
                                            english: "Average pace",
                                            norwegian: "Gjennomsnittstempo"
                                        ), \.announceAveragePace
                                    )
                                    if recorder.active?.plannedRouteTitle != nil {
                                        coachToggle(
                                            ATHLTHLocalization.choose(
                                                english: "Distance remaining",
                                                norwegian: "Gjenstående rute"
                                            ), \.announceRemainingRouteDistance
                                        )
                                    }
                                    coachToggle(
                                        ATHLTHLocalization.choose(
                                            english: "Clock time", norwegian: "Klokkeslett"
                                        ), \.announceClockTime
                                    )
                                    Toggle(
                                        ATHLTHLocalization.choose(
                                            english: "Lower music while speaking",
                                            norwegian: "Demp musikk når coachen snakker"
                                        ),
                                        isOn: duckBinding
                                    )
                                }
                                .tint(ATHLTHTheme.accentDeep)
                            }
                            }
                        }

                        NavigationLink {
                            ATHLTHAudioCoachSettingsView()
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "slider.horizontal.3")
                                Text(ATHLTHLocalization.choose(
                                    english: "Voice and default settings",
                                    norwegian: "Stemme og standardinnstillinger"
                                ))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .padding(15)
                            .background(
                                Color.white,
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
            .background(ATHLTHTheme.canvasBottom.ignoresSafeArea())
            .navigationTitle("Audio Coach")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                audioOutputName = AVAudioSession.sharedInstance()
                    .currentRoute.outputs.first?.portName
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: AVAudioSession.routeChangeNotification
                )
            ) { _ in
                audioOutputName = AVAudioSession.sharedInstance()
                    .currentRoute.outputs.first?.portName
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ATHLTHLocalization.choose(
                        english: "Done", norwegian: "Ferdig"
                    )) { dismiss() }
                }
            }
        }
    }

    private func coachCard<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .background(
                Color.white.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
    }

    private func update(
        _ change: (inout WatchAudioCoachConfiguration) -> Void
    ) {
        guard recorder.active != nil else { return }
        var next = configuration
        change(&next)
        recorder.updateAudioCoachDuringWorkout(next)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { configuration.enabled },
            set: { enabled in
                if enabled {
                    var next = configuration
                    if next.distanceIntervalMeters == nil &&
                        next.timeIntervalSeconds == nil &&
                        !next.announceDistance &&
                        !next.announceElapsedTime &&
                        !next.announceAveragePace {
                        var draft = AudioCoachDraft()
                        draft.load(from: settings)
                        draft.enabled = true
                        next = draft.configuration()
                    }
                    next.enabled = true
                    recorder.updateAudioCoachDuringWorkout(next)
                } else {
                    update { $0.enabled = false }
                }
            }
        )
    }

    private var distanceTriggerBinding: Binding<Bool> {
        Binding(
            get: { configuration.distanceIntervalMeters != nil },
            set: { enabled in
                update { $0.distanceIntervalMeters = enabled ? 1_000 : nil }
            }
        )
    }

    private var distanceIntervalBinding: Binding<Double> {
        Binding(
            get: { configuration.distanceIntervalMeters ?? 1_000 },
            set: { value in
                update { $0.distanceIntervalMeters = value }
            }
        )
    }

    private var distanceIntervalTitle: String {
        ATHLTHLocalization.format(
            english: "Every %.2f km",
            norwegian: "Hver %.2f km",
            (configuration.distanceIntervalMeters ?? 1_000) / 1_000
        )
    }

    private var timeTriggerBinding: Binding<Bool> {
        Binding(
            get: { configuration.timeIntervalSeconds != nil },
            set: { enabled in
                update { $0.timeIntervalSeconds = enabled ? 600 : nil }
            }
        )
    }

    private var timeIntervalBinding: Binding<Double> {
        Binding(
            get: { configuration.timeIntervalSeconds ?? 600 },
            set: { value in
                update { $0.timeIntervalSeconds = value }
            }
        )
    }

    private var timeIntervalTitle: String {
        let minutes = Int((configuration.timeIntervalSeconds ?? 600) / 60)
        return ATHLTHLocalization.choose(
            english: "Every \(minutes) min",
            norwegian: "Hvert \(minutes). minutt"
        )
    }

    private func coachToggle(
        _ title: String,
        _ keyPath: WritableKeyPath<WatchAudioCoachConfiguration, Bool>
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { configuration[keyPath: keyPath] },
                set: { value in
                    update { $0[keyPath: keyPath] = value }
                }
            )
        )
    }

    private var duckBinding: Binding<Bool> {
        Binding(
            get: { configuration.shouldDuckOtherAudio },
            set: { value in
                update { $0.duckOtherAudio = value }
            }
        )
    }
}

struct TreadmillInclineEditorView: View {
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
                                "You can change incline while the workout is running or correct it after the workout. The value is stored with the workout.",
                            norwegian:
                                "Du kan endre stigning mens økten pågår eller korrigere den etter økten. Verdien lagres med økten."
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


struct TreadmillSpeedEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var speed: Double
    @State private var historyOnly = true
    let onSave: (Double) -> Void
    let onHistorySave: (Double) -> Void

    init(initialValue: Double,
         onSave: @escaping (Double) -> Void,
         onHistorySave: @escaping (Double) -> Void) {
        _speed = State(initialValue: initialValue.isFinite ? min(max(initialValue, 0), 30) : 0)
        self.onSave = onSave
        self.onHistorySave = onHistorySave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $speed, in: 0...30, step: 0.1) {
                        Text(ATHLTHLocalization.format(
                            english: "Belt speed: %.1f km/h",
                            norwegian: "Møllehastighet: %.1f km/t", speed
                        )).monospacedDigit()
                    }
                    Slider(value: $speed, in: 0...30, step: 0.1)
                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "For history and future coaching only",
                            norwegian: "Kun for historikk og fremtidig coaching"
                        ),
                        isOn: $historyOnly
                    )
                } footer: {
                    Text(ATHLTHLocalization.choose(
                        english: historyOnly
                            ? "Stored with your workout and available to the next Audio Coach session. Does not modify live pace or distance."
                            : "Also used to estimate treadmill distance while running. The iPhone does not read treadmill speed automatically.",
                        norwegian: historyOnly
                            ? "Lagres med økten og brukes som historikk for neste Audio Coach. Endrer ikke dagens tempo- eller distanseberegning."
                            : "Brukes også til å anslå distansen mens du løper. iPhone leser ikke møllehastigheten automatisk."
                    ))
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(english: "Belt speed", norwegian: "Møllehastighet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Save", norwegian: "Lagre")) {
                        if historyOnly {
                            onHistorySave(speed)
                        } else {
                            onSave(speed)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
