import SwiftUI

/// Active time-based strength set, displayed as its own first Watch page.
/// The timer is anchored to a date from the shared strength session, so the
/// UI may reduce its refresh frequency without changing the recorded result.
struct WatchStrengthTimedSetPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let set = workout.strengthSession {
                let countdown = set.timedSetCountdown
                let target = countdown?.targetSeconds ??
                    min(max(set.draftDurationSeconds ?? 60, 15), 7_200)
                let remaining = countdown?.remaining(at: context.date) ??
                    TimeInterval(target)
                let finished = countdown != nil && remaining <= 0
                let started = countdown != nil
                let running = countdown?.isRunning == true && !finished
                let canEdit = set.inputMode != .iPhone &&
                    !set.isResting &&
                    !set.currentExerciseComplete &&
                    !workout.strengthActionPending

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .foregroundStyle(WatchTheme.liveAction)
                        Text(set.isWarmUp == true
                            ? ATHLTHLocalization.choose(
                                english: "WARM-UP", norwegian: "OPPVARMING")
                            : ATHLTHLocalization.choose(
                                english: "TIMED SET", norwegian: "TIDSSETT"))
                        .foregroundStyle(WatchTheme.accentDeep)
                        Spacer(minLength: 0)
                        Text("\(set.setIndex + 1)/\(max(set.setCount, 1))")
                            .foregroundStyle(WatchTheme.muted)
                    }
                    .font(.system(size: 9, weight: .bold))

                    Text(set.exerciseName ?? set.title)
                        .font(.system(size: 13, weight: .semibold,
                                      design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(clock(remaining))
                            .font(.system(size: 43, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 0)
                        if workout.heartRate > 0 {
                            Label(
                                "\(Int(workout.heartRate.rounded()))",
                                systemImage: "heart.fill"
                            )
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WatchTheme.liveHeart)
                        }
                    }

                    Text(finished
                        ? ATHLTHLocalization.choose(
                            english: "READY TO COMPLETE",
                            norwegian: "KLAR FOR FULLFØRING")
                        : running
                            ? ATHLTHLocalization.choose(
                                english: "COUNTING DOWN",
                                norwegian: "NEDTELLING PÅGÅR")
                            : started
                                ? ATHLTHLocalization.choose(
                                    english: "COUNTDOWN PAUSED",
                                    norwegian: "NEDTELLING PAUSET")
                                : ATHLTHLocalization.choose(
                                    english: "START WHEN READY",
                                    norwegian: "START NÅR DU ER KLAR"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.muted)

                    ProgressView(
                        value: Double(max(TimeInterval(target) - remaining, 0)),
                        total: Double(max(target, 1))
                    )
                    .tint(WatchTheme.liveAction)

                    if canEdit {
                        HStack(spacing: 6) {
                            if !finished {
                                Button {
                                    if running {
                                        workout.pauseTimedStrengthSet()
                                    } else {
                                        workout.startOrResumeTimedStrengthSet()
                                    }
                                } label: {
                                    Label(
                                        running
                                            ? ATHLTHLocalization.choose(
                                                english: "Pause",
                                                norwegian: "Pause")
                                            : started
                                                ? ATHLTHLocalization.choose(
                                                    english: "Resume",
                                                    norwegian: "Fortsett")
                                                : ATHLTHLocalization.choose(
                                                    english: "Start",
                                                    norwegian: "Start"),
                                        systemImage:
                                            running ? "pause.fill" : "play.fill"
                                    )
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 32)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(WatchTheme.liveAction)
                            }
                            if started {
                                Button {
                                    workout.resetTimedStrengthSet()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .frame(width: 34, height: 32)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(
                                    ATHLTHLocalization.choose(
                                        english: "Reset countdown",
                                        norwegian: "Nullstill nedtelling"
                                    )
                                )
                            }
                        }

                        Button {
                            workout.completeStrengthSet()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Complete set",
                                    norwegian: "Fullfør sett"
                                ),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchTheme.liveAction)
                    } else if set.inputMode == .iPhone {
                        Text(ATHLTHLocalization.choose(
                            english: "Controlled on iPhone",
                            norwegian: "Styres på iPhone"
                        ))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WatchTheme.muted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
                .background(WatchTheme.canvas)
            }
        }
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private func clock(_ duration: TimeInterval) -> String {
        let seconds = max(Int(ceil(duration.isFinite ? duration : 0)), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
