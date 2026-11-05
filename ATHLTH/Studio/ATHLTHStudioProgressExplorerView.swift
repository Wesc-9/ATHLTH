import SwiftUI
import Charts

/// Athlete-level progression from recorded HealthKit summaries and completed
/// strength sets. No prescribed workout is counted as a performed activity.
struct ATHLTHStudioProgressExplorerView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    @State private var selectedMode = Mode.running
    @State private var selectedDays = 90
    @State private var selectedExercise = ""

    private enum Mode: String, CaseIterable, Identifiable {
        case running, strength
        var id: String { rawValue }
        var title: String {
            switch self {
            case .running:
                return ATHLTHLocalization.choose(
                    english: "Running pace", norwegian: "Løpetempo"
                )
            case .strength:
                return ATHLTHLocalization.choose(
                    english: "Strength progression", norwegian: "Styrkeutvikling"
                )
            }
        }
    }

    private struct ProgressPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let extra: String
    }

    private var rangeStart: Date {
        Calendar.current.date(
            byAdding: .day, value: -selectedDays, to: .now
        ) ?? .distantPast
    }

    private var exercises: [String] {
        let names = strength.workoutHistory
            .filter(\.isFinished)
            .flatMap(\.exercises)
            .filter { exercise in
                exercise.sets.contains {
                    $0.completedAt != nil &&
                    $0.completedWeightKilograms != nil &&
                    $0.isWarmUp != true
                }
            }
            .map { $0.exercise.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var selectedExerciseName: String {
        exercises.contains(selectedExercise) ? selectedExercise :
            exercises.first ?? ""
    }

    private var points: [ProgressPoint] {
        switch selectedMode {
        case .running:
            return health.workouts.compactMap { workout in
                guard workout.activity == .running,
                      workout.startDate >= rangeStart,
                      workout.startDate <= .now,
                      let km = workout.distanceKilometers,
                      km >= 0.5, km.isFinite,
                      workout.duration.isFinite, workout.duration > 0
                else { return nil }
                let pace = workout.duration / km
                guard (120...3_600).contains(pace) else { return nil }
                return ProgressPoint(
                    id: workout.id.uuidString,
                    date: workout.startDate,
                    value: pace,
                    extra: String(format: "%.2f km", km)
                )
            }.sorted { $0.date < $1.date }
        case .strength:
            let chosen = selectedExerciseName
            guard !chosen.isEmpty else { return [] }
            return strength.workoutHistory.filter {
                $0.isFinished && $0.startedAt >= rangeStart &&
                $0.startedAt <= .now
            }.flatMap { workout -> [ProgressPoint] in
                workout.exercises.compactMap { exercise in
                    guard exercise.exercise.name.caseInsensitiveCompare(
                        chosen
                    ) == .orderedSame else { return nil }
                    let weights = exercise.sets
                        .filter { set in
                            set.completedAt != nil &&
                            set.isWarmUp != true &&
                            set.resolvedLoadKind == .weightKilograms
                        }
                        .compactMap(\.completedWeightKilograms)
                        .filter { $0.isFinite && $0 > 0 }
                    guard let maxWeight = weights.max() else { return nil }
                    return ProgressPoint(
                        id: workout.id.uuidString + "-" + exercise.id.uuidString,
                        date: workout.endedAt ?? workout.startedAt,
                        value: maxWeight,
                        extra: workout.title
                    )
                }
            }.sorted { $0.date < $1.date }
        }
    }

    private func valueText(_ value: Double) -> String {
        if selectedMode == .running {
            let rounded = Int(value.rounded())
            return String(format: "%d:%02d /km", rounded / 60, rounded % 60)
        }
        return String(format: "%.1f kg", value)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("PROGRESSION LAB", "UTVIKLINGSLAB"))
                        .font(.caption.weight(.semibold))
                        .tracking(1.3)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(tr("How your performance changes",
                            "Slik utvikler prestasjonene dine seg"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                }
                Spacer(minLength: 5)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { selectors }
                VStack(alignment: .leading, spacing: 10) { selectors }
            }
            if selectedMode == .strength && !exercises.isEmpty {
                Picker(tr("Exercise", "Øvelse"),
                       selection: Binding(
                            get: { selectedExerciseName },
                            set: { selectedExercise = $0 }
                       )) {
                    ForEach(exercises, id: \.self) { exercise in
                        Text(exercise).tag(exercise)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 370, alignment: .leading)
            }

            if points.count >= 2 {
                HStack(spacing: 11) {
                    ATHLTHStudioMetricCard(
                        title: tr("First in period", "Første i perioden"),
                        value: valueText(points[0].value),
                        note: points[0].date.formatted(date: .abbreviated,
                                                        time: .omitted)
                    )
                    ATHLTHStudioMetricCard(
                        title: tr("Most recent", "Siste økt"),
                        value: valueText(points[points.count - 1].value),
                        note: points[points.count - 1].date.formatted(
                            date: .abbreviated, time: .omitted)
                    )
                }
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Measured", point.value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(ATHLTHStudioStyle.gold)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Measured", point.value)
                    )
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                }
                .frame(height: 240)
                .accessibilityLabel(tr(
                    "Trend of verified workout measurements",
                    "Utvikling i registrerte treningsmålinger"
                ))
                Text(tr(
                    "Running shows average workout pace, not individual interval splits. Strength shows the heaviest completed working set for the selected exercise. Lower pace is faster.",
                    "Løping viser snittempo for hele økter, ikke intervall-splitt. Styrke viser tyngste gjennomførte arbeidssett for valgt øvelse. Lavere tempo betyr raskere løp."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    tr("Not enough recorded sessions", "For få registrerte økter"),
                    systemImage: "chart.xyaxis.line",
                    description: Text(tr(
                        "Two or more completed measurements are needed in this period. No progression is inferred from planned sessions.",
                        "Det trengs minst to gjennomførte målinger i perioden. Planlagte økter regnes ikke som treningsresultater."
                    ))
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.65))
        }
        .accessibilityIdentifier("athlth-ipad-progression-lab")
    }

    @ViewBuilder
    private var selectors: some View {
        Picker(tr("Activity", "Aktivitet"), selection: $selectedMode) {
            ForEach(Mode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)
        Picker(tr("Period", "Periode"), selection: $selectedDays) {
            Text("28 " + tr("days", "dager")).tag(28)
            Text("90 " + tr("days", "dager")).tag(90)
            Text(tr("1 year", "1 år")).tag(365)
        }
        .pickerStyle(.menu)
    }
}
