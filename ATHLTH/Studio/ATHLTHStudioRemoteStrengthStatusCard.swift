import SwiftUI

/// Private, read-only view of the last fresh strength summary delivered by
/// the owner's signed-in iPhone. No editing and no HealthKit sample upload.
struct ATHLTHStudioRemoteStrengthStatusCard: View {
    let snapshot: ATHLTHPrivateLiveStrengthSnapshot

    private let ink = Color(red: 0.18, green: 0.19, blue: 0.21)
    private let surface = Color(red: 0.955, green: 0.955, blue: 0.95)

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        tr("CURRENT WORKOUT · \(snapshot.sourceDevice)",
                           "PÅGÅENDE ØKT · \(snapshot.sourceDevice)"),
                        systemImage: "waveform.path.ecg"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Text(snapshot.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 6)
                Text(tr("READ ONLY", "KUN VISNING"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    metrics.frame(maxWidth: .infinity, alignment: .leading)
                    exerciseQueue.frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 15) {
                    metrics
                    exerciseQueue
                }
            }

            Text(tr(
                "Private account sync · last update \(Date(timeIntervalSince1970: snapshot.capturedAtEpoch).formatted(date: .omitted, time: .shortened)) · status expires when iPhone stops updating.",
                "Privat kontosynk · sist oppdatert \(Date(timeIntervalSince1970: snapshot.capturedAtEpoch).formatted(date: .omitted, time: .shortened)) · status forsvinner hvis iPhone slutter å oppdatere."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.075))
        )
        .accessibilityIdentifier("athlth-ipad-remote-live-strength")
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let current = snapshot.currentExercise {
                Text(tr("CURRENT EXERCISE", "NÅVÆRENDE ØVELSE"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(current)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let number = snapshot.currentSetNumber {
                    Text(tr("Set \(number) of \(snapshot.currentSetCount)",
                            "Sett \(number) av \(snapshot.currentSetCount)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 17) {
                metric(tr("Done", "Utført"), "\(snapshot.completedSets)")
                metric(tr("Remaining", "Gjenstår"),
                       "\(max(snapshot.totalPlannedSets -
                               snapshot.completedSets - snapshot.skippedSets, 0))")
                if snapshot.skippedSets > 0 {
                    metric(tr("Skipped", "Hoppet over"), "\(snapshot.skippedSets)")
                }
            }

            ProgressView(
                value: snapshot.totalPlannedSets > 0
                    ? Double(snapshot.completedSets + snapshot.skippedSets) /
                      Double(snapshot.totalPlannedSets)
                    : 0
            )
            .tint(ink)

            if let until = snapshot.restEndsAtEpoch {
                HStack(spacing: 10) {
                    Label(tr("Rest", "Pause"), systemImage: "timer")
                        .font(.subheadline)
                    Spacer(minLength: 4)
                    Text(Date(timeIntervalSince1970: until), style: .timer)
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(ink)
                .padding(14)
                .background(surface, in: RoundedRectangle(cornerRadius: 13))
            } else if let reps = snapshot.plannedReps {
                Label(
                    "\(reps) reps" + (snapshot.plannedWeightKilograms.map {
                        String(format: " · %.1f kg", $0)
                    } ?? ""),
                    systemImage: "dumbbell"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(ink)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var exerciseQueue: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("Exercise overview", "Øvelsesoversikt"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            ForEach(snapshot.exercises) { exercise in
                HStack(spacing: 8) {
                    Image(systemName: exercise.isCurrent
                          ? "circle.inset.filled"
                          : exercise.completedSets + exercise.skippedSets >=
                            exercise.plannedSets ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(exercise.isCurrent ? ink : Color.secondary)
                    Text(exercise.name)
                        .font(.subheadline.weight(exercise.isCurrent
                                                  ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Text("\(exercise.completedSets)/\(exercise.plannedSets)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(ink)
            }
        }
        .padding(14)
        .background(surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
