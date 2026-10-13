import SwiftUI

/// Dedicated interval page. Uses the same step clock and distance already
/// advanced by the Watch workout engine, so no second timer can drift.
struct WatchRunIntervalFocusPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 42

    private var spokenNorwegian: Bool {
        ATHLTHLocalization.choose(english: "en", norwegian: "no") == "no"
    }

    var body: some View {
        ScrollView {
            if let step = workout.currentStructuredRunningStep {
                let readout = ATHLTHRunIntervalReadout.resolve(
                    step: step,
                    elapsedSeconds: workout.currentStructuredStepElapsedTime,
                    distanceMeters: workout.currentStructuredStepDistanceMeters
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .foregroundStyle(WatchTheme.liveLime)
                        Text(ATHLTHLocalization.choose(
                            english: "CURRENT INTERVAL",
                            norwegian: "AKTUELT INTERVALL"
                        ))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        Spacer(minLength: 0)
                        if let structured = workout.structuredRunningWorkout {
                            Text("\(workout.structuredStepIndex + 1)/\(structured.steps.count)")
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(WatchTheme.textPrimary)

                    Text(step.title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(metricTitle(readout))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WatchTheme.textSecondary)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(metricValue(readout))
                                .font(.system(size: countdownSize, weight: .bold,
                                              design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            if readout.unit == .meters,
                               let remaining = readout.remaining,
                               remaining >= 1_000 {
                                Text("km")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WatchTheme.accentDeep)
                            } else if readout.unit == .meters {
                                Text("m")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WatchTheme.accentDeep)
                            }
                        }

                        if let progress = readout.progress {
                            ProgressView(value: progress)
                                .tint(WatchTheme.liveAction)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .watchSurface(radius: 17)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(metricTitle(readout))
                    .accessibilityValue(accessibleRemaining(readout))

                    if let pace = targetPace(step) {
                        HStack(spacing: 6) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "PACE TARGET", norwegian: "TEMPO MÅL"
                                ),
                                systemImage: "speedometer"
                            )
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WatchTheme.textSecondary)
                            Spacer(minLength: 0)
                            Text(pace)
                                .font(.system(size: 12, weight: .bold,
                                              design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(10)
                        .watchSurface(radius: 15)
                    }

                    HStack(spacing: 8) {
                        metric(
                            title: ATHLTHLocalization.choose(
                                english: "STEP TIME", norwegian: "TID"
                            ),
                            value: clock(workout.currentStructuredStepElapsedTime)
                        )
                        metric(
                            title: ATHLTHLocalization.choose(
                                english: "STEP DIST", norwegian: "DISTANSE"
                            ),
                            value: String(
                                format: "%.2f km",
                                max(workout.currentStructuredStepDistanceMeters, 0) / 1_000
                            )
                        )
                    }

                    if let next = workout.nextStructuredRunningStep {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: "UP NEXT", norwegian: "NESTE"
                            ))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WatchTheme.accentDeep)
                            Text(next.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .watchSurface(radius: 15)
                    }

                    if workout.state == .paused || workout.automaticPauseActive {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Workout paused", norwegian: "Økten er pauset"
                            ),
                            systemImage: "pause.fill"
                        )
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.warning)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.top, 5)
                .padding(.bottom, 12)
            }
        }
        .scrollIndicators(.hidden)
        .background(WatchTheme.canvas.ignoresSafeArea())
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let ghost = workout.liveSurfaceContext.liveGhost
            let state = ATHLTHLiveGhostWatchSignal.resolve(
                context: ghost,
                isPaused: workout.state == .paused ||
                    workout.automaticPauseActive,
                now: timeline.date
            )
            // Replay/Target Ghost are computed locally on Watch, while a
            // Live Ghost uses a fresh synchronized opponent sample.
            let isRecordedGhost = ghost == nil && workout.ghostRaceTitle != nil
            let paused = workout.state == .paused || workout.automaticPauseActive
            let recordedFresh: Bool = {
                guard isRecordedGhost, !paused,
                      let updated = workout.ghostComparisonUpdatedAt else {
                    return false
                }
                return (-5...25).contains(timeline.date.timeIntervalSince(updated))
            }()
            let visibleMeters = isRecordedGhost
                ? (recordedFresh ? workout.ghostDistanceDeltaMeters : nil)
                : (state == .live ? ghost?.distanceDeltaMeters : nil)
            let visibleTime = isRecordedGhost
                ? (recordedFresh ? workout.ghostTimeDeltaSeconds : nil)
                : (state == .live ? ghost?.estimatedTimeDeltaSeconds : nil)

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    Label(
                        isRecordedGhost
                            ? "GHOST RACE"
                            : "LIVE GHOST",
                        systemImage: "figure.run.circle"
                    )
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(WatchTheme.accentDeep)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(ghost?.opponentName ??
                             workout.ghostRaceTitle ??
                             ATHLTHLocalization.choose(
                                english: "Opponent", norwegian: "Motstander"
                             ))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)

                        if let meters = visibleMeters,
                           meters.isFinite {
                            Text(abs(meters) < 8
                                ? ATHLTHLocalization.choose(
                                    english: "SIDE BY SIDE", norwegian: "JEVNT LØP"
                                  )
                                : meters > 0
                                    ? ATHLTHLocalization.choose(
                                        english: "YOU LEAD", norwegian: "DU LEDER"
                                      )
                                    : isRecordedGhost
                                        ? ATHLTHLocalization.choose(
                                            english: "GHOST LEADS",
                                            norwegian: "GHOST LEDER"
                                          )
                                        : ATHLTHLocalization.choose(
                                            english: "OPPONENT LEADS",
                                            norwegian: "MOTSTANDER LEDER"
                                          ))
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(WatchTheme.liveAction)

                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(Int(abs(meters).rounded()))")
                                    .font(.system(size: leadSize, weight: .bold,
                                                  design: .rounded))
                                    .monospacedDigit()
                                Text("m")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WatchTheme.textSecondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Live Ghost gap",
                                norwegian: "Avstand til motstander"
                            ))
                            .accessibilityValue(
                                ATHLTHWorkoutAccessibleMetric.distance(
                                    abs(meters),
                                    norwegian: ATHLTHLocalization.choose(
                                        english: "en", norwegian: "no"
                                    ) == "no"
                                )
                            )

                            if let time = visibleTime,
                               time.isFinite {
                                Text(ATHLTHLocalization.choose(
                                    english: "Estimated gap: \(Int(abs(time).rounded())) s",
                                    norwegian: "Estimert differanse: \(Int(abs(time).rounded())) s"
                                ))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WatchTheme.textSecondary)
                            }
                        } else {
                            Label(
                                isRecordedGhost
                                    ? (paused
                                        ? ATHLTHLocalization.choose(
                                            english: "Workout paused", norwegian: "Økten er pauset"
                                          )
                                        : ATHLTHLocalization.choose(
                                            english: "Waiting for fresh GPS", norwegian: "Venter på fersk GPS"
                                          ))
                                    : message(state),
                                systemImage: paused ? "pause.fill" : "wifi.exclamationmark"
                            )
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WatchTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)

                            Text(ATHLTHLocalization.choose(
                                english: "Previous lead is hidden until GPS is trustworthy.",
                                norwegian: "Tidligere forsprang skjules til GPS er pålitelig."
                            ))
                            .font(.system(size: 10))
                            .foregroundStyle(WatchTheme.textSecondary)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .watchSurface(radius: 17)

                    if let own = ghost?.ownProgressPercent,
                       own.isFinite, (0...100).contains(own),
                       let other = ghost?.opponentProgressPercent,
                       other.isFinite, (0...100).contains(other),
                       state == .live {
                        progress(
                            title: ATHLTHLocalization.choose(
                                english: "YOU", norwegian: "DEG"
                            ),
                            fraction: own
                        )
                        progress(
                            title: ATHLTHLocalization.choose(
                                english: "OPPONENT", norwegian: "MOTSTANDER"
                            ),
                            fraction: other
                        )
                    }
                }
                .padding(.horizontal, 9)
                .padding(.top, 6)
                .padding(.bottom, 15)
            }
            .scrollIndicators(.hidden)
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
