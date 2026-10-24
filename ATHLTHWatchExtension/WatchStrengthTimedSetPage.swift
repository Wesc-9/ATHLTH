import SwiftUI

/// ATHLTH time-based exercise surface. Timed running/treadmill segments can
/// live inside a single strength workout; they remain in the same HealthKit
/// session, but get running-specific labels rather than "Complete set".
struct WatchStrengthTimedSetPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func isRunningSegment(_ snapshot: WatchStrengthSessionSnapshot) -> Bool {
        if snapshot.isEmbeddedRunningInterval == true { return true }
        if snapshot.manualTreadmillSpeedKilometersPerHour != nil ||
           snapshot.manualTreadmillInclinePercent != nil {
            return true
        }
        let name = (snapshot.exerciseName ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "nb_NO"))
            .lowercased()
        return ["running", "treadmill", "jogging", "run interval",
                "loping", "lop", "molle", "walking", "power walk"]
            .contains(where: name.contains)
    }

    private func runningPhaseLabel(_ phase: String?) -> String {
        switch phase?.lowercased() {
        case "warmup": return tr("WARM-UP", "OPPVARMING")
        case "main", "work", "effort", "interval": return tr("WORK INTERVAL", "HOVEDDRAG")
        case "recovery", "rest": return tr("RECOVERY", "PAUSE")
        case "cooldown": return tr("COOL-DOWN", "NEDJOGGING")
        default: return tr("RUNNING", "LØPING")
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            if let session = workout.strengthSession {
                let timer = session.timedSetCountdown
                let target = timer?.targetSeconds ??
                    min(max(session.draftDurationSeconds ?? 60, 15), 7_200)
                let remaining = timer?.remaining(at: tick.date) ??
                    TimeInterval(target)
                let started = timer != nil
                let finished = started && remaining <= 0
                let running = timer?.isRunning == true && !finished
                let editable = session.inputMode != .iPhone &&
                    !session.isResting && !session.currentExerciseComplete &&
                    !workout.strengthActionPending
                let isRunning = isRunningSegment(session)

                GeometryReader { geometry in
                    let compact = geometry.size.height < 195
                    VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                        HStack(spacing: 5) {
                            Image(systemName: isRunning
                                ? "figure.run" : "timer")
                                .foregroundStyle(WatchTheme.premiumGold)
                            Text(isRunning
                                 ? runningPhaseLabel(session.embeddedRunningPhaseKind)
                                 : session.isWarmUp == true
                                   ? tr("WARM-UP", "OPPVARMING")
                                   : tr("TIMED EXERCISE", "TIDSØVELSE"))
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(WatchTheme.accentDeep)
                            Spacer(minLength: 2)
                            Text("\(session.setIndex + 1)/\(max(session.setCount, 1))")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(WatchTheme.textSecondary)
                        }

                        Text(session.embeddedRunningPhaseTitle ??
                             session.exerciseName ?? session.title)
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                            .foregroundStyle(WatchTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        HStack(alignment: .center, spacing: 5) {
                            Text(clock(remaining))
                                .font(.system(
                                    size: compact ? 38 : 44,
                                    weight: .bold, design: .rounded
                                ))
                                .monospacedDigit()
                                .foregroundStyle(WatchTheme.accentDeep)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Spacer(minLength: 0)

                            VStack(alignment: .trailing, spacing: 2) {
                                Label(workout.hasFreshHeartRate && workout.heartRate > 0
                                    ? "\(Int(workout.heartRate.rounded()))"
                                    : "—",
                                      systemImage: "heart.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(WatchTheme.liveHeart)
                                Text(session.embeddedRunningTargetHeartRateZone.map {
                                    tr("TARGET Z", "MÅL S") + "\($0)"
                                } ?? "bpm")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(WatchTheme.textSecondary)
                            }
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(finished ? WatchTheme.premiumGold
                                      : running ? WatchTheme.accentDeep
                                      : WatchTheme.muted)
                                .frame(width: 5, height: 5)
                            Text(finished
                                ? tr("READY TO FINISH", "KLAR FOR AVSLUTNING")
                                : running
                                  ? tr("IN PROGRESS", "PÅGÅR")
                                  : started
                                    ? tr("PAUSED", "PAUSET")
                                    : tr("START WHEN READY", "START NÅR DU ER KLAR"))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(WatchTheme.textSecondary)
                            Spacer(minLength: 0)
                            Text(tr("THIS PHASE", "DENNE DELEN"))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(WatchTheme.textSecondary)
                        }

                        ProgressView(
                            value: Double(max(TimeInterval(target) - remaining, 0)),
                            total: Double(max(target, 1))
                        )
                        .tint(WatchTheme.premiumGold)
                        .accessibilityLabel(tr("Phase progress", "Fremdrift i delen"))

                        if isRunning, !compact {
                            if let pace = session.embeddedRunningTargetPaceSecondsPerKilometer,
                               pace.isFinite, (60...3_600).contains(pace) {
                                Text(String(format: tr(
                                    "TARGET PACE %d:%02d min/km",
                                    "MÅLTEMPO %d:%02d min/km"
                                ), Int(pace) / 60, Int(pace) % 60))
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(WatchTheme.textSecondary)
                                    .lineLimit(1)
                            } else if let beltSpeed = session.manualTreadmillSpeedKilometersPerHour,
                                      beltSpeed.isFinite, beltSpeed > 0 {
                                Text(String(format: tr(
                                    "SET SPEED %.1f km/h", "OPPGITT FART %.1f km/t"
                                ), beltSpeed))
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(WatchTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 1)

                        if editable {
                            HStack(spacing: 7) {
                                if !finished {
                                    Button {
                                        if running {
                                            workout.pauseTimedStrengthSet()
                                        } else {
                                            workout.startOrResumeTimedStrengthSet()
                                        }
                                    } label: {
                                        Image(systemName: running ? "pause.fill" : "play.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .frame(width: 38, height: compact ? 32 : 36)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(WatchTheme.accentDeep)
                                    .accessibilityLabel(running
                                        ? tr("Pause phase", "Pause del")
                                        : started
                                          ? tr("Resume phase", "Fortsett del")
                                          : tr("Start phase", "Start del"))
                                }

                                Button {
                                    workout.completeStrengthSet()
                                } label: {
                                    Label(
                                        isRunning
                                          ? tr("Finish running phase", "Avslutt løpedel")
                                          : tr("Complete set", "Fullfør sett"),
                                        systemImage: "checkmark.circle.fill"
                                    )
                                    .font(.system(size: 10, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: compact ? 32 : 36)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(WatchTheme.accentDeep)
                            }
                        } else if session.inputMode == .iPhone {
                            Text(tr("Controlled on iPhone", "Styres på iPhone"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WatchTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, compact ? 3 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .background(WatchTheme.canvas)
                }
            }
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private func clock(_ duration: TimeInterval) -> String {
        let value = max(Int(ceil(duration.isFinite ? duration : 0)), 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
