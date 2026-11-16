import SwiftUI

/// Dedicated interval page. Uses the same step clock and distance already
/// advanced by the Watch workout engine, so no second timer can drift.
struct WatchRunIntervalFocusPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 42

    private var spokenNorwegian: Bool {
        ATHLTHLocalization.choose(english: "en", norwegian: "no") == "no"
    }

    /// One phase per page, with the parent vertical pager owning swipes.
    var body: some View {
        GeometryReader { viewport in
            let compact = viewport.size.height < 205
            if let step = workout.currentStructuredRunningStep {
                let readout = ATHLTHRunIntervalReadout.resolve(
                    step: step,
                    elapsedSeconds: workout.currentStructuredStepElapsedTime,
                    distanceMeters: workout.currentStructuredStepDistanceMeters
                )
                VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundStyle(WatchTheme.accentDeep)
                        Text(ATHLTHLocalization.choose(
                            english: "INTERVAL", norwegian: "INTERVALL"
                        ))
                        .font(.system(size: 10, weight: .bold))
                        Spacer(minLength: 0)
                        if let plan = workout.structuredRunningWorkout {
                            Text("\(workout.structuredStepIndex + 1)/\(plan.steps.count)")
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    Text(step.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if workout.awaitingMainStart {
                        Label(ATHLTHLocalization.choose(
                            english: "READY FOR MAIN", norwegian: "KLAR FOR HOVEDDEL"
                        ), systemImage: "play.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WatchTheme.accentDeep)
                    } else {
                        Text(metricTitle(readout))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WatchTheme.textSecondary)
                        Text(metricValue(readout))
                            .font(.system(size: compact ? 37 : 45,
                                          weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityLabel(metricTitle(readout))
                            .accessibilityValue(accessibleRemaining(readout))
                        if let progress = readout.progress {
                            ProgressView(value: progress)
                                .tint(WatchTheme.liveAction)
                        }
                    }
                    HStack(spacing: 9) {
                        if let target = targetPace(step) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ATHLTHLocalization.choose(
                                    english: "TARGET", norwegian: "MÅL"
                                ))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(WatchTheme.muted)
                                Text(target)
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ATHLTHLocalization.choose(
                                english: "PULSE", norwegian: "PULS"
                            ))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(WatchTheme.muted)
                            Text(workout.hasFreshHeartRate
                                ? "\(Int(workout.heartRate.rounded()))"
                                : "—")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, compact ? 2 : 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Label(ATHLTHLocalization.choose(
                        english: "FREE WORKOUT", norwegian: "FRI ØKT"
                    ), systemImage: "figure.run")
                    Text(ATHLTHLocalization.choose(
                        english: "No scheduled intervals",
                        norwegian: "Ingen planlagte intervaller"
                    ))
                    .font(.headline)
                    Spacer(minLength: 0)
                }
                .padding(9)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private func overallProgress(
        steps: [WatchRunningWorkoutStep],
        index: Int,
        current: Double
    ) -> Double {
        guard !steps.isEmpty else { return 0 }
        let weights = steps.map { step -> Double in
            let estimate = step.durationSeconds ??
                step.distanceMeters.map {
                    ($0 / 1_000) *
                    (step.targetPaceMinSecondsPerKilometer ?? 360)
                } ?? 60
            return estimate.isFinite ? max(estimate, 15) : 60
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        let done = weights.prefix(max(0, min(index, weights.count))).reduce(0, +)
        let this = weights.indices.contains(index) ? weights[index] : 0
        return min(max((done + this * min(max(current, 0), 1)) / total, 0), 1)
    }

    private func heartRateCard(targetZone: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(ATHLTHLocalization.choose(
                english: "PULSE", norwegian: "PULS"
            ), systemImage: "heart.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WatchTheme.liveHeart)
            Text(workout.hasFreshHeartRate && workout.heartRate > 0
                 ? "\(Int(workout.heartRate.rounded()))" : "—")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let zone = targetZone, (1...5).contains(zone) {
                Text(ATHLTHLocalization.choose(
                    english: "TARGET ZONE", norwegian: "MÅLSONE"
                ) + " \(zone)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { number in
                        Capsule()
                            .fill(number == zone
                                  ? WatchTheme.liveHeart : WatchTheme.border)
                            .frame(height: 5)
                    }
                }
            } else {
                Text("bpm")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 14)
    }

    private func accessibleRemaining(
        _ readout: ATHLTHRunIntervalReadout
    ) -> String {
        guard let value = readout.remaining else {
            return ATHLTHLocalization.choose(
                english: "Open interval without a countdown",
                norwegian: "Åpent intervall uten nedtelling"
            )
        }
        switch readout.unit {
        case .seconds:
            return ATHLTHWorkoutAccessibleMetric.duration(
                ceil(value), norwegian: spokenNorwegian
            )
        case .meters:
            return ATHLTHWorkoutAccessibleMetric.distance(
                value, norwegian: spokenNorwegian
            )
        case .open:
            return ATHLTHLocalization.choose(
                english: "Open interval", norwegian: "Åpent intervall"
            )
        }
    }

    private func metricTitle(_ readout: ATHLTHRunIntervalReadout) -> String {
        switch readout.unit {
        case .seconds:
            return ATHLTHLocalization.choose(
                english: "TIME REMAINING", norwegian: "TID IGJEN"
            )
        case .meters:
            return ATHLTHLocalization.choose(
                english: "DISTANCE REMAINING", norwegian: "DISTANSE IGJEN"
            )
        case .open:
            return ATHLTHLocalization.choose(
                english: "OPEN STEP", norwegian: "ÅPENT INTERVALL"
            )
        }
    }

    private func metricValue(_ readout: ATHLTHRunIntervalReadout) -> String {
        guard let remaining = readout.remaining else {
            return "—"
        }
        switch readout.unit {
        case .seconds:
            return clock(remaining)
        case .meters:
            if remaining >= 1_000 {
                return String(format: "%.2f", remaining / 1_000)
            }
            return String(Int(remaining.rounded(.up)))
        case .open:
            return "—"
        }
    }

    private func targetPace(_ step: WatchRunningWorkoutStep) -> String? {
        guard let minimum = step.targetPaceMinSecondsPerKilometer,
              let maximum = step.targetPaceMaxSecondsPerKilometer,
              minimum.isFinite, maximum.isFinite,
              minimum > 0, maximum >= minimum
        else { return nil }
        return "\(clock(minimum))–\(clock(maximum))/km"
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(WatchTheme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 14)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let time = max(0, Int(seconds.isFinite ? seconds.rounded(.up) : 0))
        return String(format: "%d:%02d", time / 60, time % 60)
    }
}

/// Route/Arena comparison page. A stale, paused or unverified GPS gap is never
/// shown as a current lead, even if cached coordinates remain available.
struct WatchRunGhostFocusPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @ScaledMetric(relativeTo: .largeTitle) private var leadSize: CGFloat = 45

    /// Ghost comparison on one full Watch page; no nested scroll.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let ghost = workout.liveSurfaceContext.liveGhost
            let state = ATHLTHLiveGhostWatchSignal.resolve(
                context: ghost,
                isPaused: workout.state == .paused ||
                    workout.automaticPauseActive,
                now: timeline.date
            )
            let isRecordedGhost = ghost == nil && workout.ghostRaceTitle != nil
            let paused = workout.state == .paused || workout.automaticPauseActive
            let recordedFresh: Bool = {
                guard isRecordedGhost, !paused,
                      let updated = workout.ghostComparisonUpdatedAt else {
                    return false
                }
                return (-5...25).contains(
                    timeline.date.timeIntervalSince(updated)
                )
            }()
            let visibleMeters = isRecordedGhost
                ? (recordedFresh ? workout.ghostDistanceDeltaMeters : nil)
                : (state == .live ? ghost?.distanceDeltaMeters : nil)
            let visibleTime = isRecordedGhost
                ? (recordedFresh ? workout.ghostTimeDeltaSeconds : nil)
                : (state == .live ? ghost?.estimatedTimeDeltaSeconds : nil)

            GeometryReader { viewport in
                let compact = viewport.size.height < 205
                VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                    Label(isRecordedGhost
                          ? "GHOST RACE" : "LIVE GHOST",
                          systemImage: "figure.run.circle")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(WatchTheme.accentDeep)
                    Text(ghost?.opponentName ??
                         workout.ghostRaceTitle ??
                         ATHLTHLocalization.choose(
                            english: "Opponent", norwegian: "Motstander"
                         ))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    if let meters = visibleMeters, meters.isFinite {
                        Text(abs(meters) < 8
                            ? ATHLTHLocalization.choose(
                                english: "SIDE BY SIDE", norwegian: "JEVNT LØP"
                              )
                            : meters > 0
                                ? ATHLTHLocalization.choose(
                                    english: "YOU LEAD", norwegian: "DU LEDER"
                                  )
                                : ATHLTHLocalization.choose(
                                    english: "GHOST LEADS", norwegian: "GHOST LEDER"
                                  ))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(WatchTheme.liveAction)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(abs(meters).rounded()))")
                                .font(.system(size: compact ? 41 : 49,
                                              weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                            Text("m").font(.system(size: 13))
                        }
                        if let time = visibleTime, time.isFinite {
                            Text(ATHLTHLocalization.choose(
                                english: "\(Int(abs(time).rounded())) s difference",
                                norwegian: "\(Int(abs(time).rounded())) sek differanse"
                            ))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WatchTheme.textSecondary)
                        }
                    } else {
                        Label(isRecordedGhost && paused
                              ? ATHLTHLocalization.choose(
                                english: "Workout paused", norwegian: "Økten er pauset"
                              )
                              : message(state),
                              systemImage: paused ? "pause.fill" : "wifi.exclamationmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WatchTheme.warning)
                        .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    if isRecordedGhost {
                        Button {
                            workout.disableGhostDuringWorkout()
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: "Disable Ghost", norwegian: "Slå av Ghost"
                            ), systemImage: "eye.slash")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: compact ? 33 : 41)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, compact ? 2 : 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private func message(_ state: ATHLTHLiveGhostWatchSignal) -> String {
        switch state {
        case .live:
            return ATHLTHLocalization.choose(
                english: "Live", norwegian: "Direkte"
            )
        case .paused:
            return ATHLTHLocalization.choose(
                english: "Duel paused", norwegian: "Duellen er pauset"
            )
        case .delayed:
            return ATHLTHLocalization.choose(
                english: "GPS delayed", norwegian: "GPS er forsinket"
            )
        case .waiting:
            return ATHLTHLocalization.choose(
                english: "Waiting for opponent",
                norwegian: "Venter på motstander"
            )
        }
    }

    private func progress(title: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 9, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(Int(fraction.rounded())) %")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
            }
            ProgressView(value: fraction / 100)
                .tint(WatchTheme.liveAction)
        }
        .padding(10)
        .watchSurface(radius: 14)
    }
}
