import SwiftUI

/// A single low-power, read-only workout dashboard for Apple Watch.
/// The workout manager continues recording independently of the display.
/// Do not add animations, photos, gradients or crown interaction here.
struct WatchTrainingAlwaysOnDashboard: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    private let primary = Color.white.opacity(0.88)
    private let secondary = Color.white.opacity(0.64)
    private let quiet = Color.white.opacity(0.47)
    private let accent = Color(red: 0.48, green: 0.77, blue: 0.78)

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 190 ||
                geometry.size.height < 205

            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                header(compact: compact)

                if workout.kind == .strength {
                    strengthDashboard(compact: compact)
                } else if workout.kind == .running ||
                            workout.kind == .walking {
                    distanceDashboard(compact: compact)
                } else {
                    genericDashboard(compact: compact)
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
                    Text(ATHLTHLocalization.choose(
                        english: "Next set soon",
                        norwegian: "Neste sett snart"
                    ))
                    .font(.system(size: compact ? 23 : 28,
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                    .minimumScaleFactor(0.7)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(current.targetKindRaw == "time"
                             ? timeString(Double(current.draftDurationSeconds ?? 0))
                             : String(current.draftReps))
                            .font(.system(
                                size: compact ? 43 : 51,
                                weight: .bold,
                                design: .rounded
                            ))
                            .monospacedDigit()
                            .foregroundStyle(primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(current.targetKindRaw == "time"
                             ? "SEC"
                             : "REPS")
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
                .font(.system(size: compact ? 10 : 12,
                              weight: .semibold))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(paceString)
                    .font(.system(
                        size: compact ? 35 : 43,
                        weight: .bold, design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("/km")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(secondary)
                Spacer(minLength: 0)
            }

            Text("PACE")
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundStyle(accent)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.2f",
                    max(workout.distanceMeters, 0) / 1000))
                    .font(.system(
                        size: compact ? 30 : 37,
                        weight: .bold, design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("KM")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }

    private func genericDashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workout.kind.title)
                .font(.system(size: compact ? 23 : 28,
                              weight: .bold, design: .rounded))
                .foregroundStyle(primary)
            Spacer(minLength: 0)
            footer()
        }
    }

    private func footer() -> some View {
        HStack(spacing: 6) {
            Label(timeString(workout.elapsedTime), systemImage: "clock")
            Spacer(minLength: 0)
            Label(workout.heartRate > 0
                  ? String(Int(workout.heartRate.rounded()))
                  : "—", systemImage: "heart.fill")
        }
        .font(.system(size: 11, weight: .semibold,
                      design: .rounded))
        .monospacedDigit()
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
