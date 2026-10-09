import SwiftUI
import Charts

/// Fast, on-demand training charts backed only by completed, directly linked
/// ATHLTH strength sessions. No new workout engine or AI dependency.
struct ATHLTHTrainTrendsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var goalStore: GoalStore

    let planID: UUID

    @State private var chosenExerciseID = ""
    @State private var chosenMetric: Metric = .peakLoad
    @State private var chosenPeriod: Period = .all

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let muted = Color(red: 0.47, green: 0.45, blue: 0.43)
    private let champagne = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let green = Color(red: 0.28, green: 0.53, blue: 0.43)
    private let pale = Color(red: 0.986, green: 0.977, blue: 0.962)
    private let hairline = Color(red: 0.89, green: 0.87, blue: 0.84)

    private enum Metric: String, CaseIterable, Identifiable {
        case peakLoad, volume, sets, reps
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .peakLoad: return "kg"
            case .volume: return "Volum"
            case .sets: return "Sett"
            case .reps: return "Reps"
            }
        }
        var unit: String {
            switch self {
            case .peakLoad, .volume: return "kg"
            case .sets: return "sett"
            case .reps: return "reps"
            }
        }
    }

    private enum Period: String, CaseIterable, Identifiable {
        case month, twelveWeeks, all
        var id: String { rawValue }
    }

    private struct ChartPoint: Identifiable {
        let date: Date
        let value: Double
        var id: String { "\(Int(date.timeIntervalSince1970))" }
    }

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }
    private var snapshot: ATHLTHTrainTrendEngine.Snapshot? {
        guard let plan else { return nil }
        return ATHLTHTrainTrendEngine.make(
            plan: plan, strengthHistory: strength.workoutHistory
        )
    }
    private var exercise: ATHLTHTrainTrendEngine.Exercise? {
        snapshot?.exercises.first(where: { $0.id == chosenExerciseID })
            ?? snapshot?.exercises.first
    }
    private var matchingGoal: ATHLTHGoal? {
        guard let exercise else { return nil }
        return goalStore.goals.first {
            $0.linkedTrainingPlanID == planID &&
            $0.target?.metric == .strengthWeightKilograms &&
            $0.target?.exerciseName.map {
                ATHLTHTrainTrendEngine.normalize($0) == exercise.id
            } == true &&
            $0.target?.targetValue.isFinite == true &&
            ($0.target?.targetValue ?? 0) > 0
        }
    }
    private var targetWeight: Double? {
        chosenMetric == .peakLoad ? matchingGoal?.target?.targetValue : nil
    }
    private var chartPoints: [ChartPoint] {
        guard let exercise else { return [] }
        let filtered = snapshot?.points(for: exercise.id).filter { item in
            switch chosenPeriod {
            case .all: return true
            case .month:
                return item.date >= (Calendar.current.date(
                    byAdding: .day, value: -28, to: Date()
                ) ?? .distantPast)
            case .twelveWeeks:
                return item.date >= (Calendar.current.date(
                    byAdding: .day, value: -84, to: Date()
                ) ?? .distantPast)
            }
        } ?? []
        return filtered.compactMap { point in
            let value: Double?
            switch chosenMetric {
            case .peakLoad: value = point.peakWeightKilograms
            case .volume: value = point.volumeKilograms
            case .sets: value = Double(point.completedWorkingSets)
            case .reps: value = Double(point.completedRepetitions)
            }
            guard let value, value.isFinite, value >= 0 else { return nil }
            return ChartPoint(date: point.date, value: value)
        }
    }
    private var maximumY: Double {
        max(
            1,
            max(chartPoints.map(\.value).max() ?? 0, targetWeight ?? 0) * 1.16
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    header
                    if let plan, let snapshot {
                        metricOverview(snapshot)
                        exerciseSelection(snapshot)
                        chartCard
                        weeklyVolume(plan)
                        sourceExplanation
                    } else {
                        ContentUnavailableView(
                            tr("Plan unavailable", "Fant ikke treningsplanen"),
                            systemImage: "chart.xyaxis.line"
                        )
                    }
                }
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(pale.ignoresSafeArea())
            .navigationTitle(tr("Performance trends", "Treningsutvikling"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .onAppear(perform: selectInitialExercise)
            .onChange(of: planID) { _, _ in
                chosenExerciseID = ""
                selectInitialExercise()
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("EVIDENCE IN MOTION", "SE UTVIKLINGEN"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(champagne)
            Text(tr("Every rep tells a story.", "Fremgang du kan se."))
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(plan?.title ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
            Text(tr(
                "Trends show recorded working sets from workouts linked to this program.",
                "Grafene viser registrerte arbeidssett fra økter knyttet til akkurat denne planen."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
        }
    }

    private func metricOverview(
        _ snapshot: ATHLTHTrainTrendEngine.Snapshot
    ) -> some View {
        HStack(spacing: 0) {
            statistic(
                "\(snapshot.linkedWorkoutCount)",
                tr("LOGGED SESSIONS", "LOGGFØRTE ØKTER")
            )
            Rectangle().fill(hairline).frame(width: 0.8, height: 35)
            statistic(
                "\(snapshot.points.count)",
                tr("EXERCISE-DAYS", "ØVELSESDAGER")
            )
            Rectangle().fill(hairline).frame(width: 0.8, height: 35)
            statistic(
                "\(snapshot.exercises.count)",
                tr("EXERCISES", "ØVELSER")
            )
        }
        .padding(16)
        .trendSurface(line: hairline)
    }

    private func statistic(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exerciseSelection(
        _ snapshot: ATHLTHTrainTrendEngine.Snapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("CHOOSE EXERCISE", "VELG ØVELSE"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(champagne)
            if snapshot.exercises.isEmpty {
                Text(tr(
                    "Add strength exercises to the plan to follow their results here.",
                    "Legg til styrkeøvelser i planen for å følge utviklingen."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            } else {
                Picker(tr("Exercise", "Øvelse"), selection: $chosenExerciseID) {
                    ForEach(snapshot.exercises) { item in
                        Text(item.title).tag(item.id)
                    }
                }
                .tint(ink)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(hairline, lineWidth: 0.7)
                }
                .onAppear {
                    if chosenExerciseID.isEmpty {
                        chosenExerciseID = snapshot.exercises.first?.id ?? ""
                    }
                }
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("EXERCISE PROGRESSION", "ØVELSESPROGRESJON"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(champagne)
                    Text(exercise?.title ?? tr("No exercise", "Ingen øvelse"))
                        .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 4)
                if let latest = chartPoints.last {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(latest.value.formatted(
                            .number.precision(.fractionLength(0...1))
                        ) + " " + chosenMetric.unit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                        Text(tr("LATEST", "SIST"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(muted)
                    }
                }
            }

            Picker(tr("Metric", "Måling"), selection: $chosenMetric) {
                ForEach(Metric.allCases) { option in
                    Text(option.symbol).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker(tr("Period", "Tidsperiode"), selection: $chosenPeriod) {
                Text(tr("4 weeks", "4 uker")).tag(Period.month)
                Text(tr("12 weeks", "12 uker")).tag(Period.twelveWeeks)
                Text(tr("All", "Alle")).tag(Period.all)
            }
            .pickerStyle(.segmented)

            if chartPoints.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 25, weight: .ultraLight))
                        .foregroundStyle(champagne)
                    Text(tr("No recorded results in this period",
                            "Ingen registrerte resultater i denne perioden"))
                        .font(.subheadline.weight(.medium))
                    Text(tr(
                        "The chart stays empty until an ATHLTH workout records completed working sets for this exercise.",
                        "Grafen vises først når en ATHLTH-økt har registrert gjennomførte arbeidssett for øvelsen."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 27)
            } else {
                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Recorded", point.value)
                        )
                        .foregroundStyle(champagne)
                        .interpolationMethod(.linear)

                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Recorded", point.value)
                        )
                        .foregroundStyle(champagne)
                        .symbolSize(37)
                    }

                    if let target = targetWeight {
                        RuleMark(y: .value("Target load", target))
                            .foregroundStyle(green)
                            .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(tr("GOAL", "MÅL") + " " + target.formatted() + " kg")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(green)
                            }
                    }
                }
                .chartYScale(domain: 0...maximumY)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel()
                    }
                }
                .frame(height: 222)

                HStack(spacing: 13) {
                    Label(tr("Recorded", "Registrert"),
                          systemImage: "circle.fill")
                        .foregroundStyle(champagne)
                    if targetWeight != nil {
                        Label(tr("Goal", "Mål"), systemImage: "minus")
                            .foregroundStyle(green)
                    }
                }
                .font(.caption2)
            }

            Text(metricDescription)
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .trendSurface(line: hairline)
    }

    private var metricDescription: String {
        switch chosenMetric {
        case .peakLoad:
            return tr(
                "Highest actual working-set load per day (kg), not estimated one-rep max. A goal line appears only for a matching strength goal.",
                "Høyeste registrerte arbeidsvekt per dag (kg), ikke estimert 1RM. Mållinje vises bare hvis øvelsen har et tilsvarende styrkemål."
            )
        case .volume:
            return tr(
                "Total recorded working-set volume per day (reps × kg). Time-based or bodyweight work does not create artificial kilograms.",
                "Registrert treningsvolum per dag (reps × kg). Tidsbasert trening eller kroppsvekt gir ikke oppdiktede kilo."
            )
        case .sets:
            return tr(
                "Only completed working sets count. Warm-up and unfinished sets are excluded.",
                "Kun fullførte arbeidssett telles. Oppvarming og ufullførte sett er utelatt."
            )
        case .reps:
            return tr(
                "Recorded repetitions from completed working sets only.",
                "Kun registrerte repetisjoner fra fullførte arbeidssett."
            )
        }
    }

    private func weeklyVolume(_ plan: TrainingPlan) -> some View {
        let report = TrainingPlanStrengthReport.make(
            plan: plan, strengthHistory: strength.workoutHistory
        )
        let hasVolume = report.weeks.contains { $0.performedVolumeKilograms > 0 }

        return VStack(alignment: .leading, spacing: 13) {
            Text(tr("RECORDED WEEKLY TRAINING LOAD", "REGISTRERT UKENTLIG VOLUM"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(champagne)
            Text(tr("The work behind each week.", "Arbeidet bak hver uke."))
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(ink)

            if hasVolume {
                ScrollView(.horizontal) {
                    Chart(report.weeks) { week in
                        BarMark(
                            x: .value("Week", week.number),
                            y: .value("Logged kg", week.performedVolumeKilograms)
                        )
                        .foregroundStyle(champagne.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) {
                            AxisValueLabel()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            AxisValueLabel()
                        }
                    }
                    .frame(width: max(CGFloat(report.weeks.count * 29), 300),
                           height: 172)
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 10) {
                    Text(tr("WEEK", "UKE"))
                        .font(.system(size: 9, weight: .medium))
                    Spacer()
                    Text(tr("Actual load: kg × reps", "Faktisk volum: kg × reps"))
                        .font(.caption2)
                }
                .foregroundStyle(muted)
            } else {
                Text(tr(
                    "Weekly training volume appears after linked strength workouts have completed sets with recorded repetitions and weights.",
                    "Ukentlig volum vises når tilknyttede styrkeøkter har registrerte repetisjoner og vekter."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
                .padding(.vertical, 9)
            }

            HStack(spacing: 0) {
                statistic("\(report.totalPlannedStrengthSets)",
                          tr("PLANNED SETS", "PLANLAGTE SETT"))
                Rectangle().fill(hairline).frame(width: 0.7, height: 35)
                statistic("\(report.totalPerformedStrengthSets)",
                          tr("WORK SETS", "UTFØRTE SETT"))
            }
        }
        .padding(17)
        .trendSurface(line: hairline)
    }

    private var sourceExplanation: some View {
        Label(
            tr(
                "Source: completed ATHLTH strength logs explicitly linked to this training plan. Apple Health-only workouts can affect overall completion but do not supply these exercise-level charts.",
                "Kilde: fullførte ATHLTH-styrkelogger som er koblet direkte til treningsplanen. Økter bare fra Apple Health kan telle i total fremgang, men gir ikke øvelsesdata til grafene."
            ),
            systemImage: "info.circle"
        )
        .font(.caption2)
        .foregroundStyle(muted)
    }

    private func selectInitialExercise() {
        if !chosenExerciseID.isEmpty,
           snapshot?.exercises.contains(where: { $0.id == chosenExerciseID }) == true {
            return
        }
        if let goal = goalStore.goals.first(where: {
            $0.linkedTrainingPlanID == planID &&
            $0.target?.metric == .strengthWeightKilograms &&
            $0.target?.exerciseName != nil
        }), let named = goal.target?.exerciseName {
            let matching = ATHLTHTrainTrendEngine.normalize(named)
            if snapshot?.exercises.contains(where: { $0.id == matching }) == true {
                chosenExerciseID = matching
                return
            }
        }
        chosenExerciseID = snapshot?.exercises.first?.id ?? ""
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

private extension View {
    func trendSurface(line: Color) -> some View {
        self.background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(line, lineWidth: 0.7)
            }
    }
}
