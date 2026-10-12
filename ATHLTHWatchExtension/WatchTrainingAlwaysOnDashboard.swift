import SwiftUI

/// A single low-power, read-only workout dashboard for Apple Watch.
/// The workout manager continues recording independently of the display.
/// Do not add animations, photos, gradients or crown interaction here.
struct WatchTrainingAlwaysOnDashboard: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    private var strongContrast: Bool {
        ATHLTHWatchDisplayPreferences.prefersStrongContrast(
            workout.liveSurfaceConfiguration
        )
    }

    private var isPrivateAlwaysOn: Bool {
        ATHLTHWatchDisplayPreferences.hidesAlwaysOnDetails(
            workout.liveSurfaceConfiguration
        )
    }

    private var primary: Color {
        Color.white.opacity(strongContrast ? 1 : 0.88)
    }
    private var secondary: Color {
        Color.white.opacity(strongContrast ? 0.93 : 0.64)
    }
    private var quiet: Color {
        Color.white.opacity(strongContrast ? 0.80 : 0.47)
    }
    private let accent = Color(red: 0.48, green: 0.77, blue: 0.78)

    /// Select one information hierarchy for each workout phase.
    /// The lowered-wrist view stays read-only and uses no extra workout timer.
    private var alwaysOnFocus: ATHLTHAlwaysOnFocus {
        ATHLTHAlwaysOnFocusResolver.resolve(
            .init(
                kind: workout.kind,
                hasStrengthSession: workout.strengthSession != nil,
                isStrengthResting: workout.strengthSession?.isResting == true,
                isTimedStrengthSet:
                    workout.strengthSession?.targetKindRaw == "time",
                isStrengthExerciseComplete:
                    workout.strengthSession?.currentExerciseComplete == true,
                currentRunningStepMeasure:
                    workout.currentStructuredRunningStep?.measure,
                recordedDistanceMeters: workout.distanceMeters
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 190 ||
                geometry.size.height < 205

            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                header(compact: compact)

                if isPrivateAlwaysOn {
                    privateWorkoutDashboard(compact: compact)
                } else {
                    switch alwaysOnFocus {
                    case .strengthRest, .strengthTime, .strengthReps,
                         .strengthComplete:
                        strengthDashboard(compact: compact)
                    case .intervalTime, .intervalDistance, .intervalOpen:
                        intervalDashboard(compact: compact)
                    case .paceAndDistance, .distanceAndPace:
                        distanceDashboard(compact: compact)
                    case .cyclingDistance:
                        cyclingDashboard(compact: compact)
                    case .elapsed:
                        genericDashboard(compact: compact)
                    }
                }
            }
            .padding(.horizontal, compact ? 10 : 13)
            .padding(.vertical, compact ? 6 : 9)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundStyle(accent)
            Text("ATHLTH")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(secondary)

            Spacer(minLength: 2)

            if workout.state == .paused ||
                workout.automaticPauseActive {
                Text(ATHLTHLocalization.choose(
                    english: "PAUSED", norwegian: "PAUSE"
                ))
                .foregroundStyle(Color.orange.opacity(0.90))
            } else {
                Text("LIVE")
                    .foregroundStyle(accent)
            }
        }
        .font(.system(size: 9, weight: .bold))
    }

    /// Privacy is opt-in and only affects the lowered-wrist display.
    /// Activity recording continues normally and interactive pages
    /// retain their usual detailed metrics when the user raises the Watch.
    private func privateWorkoutDashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Label(
                workout.kind.title,
                systemImage: workout.kind.systemImage
            )
            .font(.system(size: compact ? 12 : 15, weight: .bold))
            .foregroundStyle(secondary)
            .lineLimit(1)

            Text(timeString(workout.elapsedTime))
                .font(.system(
                    size: compact ? 39 : 46,
                    weight: .bold,
                    design: .rounded
                ))
                .monospacedDigit()
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(ATHLTHLocalization.choose(
                english: "WORKOUT TIME", norwegian: "ØKTTID"
            ))
            .font(.system(size: compact ? 9 : 10, weight: .bold))
            .foregroundStyle(accent)

            Spacer(minLength: 0)

            Label(
                ATHLTHLocalization.choose(
                    english: "Private display", norwegian: "Privat visning"
                ),
                systemImage: "lock.shield"
            )
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }

    private func strengthDashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            if let current = workout.strengthSession {
                Text(current.exerciseName ?? current.title)
                    .font(.system(
                        size: compact ? 13 : 15, weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 9) {
                    if current.isWarmUp == true {
                        Text(ATHLTHLocalization.choose(
                            english: "WARM-UP", norwegian: "OPPVARMING"
                        ))
                    }
                    Text(ATHLTHLocalization.format(
                        english: "EXERCISE %d/%d",
                        norwegian: "ØVELSE %d/%d",
                        max(current.exerciseIndex + 1, 1),
                        max(current.exerciseCount, 1)
                    ))
                    Text(ATHLTHLocalization.format(
                        english: "SET %d/%d",
                        norwegian: "SETT %d/%d",
                        max(current.setIndex + 1, 1),
                        max(current.setCount, 1)
                    ))
                }
                .font(.system(size: compact ? 8 : 9, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                if current.isResting {
                    Text(ATHLTHLocalization.choose(
                        english: "REST BETWEEN SETS",
                        norwegian: "PAUSE MELLOM SETT"
                    ))
                    .font(.system(size: compact ? 10 : 11, weight: .bold))
                    .foregroundStyle(secondary)
                    if let restEndsAt = current.restEndsAt {
                        // AOD is throttled by watchOS; recompute from the
                        // absolute end date instead of counting local ticks.
                        TimelineView(.periodic(from: .now, by: 5)) { timeline in
                            let seconds = restEndsAt.timeIntervalSince(timeline.date)
                            Text(seconds > 0
                                 ? timeString(ceil(seconds))
                                 : ATHLTHLocalization.choose(
                                    english: "READY", norwegian: "KLAR"
                                 ))
                                .font(.system(size: compact ? 30 : 36,
                                              weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(primary)
                        }
                    } else {
                        Text(ATHLTHLocalization.choose(
                            english: "REST", norwegian: "PAUSE"
                        ))
                        .font(.system(size: compact ? 26 : 30,
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(primary)
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Next set when ready",
                        norwegian: "Neste sett når du er klar"
                    ))
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(secondary)
                } else if current.currentExerciseComplete {
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: compact ? 23 : 28))
                            .foregroundStyle(accent)
                        Text(current.allExercisesComplete
                            ? ATHLTHLocalization.choose(
                                english: "WORKOUT COMPLETE",
                                norwegian: "ØKT FULLFØRT"
                              )
                            : ATHLTHLocalization.choose(
                                english: "EXERCISE COMPLETE",
                                norwegian: "ØVELSE FULLFØRT"
                              ))
                            .font(.system(size: compact ? 18 : 22,
                                          weight: .bold, design: .rounded))
                            .foregroundStyle(primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                } else if current.targetKindRaw == "time" {
                    // Same absolute-date timer as the interactive Watch
                    // screen and iPhone; never use a screen-owned counter.
                    TimelineView(.periodic(from: .now, by: 5)) { timeline in
                        let remaining = current.timedSetCountdown?
                            .remaining(at: timeline.date)
                            ?? Double(current.draftDurationSeconds ?? 0)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(timeString(ceil(remaining)))
                                .font(.system(
                                    size: compact ? 38 : 44,
                                    weight: .bold, design: .rounded
                                ))
                                .monospacedDigit()
                                .foregroundStyle(primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Text(current.timedSetCountdown == nil
                                ? ATHLTHLocalization.choose(
                                    english: "TARGET", norwegian: "MÅL"
                                  )
                                : remaining <= 0
                                    ? ATHLTHLocalization.choose(
                                        english: "READY", norwegian: "KLAR"
                                      )
                                    : current.timedSetCountdown?.isRunning == true
                                        ? ATHLTHLocalization.choose(
                                            english: "LEFT", norwegian: "IGJEN"
                                          )
                                        : ATHLTHLocalization.choose(
                                            english: "PAUSED", norwegian: "PAUSE"
                                          ))
                                .font(.system(size: compact ? 10 : 11,
                                              weight: .bold))
                                .foregroundStyle(accent)
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(String(current.draftReps))
                            .font(.system(
                                size: compact ? 43 : 51,
                                weight: .bold,
                                design: .rounded
                            ))
                            .monospacedDigit()
                            .foregroundStyle(primary)
                        Text("REPS")
                            .font(.system(size: compact ? 11 : 12,
                                          weight: .bold))
                            .foregroundStyle(accent)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    if current.loadKindRaw == "resistanceLevel" {
                        Text(ATHLTHLocalization.format(
                            english: "Level %d", norwegian: "Nivå %d",
                            current.draftResistanceLevel ?? 5
                        ))
                    } else {
                        Text(String(format: "%.1f kg",
                                    current.draftWeightKilograms))
                    }
                    Spacer(minLength: 2)
                    Text(ATHLTHLocalization.format(
                        english: "%d/%d sets",
                        norwegian: "%d/%d sett",
                        current.completedSets,
                        max(current.totalSets, 1)
                    ))
                }
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(secondary)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "STRENGTH", norwegian: "STYRKE"
                ))
                .font(.system(size: compact ? 26 : 30,
                              weight: .bold, design: .rounded))
                .foregroundStyle(primary)
                Spacer(minLength: 0)
            }

            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }

    private func distanceDashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            Text(currentWorkoutTitle)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(secondary)
                .lineLimit(1)

            if alwaysOnFocus == .distanceAndPace {
                distanceMetric(fontSize: compact ? 37 : 44)
                Text(ATHLTHLocalization.choose(
                    english: "DISTANCE", norwegian: "DISTANSE"
                ))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)

                paceMetric(fontSize: compact ? 25 : 30)
            } else {
                paceMetric(fontSize: compact ? 35 : 43)
                Text("PACE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(accent)
                distanceMetric(fontSize: compact ? 30 : 37)
            }

            Spacer(minLength: 0)
            if workout.kind == .running,
               workout.liveSurfaceContext.liveGhost != nil {
                alwaysOnGhostStatus
            }
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }

    /// Only the current step matters when wrist-down. Keep the main
    /// countdown or distance dominant; do not show a cached Ghost lead in
    /// place of the current training instruction.
    private func intervalDashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if let step = workout.currentStructuredRunningStep {
                Text(step.title)
                    .font(.system(size: compact ? 11 : 13,
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "INTERVAL", norwegian: "INTERVALL"
                    ))
                    if let structured = workout.structuredRunningWorkout {
                        Text(
                            "\(min(workout.structuredStepIndex + 1, structured.steps.count))/\(structured.steps.count)"
                        )
                        .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                .font(.system(size: compact ? 8 : 9, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(1)

                let readout = ATHLTHRunIntervalReadout.resolve(
                    step: step,
                    elapsedSeconds: workout.currentStructuredStepElapsedTime,
                    distanceMeters: workout.currentStructuredStepDistanceMeters
                )

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(intervalValue(readout))
                        .font(.system(size: compact ? 37 : 44,
                                      weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    if readout.unit == .meters,
                       let meters = readout.remaining {
                        Text(meters >= 1_000 ? "km" : "m")
                            .font(.system(size: compact ? 11 : 12,
                                          weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    Spacer(minLength: 0)
                }

                Text(intervalCaption(readout))
                    .font(.system(size: compact ? 8 : 9,
                                  weight: .semibold))
                    .foregroundStyle(secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(paceString + "/km")
                    Spacer(minLength: 0)
                    Text(String(format: "%.2f km",
                                max(workout.distanceMeters, 0) / 1_000))
                }
                .font(.system(size: compact ? 11 : 12,
                              weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }

    private func intervalValue(_ readout: ATHLTHRunIntervalReadout)
        -> String {
        guard let remaining = readout.remaining else { return "—" }
        switch readout.unit {
        case .seconds:
            return timeString(ceil(remaining))
        case .meters:
            return remaining >= 1_000
                ? String(format: "%.2f", remaining / 1_000)
                : String(Int(remaining.rounded(.up)))
        case .open:
            return "—"
        }
    }

    private func intervalCaption(_ readout: ATHLTHRunIntervalReadout)
        -> String {
        switch readout.unit {
        case .seconds:
            return ATHLTHLocalization.choose(
                english: "TIME LEFT", norwegian: "TID IGJEN"
            )
        case .meters:
            return ATHLTHLocalization.choose(
                english: "DISTANCE LEFT", norwegian: "DISTANSE IGJEN"
            )
        case .open:
            return ATHLTHLocalization.choose(
                english: "OPEN INTERVAL", norwegian: "ÅPENT INTERVALL"
            )
        }
    }

    // Keep pace, distance, heart rate and time as the main AOD metrics.
    // Only a tiny low-power race indicator is added; never display a stale
    // advantage as live when WatchConnectivity stops delivering updates.
    private var alwaysOnGhostStatus: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let ghost = workout.liveSurfaceContext.liveGhost
            let signal = ATHLTHLiveGhostWatchSignal.resolve(
                context: ghost,
                isPaused: workout.state == .paused ||
                    workout.automaticPauseActive,
                now: timeline.date
            )
            HStack(spacing: 5) {
                Image(systemName: signal == .live
                      ? "figure.run" : "wifi.exclamationmark")
                .font(.system(size: 9, weight: .semibold))

                if signal == .live,
                   let delta = ghost?.distanceDeltaMeters,
                   delta.isFinite {
                    Text(abs(delta) < 8
                        ? ATHLTHLocalization.choose(
                            english: "SIDE BY SIDE", norwegian: "JEVNT LØP"
                        )
                        : (delta > 0
                            ? ATHLTHLocalization.choose(
                                english: "YOU LEAD", norwegian: "DU LEDER"
                              )
                            : ATHLTHLocalization.choose(
                                english: "RIVAL LEADS", norwegian: "MOTSTANDER LEDER"
                              )))
                    Text("\(Int(abs(delta).rounded())) m")
                        .monospacedDigit()
                } else {
                    Text(signal == .paused
                        ? ATHLTHLocalization.choose(
                            english: "GHOST PAUSED", norwegian: "GHOST PAUSE"
                          )
                        : ATHLTHLocalization.choose(
                            english: "GHOST SIGNAL DELAYED", norwegian: "GHOST FORSINKET"
                          ))
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(signal == .live ? accent : secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }
    }

    private func distanceMetric(fontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(String(format: "%.2f", max(workout.distanceMeters, 0) / 1000))
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("km")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            Spacer(minLength: 0)
        }
    }

    private func paceMetric(fontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(paceString)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("/km")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondary)
            Spacer(minLength: 0)
        }
    }

    private func cyclingDashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            Label(workout.kind.title, systemImage: workout.kind.systemImage)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f",
                    max(workout.distanceMeters, 0) / 1_000))
                    .font(.system(
                        size: compact ? 38 : 45,
                        weight: .bold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("km")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(ATHLTHLocalization.choose(
                english: "RECORDED DISTANCE", norwegian: "MÅLT DISTANSE"
            ))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)

            Text(timeString(workout.elapsedTime))
                .font(.system(size: compact ? 20 : 24,
                              weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(secondary)

            Spacer(minLength: 0)
            genericFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }

    private func genericDashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout.kind.title)
                .font(.system(size: compact ? 14 : 16,
                              weight: .semibold, design: .rounded))
                .foregroundStyle(secondary)
            Text(timeString(workout.elapsedTime))
                .font(.system(size: compact ? 38 : 45,
                              weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primary)
                .minimumScaleFactor(0.7)
            Text(ATHLTHLocalization.choose(
                english: "ELAPSED TIME", norwegian: "MEDGÅTT TID"
            ))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)
            Spacer(minLength: 0)
            genericFooter()
        }
    }

    private func genericFooter() -> some View {
        HStack(spacing: 6) {
            Label(workout.hasFreshHeartRate
                  ? String(Int(workout.heartRate.rounded()))
                  : "—", systemImage: "heart.fill")
            Spacer(minLength: 0)
            if workout.activeCalories > 0 {
                Label(String(Int(workout.activeCalories.rounded())),
                      systemImage: "flame")
            }
        }
        .font(.system(size: 11, weight: .semibold,
                      design: .rounded))
        .monospacedDigit()
        .foregroundStyle(quiet)
    }

    private func footer() -> some View {
        HStack(spacing: 6) {
            Label(timeString(workout.elapsedTime), systemImage: "clock")
            Spacer(minLength: 0)
            Label(workout.hasFreshHeartRate
                  ? String(Int(workout.heartRate.rounded()))
                  : "—", systemImage: "heart.fill")

            if workout.hasFreshHeartRate,
               workout.targetAlertConfiguration?.heartRateEnabled == true,
               let zone = workout.targetAlertConfiguration?.heartRateZone {
                Text("S\(zone)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .font(.system(size: 11, weight: .semibold,
                      design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(quiet)
    }

    private var currentWorkoutTitle: String {
        if let step = workout.currentStructuredRunningStep {
            return step.title
        }
        if let title = workout.structuredRunningWorkout?.title,
           !title.isEmpty {
            return title
        }
        return workout.kind == .walking
            ? ATHLTHLocalization.choose(
                english: "Walking", norwegian: "Gåtur"
            )
            : ATHLTHLocalization.choose(
                english: "Running", norwegian: "Løping"
            )
    }

    private var paceString: String {
        guard let pace = workout.currentPaceSecondsPerKilometer,
              pace.isFinite, pace > 0 else { return "—:—" }
        let seconds = max(0, Int(pace.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
