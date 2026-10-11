import SwiftUI

/// Lightweight, read-only pages around the existing strength set editor.
/// WatchWorkoutManager remains the sole owner of the workout and commands.
struct WatchStrengthSessionStatusPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                WatchStrengthPageHeading(
                    title: ATHLTHLocalization.choose(
                        english: "WORKOUT STATUS",
                        norwegian: "ØKTSTATUS"
                    ),
                    symbol: "chart.bar.fill"
                )

                if let snapshot = workout.strengthSession {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(snapshot.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(snapshot.completedSets)")
                                .font(.system(size: 36, weight: .bold,
                                              design: .rounded))
                                .monospacedDigit()
                            Text("/ \(max(snapshot.totalSets, 1))")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(WatchTheme.muted)
                        }

                        Text(ATHLTHLocalization.choose(
                            english: "SETS COMPLETED",
                            norwegian: "SETT FULLFØRT"
                        ))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(WatchTheme.accentDeep)

                        ProgressView(
                            value: Double(min(snapshot.completedSets,
                                              max(snapshot.totalSets, 1))),
                            total: Double(max(snapshot.totalSets, 1))
                        )
                        .tint(WatchTheme.liveAction)
                    }
                    .padding(11)
                    .watchSurface(radius: 18)

                    HStack(spacing: 7) {
                        WatchStrengthReadout(
                            title: ATHLTHLocalization.choose(
                                english: "TIME", norwegian: "TID"
                            ),
                            value: duration(workout.elapsedTime),
                            symbol: "clock.fill"
                        )
                        WatchStrengthReadout(
                            title: ATHLTHLocalization.choose(
                                english: "EXERCISES", norwegian: "ØVELSER"
                            ),
                            value: "\(min(snapshot.exerciseIndex + 1,
                                           snapshot.exerciseCount))/\(snapshot.exerciseCount)",
                            symbol: "dumbbell.fill"
                        )
                    }

                    if let name = snapshot.exerciseName {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: "CURRENT EXERCISE",
                                norwegian: "NÅVÆRENDE ØVELSE"
                            ))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(WatchTheme.muted)
                            Text(name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(2)
                            Text(ATHLTHLocalization.choose(
                                english: "Set \(min(snapshot.setIndex + 1, snapshot.setCount)) of \(snapshot.setCount)",
                                norwegian: "Sett \(min(snapshot.setIndex + 1, snapshot.setCount)) av \(snapshot.setCount)"
                            ))
                            .font(.system(size: 10))
                            .foregroundStyle(WatchTheme.muted)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .watchSurface(radius: 16)
                    }
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "Preparing workout details",
                        norwegian: "Klargjør øktdetaljer"
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(WatchTheme.muted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        let hours = seconds / 3_600
        if hours > 0 {
            return String(format: "%d:%02d", hours, (seconds % 3_600) / 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct WatchStrengthExerciseQueuePage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchStrengthPageHeading(
                    title: ATHLTHLocalization.choose(
                        english: "EXERCISE QUEUE",
                        norwegian: "ØVELSESOVERSIKT"
                    ),
                    symbol: "list.bullet"
                )

                if let snapshot = workout.strengthSession,
                   let queue = snapshot.exerciseQueue,
                   !queue.isEmpty {
                    ForEach(queue.sorted(by: { $0.index < $1.index }),
                            id: \.index) { exercise in
                        queueRow(exercise, currentIndex: snapshot.exerciseIndex)
                    }
                } else if let snapshot = workout.strengthSession,
                          let name = snapshot.exerciseName {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(.system(size: 14, weight: .bold))
                        Text(ATHLTHLocalization.choose(
                            english: "Exercise \(snapshot.exerciseIndex + 1) of \(snapshot.exerciseCount)",
                            norwegian: "Øvelse \(snapshot.exerciseIndex + 1) av \(snapshot.exerciseCount)"
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.muted)
                        Text(ATHLTHLocalization.choose(
                            english: "The full queue will appear after synchronization.",
                            norwegian: "Hele oversikten vises når den er synkronisert."
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.muted)
                    }
                    .padding(11)
                    .watchSurface()
                } else {
                    Text(ATHLTHLocalization.choose(
                        english: "No exercises available yet.",
                        norwegian: "Ingen øvelser tilgjengelig ennå."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(WatchTheme.muted)
                    .padding(11)
                    .watchSurface()
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func queueRow(
        _ exercise: WatchStrengthExerciseSummary,
        currentIndex: Int
    ) -> some View {
        let isCurrent = exercise.index == currentIndex
        let isComplete = exercise.isCompleted == true
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName:
                    isComplete ? "checkmark.circle.fill" :
                    isCurrent ? "circle.inset.filled" : "circle"
                )
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isCurrent || isComplete
                    ? WatchTheme.liveAction : WatchTheme.muted)

                Text("\(exercise.index + 1). \(exercise.name)")
                    .font(.system(size: 12, weight: isCurrent ? .bold : .semibold))
                    .lineLimit(2)

                Spacer(minLength: 1)

                Text("\(exercise.setCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchTheme.muted)
            }

            if let nextIndex = exercise.firstPendingSetIndex,
               let plan = exercise.setPlans?.first(where: {
                   $0.setNumber == nextIndex + 1
               }) {
                HStack(spacing: 5) {
                    if plan.isWarmUp == true {
                        Text(ATHLTHLocalization.choose(
                            english: "WARM-UP", norwegian: "OPPVARMING"
                        ))
                    }
                    if let reps = plan.reps {
                        Text("\(reps) reps")
                    } else if let seconds = plan.durationSeconds {
                        Text("\(seconds) s")
                    }
                    if let weight = plan.weightKilograms {
                        Text(String(format: "· %.1f kg", weight))
                    } else if let level = plan.resistanceLevel {
                        Text(ATHLTHLocalization.choose(
                            english: "· Level \(level)",
                            norwegian: "· Nivå \(level)"
                        ))
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WatchTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }

            if isCurrent {
                Text(ATHLTHLocalization.choose(
                    english: "CURRENT", norwegian: "AKTIV"
                ))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WatchTheme.liveAction)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 16)
    }
}

struct WatchStrengthPulsePage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchStrengthPageHeading(
                    title: ATHLTHLocalization.choose(
                        english: "HEART RATE",
                        norwegian: "PULS"
                    ),
                    symbol: "heart.fill"
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(workout.heartRate > 0
                            ? "\(Int(workout.heartRate.rounded()))" : "—")
                            .font(.system(size: 52, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.65)
                        Text("bpm")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WatchTheme.muted)
                    }
                    Text(workout.heartRate > 0
                        ? ATHLTHLocalization.choose(
                            english: "CURRENT", norwegian: "NÅVÆRENDE"
                          )
                        : ATHLTHLocalization.choose(
                            english: "WAITING FOR HEART RATE",
                            norwegian: "VENTER PÅ PULS"
                          ))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WatchTheme.liveAction)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .watchSurface(radius: 18)

                HStack(spacing: 7) {
                    WatchStrengthReadout(
                        title: ATHLTHLocalization.choose(
                            english: "AVERAGE", norwegian: "SNITT"
                        ),
                        value: bpm(workout.averageHeartRate),
                        symbol: "heart.text.square"
                    )
                    WatchStrengthReadout(
                        title: ATHLTHLocalization.choose(
                            english: "MAX", norwegian: "MAKS"
                        ),
                        value: bpm(workout.maxHeartRate),
                        symbol: "heart.circle"
                    )
                }

                if let target = workout.targetAlertConfiguration,
                   target.heartRateEnabled {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "TARGET ZONE",
                            norwegian: "MÅLSONE"
                        ))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.accentDeep)

                        if let low = target.heartRateMinimumBPM,
                           let high = target.heartRateMaximumBPM {
                            Text("\(Int(low.rounded()))–\(Int(high.rounded())) bpm")
                                .font(.system(size: 15, weight: .bold,
                                              design: .rounded))
                                .monospacedDigit()
                        }

                        if let status = workout.liveTargetStatus {
                            Text(status)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WatchTheme.muted)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .watchSurface()
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func bpm(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "—" }
        return "\(Int(value.rounded()))"
    }
}

/// iPhone-only input mode must never show an action the Watch cannot commit.
struct WatchStrengthReadOnlySetPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = workout.strengthSession {
                WatchStrengthPageHeading(
                    title: snapshot.isWarmUp == true
                        ? ATHLTHLocalization.choose(
                            english: "WARM-UP", norwegian: "OPPVARMING"
                          )
                        : ATHLTHLocalization.choose(
                            english: "CURRENT SET", norwegian: "AKTIVT SETT"
                          ),
                    symbol: "dumbbell.fill"
                )

                Text(snapshot.exerciseName ?? snapshot.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(2)

                Text(ATHLTHLocalization.choose(
                    english: "Set \(snapshot.setIndex + 1) / \(snapshot.setCount)",
                    norwegian: "Sett \(snapshot.setIndex + 1) / \(snapshot.setCount)"
                ))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WatchTheme.muted)

                HStack(spacing: 7) {
                    WatchStrengthReadout(
                        title: snapshot.targetKindRaw == "time"
                            ? ATHLTHLocalization.choose(
                                english: "TARGET", norwegian: "MÅL"
                              )
                            : "REPS",
                        value: snapshot.targetKindRaw == "time"
                            ? "\(snapshot.draftDurationSeconds ?? 0) s"
                            : "\(snapshot.draftReps)",
                        symbol: snapshot.targetKindRaw == "time"
                            ? "timer" : "repeat"
                    )
                    WatchStrengthReadout(
                        title: ATHLTHLocalization.choose(
                            english: "LOAD", norwegian: "BELASTNING"
                        ),
                        value: snapshot.loadKindRaw == "resistanceLevel"
                            ? ATHLTHLocalization.choose(
                                english: "Level \(snapshot.draftResistanceLevel ?? 5)",
                                norwegian: "Nivå \(snapshot.draftResistanceLevel ?? 5)"
                              )
                            : String(format: "%.1f kg",
                                     snapshot.draftWeightKilograms),
                        symbol: "scalemass"
                    )
                }

                Label(
                    ATHLTHLocalization.choose(
                        english: "Log this set on iPhone",
                        norwegian: "Registrer settet på iPhone"
                    ),
                    systemImage: "iphone"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchTheme.accentDeep)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .watchSurface()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
    }
}

private struct WatchStrengthPageHeading: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(WatchTheme.liveAction)
            Text(title)
                .tracking(0.7)
                .foregroundStyle(WatchTheme.textPrimary)
        }
        .font(.system(size: 10, weight: .bold))
        .padding(.bottom, 2)
    }
}

private struct WatchStrengthReadout: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WatchTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(WatchTheme.textPrimary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 16)
    }
}
