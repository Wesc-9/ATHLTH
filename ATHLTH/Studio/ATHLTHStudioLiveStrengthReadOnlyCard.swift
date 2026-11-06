import SwiftUI

/// A read-only iPad surface for the locally available active strength log.
/// It does not edit sets, own HealthKit recording, or imply remote freshness.
struct ATHLTHStudioLiveStrengthReadOnlyCard: View {
    @EnvironmentObject private var strength: StrengthWorkoutStore

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.18)
    private let subtle = Color(red: 0.95, green: 0.94, blue: 0.92)
    private let outline = Color(red: 0.88, green: 0.87, blue: 0.85)

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if let workout = strength.activeWorkout {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            tr("WORKOUT IN PROGRESS", "ØKT PÅGÅR"),
                            systemImage: "waveform.path.ecg"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Text(workout.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    Spacer(minLength: 8)
                    Text(tr("READ ONLY", "KUN VISNING"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        sessionMetrics(workout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        exerciseQueue(workout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        sessionMetrics(workout)
                        exerciseQueue(workout)
                    }
                }

                Text(tr(
                    "Live view of training data available on this iPad. Registration remains on iPhone or Apple Watch.",
                    "Viser treningsdata som er tilgjengelige på denne iPaden. Registrering gjøres fortsatt på iPhone eller Apple Watch."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
            .accessibilityIdentifier("athlth-ipad-live-strength-readonly")
        }
    }

    private func sessionMetrics(_ workout: StrengthWorkoutLog) -> some View {
        let setCount = workout.exercises.reduce(0) { $0 + $1.sets.count }
        let completed = workout.totalCompletedSets
        let skipped = workout.exercises.reduce(0) {
            $0 + ($1.skippedPlannedSetCount ?? 0)
        }

        return VStack(alignment: .leading, spacing: 14) {
            if let exercise = strength.currentExercise {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("CURRENT EXERCISE", "NÅVÆRENDE ØVELSE"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(exercise.exercise.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let set = strength.currentSet {
                        Text(tr("Set", "Sett") + " \(set.setNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 18) {
                metric(tr("Completed", "Utførte"), value: "\(completed)")
                metric(tr("Remaining", "Gjenstår"),
                       value: "\(max(setCount - completed, 0))")
                if skipped > 0 {
                    metric(tr("Skipped", "Hoppet over"), value: "\(skipped)")
                }
            }

            ProgressView(value: setCount > 0 ? Double(completed) / Double(setCount) : 0)
                .tint(ink)

            if let restEndsAt = strength.restEndsAt {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .foregroundStyle(ink)
                    Text(tr("Rest remaining", "Gjenstående pause"))
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Text(restEndsAt, style: .timer)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ink)
                }
                .padding(13)
                .background(subtle, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func exerciseQueue(_ workout: StrengthWorkoutLog) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("Exercise overview", "Øvelsesoversikt"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: exercise.isCompleted
                          ? "checkmark.circle.fill"
                          : index == strength.currentExerciseIndex
                              ? "circle.inset.filled" : "circle")
                        .foregroundStyle(index == strength.currentExerciseIndex
                                         ? ink : .secondary)
                    Text(exercise.exercise.name)
                        .font(.subheadline.weight(index == strength.currentExerciseIndex
                                                  ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(exercise.sets.filter(\.isCompleted).count)/\(exercise.sets.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(ink)
            }
        }
        .padding(14)
        .background(subtle, in: RoundedRectangle(cornerRadius: 14))
    }
}
