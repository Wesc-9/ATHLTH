import SwiftUI
import Charts

/// Running-speed progression parallels exercise-load history. It is derived
/// from completed recordings only; prescribed speeds never become results.
struct ATHLTHRunningSpeedProgressCard: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore
    @State private var watchHistory: [ATHLTHCompletedRunningPerformance] = []
    @State private var selectedName = ""

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var completed: [ATHLTHCompletedRunningPerformance] {
        let phones = phoneWorkout.history.compactMap {
            ATHLTHCompletedRunningPerformance(phone: $0)
        }
        let unique = Dictionary(
            (phones + watchHistory).map { ($0.id, $0) },
            uniquingKeysWith: { old, _ in old }
        )
        return unique.values.sorted { $0.completedAt < $1.completedAt }
    }

    private var choices: [String] {
        Array(Set(completed.map(\.title))).sorted()
    }

    private var name: String? {
        choices.contains(selectedName) ? selectedName : choices.first
    }

    private var selectedResults: [ATHLTHCompletedRunningPerformance] {
        guard let name else { return [] }
        return completed.filter { $0.title == name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(tr("RUNNING SPEED PROGRESSION", "HASTIGHETSUTVIKLING"))
                .font(.caption2.weight(.semibold))
                .tracking(1.3)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)

            Text(tr("Completed interval workouts", "Fullførte intervalløkter"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(ATHLTHPlanDesign.ink)

            if let name, let latest = selectedResults.last {
                Picker(tr("Workout", "Treningsøkt"),
                       selection: Binding(
                           get: { name }, set: { selectedName = $0 }
                       )) {
                    ForEach(choices, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .tint(ATHLTHPlanDesign.ink)

                if !selectedResults.isEmpty {
                    Chart {
                        ForEach(selectedResults) { record in
                            if let speed = record.averageWorkSpeed {
                                LineMark(
                                    x: .value("Dato", record.completedAt),
                                    y: .value("km/t", speed)
                                )
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                PointMark(
                                    x: .value("Dato", record.completedAt),
                                    y: .value("km/t", speed)
                                )
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            }
                        }
                    }
                    .frame(height: 170)
                    .chartYAxis { AxisMarks(position: .leading) }
                }

                HStack {
                    Text(latest.completedAt.formatted(
                        date: .abbreviated, time: .omitted
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer()
                    if let average = latest.averageWorkSpeed {
                        Text(String(format: "%.1f km/t", average))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                    }
                }

                ForEach(Array(latest.workSteps.enumerated()),
                        id: \.element.index) { number, step in
                    if let actual = step.actualSpeedKilometersPerHour {
                        HStack(spacing: 9) {
                            Text(tr("Effort", "Drag") + " \(number + 1)")
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 2)
                            Text(String(format: "%.1f km/t", actual))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            if let target = step.targetPaceSecondsPerKilometer,
                               target > 0 {
                                Text(String(format: "mål %.1f", 3_600 / target))
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .padding(.vertical, 5)
                    }
                }

                if let samples = latest.minutes, !samples.isEmpty {
                    DisclosureGroup(tr("Minute-by-minute run", "Løp minutt for minutt")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(samples.prefix(80).enumerated()),
                                    id: \.offset) { _, minute in
                                HStack(spacing: 8) {
                                    Text(tr("Phase", "Del") + " \(minute.stepIndex + 1) · " +
                                        "\(Int(ceil(minute.stepElapsedAtEndSeconds / 60))) min")
                                        .font(.caption)
                                    Spacer(minLength: 3)
                                    if minute.activeSeconds > 0 {
                                        Text(String(format: "%.1f km/t",
                                            minute.recordedDistanceMeters * 3.6 /
                                            minute.activeSeconds))
                                            .font(.caption.weight(.semibold))
                                            .monospacedDigit()
                                    }
                                    if let bpm = minute.watchHeartRateBPM {
                                        Text("\(Int(bpm.rounded())) bpm")
                                            .font(.caption)
                                    }
                                }
                                if let incline = minute.manuallyEnteredTreadmillInclinePercent {
                                    Text(String(format: "Oppgitt stigning %.1f %%", incline))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(tr(
                                "Speed is derived from recorded distance and time. Targets and manually entered incline are not sensor measurements.",
                                "Hastigheten er beregnet fra registrert distanse og tid. Målverdier og manuelt oppgitt stigning er ikke sensormålinger."
                            ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 7)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                }

                if latest.userReported {
                    Label(tr(
                        "Treadmill speeds were entered manually.",
                        "Møllehastighetene er registrert manuelt."
                    ), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            } else {
                Text(tr(
                    "Finish every step of a structured run with recorded distance. Partial efforts, cancelled workouts and targets never count.",
                    "Fullfør alle delene i en strukturert løpeøkt med registrert distanse. Enkelt­drag, avbrutte økter og målhastigheter teller ikke."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
        .padding(16)
        .athlthPlanCard(radius: 20)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(
            for: .athlthTrainingDataDidChange
        )) { _ in reload() }
    }

    private func reload() {
        watchHistory = ATHLTHRunningPerformanceHistory.load(
            userID: session.profile.userID
        )
    }
}
