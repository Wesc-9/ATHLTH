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
                            .foregroundStyle(WatchTheme.accentDeep)
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

                    if workout.awaitingMainStart {
                        Label(ATHLTHLocalization.choose(
                            english: "READY FOR MAIN SECTION",
                            norwegian: "KLAR FOR HOVEDDEL"
                        ), systemImage: "figure.run.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WatchTheme.accentDeep)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .watchSurface(radius: 17)
                    } else {
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
                            Text(ATHLTHLocalization.choose(
                                english: "THIS PHASE", norwegian: "DENNE DELEN"
                            ))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WatchTheme.textSecondary)
                            ProgressView(value: progress)
                                .tint(WatchTheme.liveAction)
                            if let structured = workout.structuredRunningWorkout {
                                Text(ATHLTHLocalization.choose(
                                    english: "TOTAL WORKOUT", norwegian: "HELE ØKTEN"
                                ))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(WatchTheme.textSecondary)
                                .padding(.top, 3)
                                ProgressView(value: overallProgress(
                                    steps: structured.steps,
                                    index: workout.structuredStepIndex,
                                    current: progress
                                ))
                                .tint(WatchTheme.accentDeep)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .watchSurface(radius: 17)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(metricTitle(readout))
                    .accessibilityValue(accessibleRemaining(readout))
                    }

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

                    // A single, high-contrast pulse surface: current pulse
                    // is measured; coloured segments indicate target zone only.
                    HStack(spacing: 8) {
                        heartRateCard(targetZone: step.targetHeartRateZone)
                        metric(
                            title: ATHLTHLocalization.choose(
                                english: "CURRENT PACE", norwegian: "TEMPO NÅ"
                            ),
                            value: workout.currentPaceSecondsPerKilometer.map {
                                "\(clock($0))/km"
                            } ?? "—"
                        )
                    }

                    if let incline = step.targetTreadmillInclinePercent,
                       incline.isFinite, (0...15).contains(incline) {
                        HStack {
                            Label(ATHLTHLocalization.choose(
                                english: "PLANNED INCLINE", norwegian: "PLANLAGT STIGNING"
                            ), systemImage: "mountain.2")
                                .font(.system(size: 9, weight: .semibold))
                            Spacer()
                            Text(String(format: "%.1f %%", incline))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(10)
                        .watchSurface(radius: 15)
                    }

                    if let lead = ATHLTHIntervalGhostPacer.leadMeters(
                        step: step,
                        elapsedSeconds: workout.currentStructuredStepElapsedTime,
                        distanceMeters: workout.currentStructuredStepDistanceMeters
                    ) {
                        HStack {
                            Image(systemName: "figure.run.circle")
                            Text(ATHLTHLocalization.choose(
                                english: "WORK-ONLY GHOST", norwegian: "GHOST · KUN DRAG"
                            ))
                            Spacer()
                            Text("\(Int(abs(lead).rounded())) m " + ATHLTHLocalization.choose(
                                english: lead >= 0 ? "ahead" : "behind",
                                norwegian: lead >= 0 ? "foran" : "bak"
                            ))
                            .monospacedDigit()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WatchTheme.accentDeep)
                        .padding(9)
                        .watchSurface(radius: 14)
                    }

                    if step.phase == "recovery",
                       step.ghostFollowsRecovery == true {
                        let following = ATHLTHIntervalGhostPacer.followsRecovery(
                            step: step,
                            observedPaceSecondsPerKilometer:
                                workout.currentPaceSecondsPerKilometer
                        )
                        HStack(spacing: 7) {
                            Image(systemName: "figure.run.circle")
                            Text(ATHLTHLocalization.choose(
                                english: following ? "Ghost matches your recovery"
                                                   : "Ghost is waiting for slower pace",
                                norwegian: following ? "Ghost følger pausetempoet"
                                                     : "Ghost venter på roligere tempo"
                            ))
                            .lineLimit(2)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .padding(9)
                        .watchSurface(radius: 14)
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

                    if let workoutPlan = workout.structuredRunningWorkout,
                       (workout.awaitingMainStart ||
                        (step.phase == "warmup" &&
                         workoutPlan.autoStartMainAfterWarmup != true) ||
                        step.phase == "cooldown" ||
                        step.measure == .open ||
                        workoutPlan.autoAdvanceTimedSteps == false),
                       workout.state == .running {
                        Button {
                            workout.advanceStructuredRunningWorkoutManually()
                        } label: {
                            Label(ATHLTHLocalization.choose(
                                english: (workout.awaitingMainStart ||
                                    (step.phase == "warmup" &&
                                     workoutPlan.deferRouteUntilMain == true))
                                    ? "Start main section" : step.phase == "warmup"
                                    ? "End warm-up" : step.phase == "cooldown"
                                    ? "End cool-down" : "Next phase",
                                norwegian: (workout.awaitingMainStart ||
                                    (step.phase == "warmup" &&
                                     workoutPlan.deferRouteUntilMain == true))
                                    ? "Start hoveddel" : step.phase == "warmup"
                                    ? "Avslutt oppvarming" : step.phase == "cooldown"
                                    ? "Avslutt nedjogging" : "Neste del"
                            ), systemImage: "arrow.right.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.liveAction)
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
                        if isRecordedGhost && workout.ghostIsOffPlannedRoute {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Off course – Ghost keeps following the route",
                                    norwegian: "Utenfor ruten – Ghost fortsetter langs løypen"
                                ),
                                systemImage: "location.slash"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WatchTheme.warning)
                        }
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

                            if isRecordedGhost,
                               let percent = workout.ghostRouteGapPercent,
                               percent.isFinite, abs(percent) >= 1 {
                                Text(ATHLTHLocalization.choose(
                                    english: percent >= 0
                                        ? String(format: "%.0f%% ahead on route", percent)
                                        : String(format: "%.0f%% behind on route", abs(percent)),
                                    norwegian: percent >= 0
                                        ? String(format: "%.0f %% foran på ruten", percent)
                                        : String(format: "%.0f %% bak på ruten", abs(percent))
                                ))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WatchTheme.textSecondary)
                            }

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

                    if isRecordedGhost {
                        Button {
                            workout.disableGhostDuringWorkout()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Turn off Ghost",
                                    norwegian: "Slå av Ghost"
                                ),
                                systemImage: "eye.slash"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint(ATHLTHLocalization.choose(
                            english: "Continue recording without Ghost comparison",
                            norwegian: "Fortsett å registrere økten uten Ghost"
                        ))
                    }

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
