import SwiftUI
import Charts

/// Select one concrete exercise or repeated interval workout and compare
/// only observed, finished results over week, month or year.
struct ATHLTHSpecificProgressView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var phoneWorkout: IPhoneWorkoutStore

    private enum Category: String, CaseIterable, Identifiable {
        case strength, intervals, workouts
        var id: String { rawValue }
        var label: String {
            switch self {
            case .strength:
                return ATHLTHLocalization.choose(english: "Exercise", norwegian: "Øvelse")
            case .intervals:
                return ATHLTHLocalization.choose(english: "Intervals", norwegian: "Intervaller")
            case .workouts:
                return ATHLTHLocalization.choose(english: "Workouts", norwegian: "Økter")
            }
        }
    }

    @State private var category: Category = .strength
    @State private var period: ATHLTHSpecificProgressEngine.Period = .month
    @State private var selectedExerciseID = ""
    @State private var selectedIntervalID = ""
    @State private var selectedWorkoutActivity = ""
    @State private var healthSessions: [SocialPublishableWorkout] = []
    @State private var watchHistory: [ATHLTHCompletedRunningPerformance] = []

    private var gold: Color { ATHLTHPlanDesign.accentInk }
    private var ink: Color { ATHLTHPlanDesign.ink }
    private var muted: Color { ATHLTHPlanDesign.secondaryInk }

    private var strengthSnapshot: ATHLTHTrainTrendEngine.Snapshot {
        ATHLTHTrainTrendEngine.makeGeneral(strengthHistory: strength.workoutHistory)
    }

    private var recordedExercises: [ATHLTHTrainTrendEngine.Exercise] {
        strengthSnapshot.exercises.filter {
            !strengthSnapshot.points(for: $0.id).isEmpty
        }
    }

    private var selectedExercise: ATHLTHTrainTrendEngine.Exercise? {
        recordedExercises.first { $0.id == selectedExerciseID } ?? recordedExercises.first
    }

    private var weightPoints: [ATHLTHTrainTrendEngine.Point] {
        guard let selectedExercise else { return [] }
        return strengthSnapshot.points(for: selectedExercise.id).filter {
            $0.date >= period.start(now: Date()) && $0.date <= Date()
        }
    }

    private var recordedIntervals: [ATHLTHCompletedRunningPerformance] {
        let local = phoneWorkout.history.compactMap {
            ATHLTHCompletedRunningPerformance(phone: $0)
        }
        var seen = Set<UUID>()
        return (local + watchHistory).filter { seen.insert($0.id).inserted }
    }

    private var intervalChoices: [ATHLTHSpecificProgressEngine.IntervalChoice] {
        ATHLTHSpecificProgressEngine.intervalChoices(recordedIntervals)
    }

    private var selectedInterval: ATHLTHSpecificProgressEngine.IntervalChoice? {
        intervalChoices.first { $0.id == selectedIntervalID } ?? intervalChoices.first
    }

    private var selectedRuns: [ATHLTHCompletedRunningPerformance] {
        guard let selectedInterval else { return [] }
        return ATHLTHSpecificProgressEngine.intervalRecords(
            key: selectedInterval.id, from: recordedIntervals, period: period
        )
    }

    private var activityChoices: [String] {
        Array(Set(healthSessions.map { $0.activity.rawValue })).sorted()
    }

    private var selectedActivity: String? {
        activityChoices.contains(selectedWorkoutActivity)
            ? selectedWorkoutActivity : activityChoices.first
    }

    private var selectedActivityRecords: [SocialPublishableWorkout] {
        guard let selectedActivity else { return [] }
        let from = period.start(now: Date())
        return healthSessions.filter {
            $0.activity.rawValue == selectedActivity &&
                $0.endDate >= from && $0.endDate <= Date() &&
                $0.duration.isFinite && $0.duration > 0
        }
        .sorted { $0.endDate < $1.endDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3)
                    .foregroundStyle(gold)
                    .frame(width: 39, height: 39)
                    .background(
                        gold.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("FOLLOW A SPECIFIC RESULT", "FØLG ET KONKRET RESULTAT"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(gold)
                    Text(tr("Your progression", "Din fremgang"))
                        .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
            }

            Text(tr(
                "Choose a recorded exercise or interval workout to compare your real results over time.",
                "Velg en gjennomført øvelse eller intervalløkt og sammenlign faktiske resultater over tid."
            ))
            .font(.caption)
            .foregroundStyle(muted)

            Picker(tr("Activity type", "Aktivitetstype"), selection: $category) {
                ForEach(Category.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if category == .strength {
                if recordedExercises.isEmpty {
                    emptyState(tr(
                        "Finish a strength exercise to see your history.",
                        "Fullfør en styrkeøvelse for å få frem historikken."
                    ))
                } else {
                    Picker(tr("Select exercise", "Velg øvelse"),
                           selection: Binding(
                            get: { selectedExercise?.id ?? "" },
                            set: { selectedExerciseID = $0 }
                           )) {
                        ForEach(recordedExercises) { item in
                            Text(item.title).tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ink)
                    .padding(11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    periodPicker
                    strengthDetail
                }
            } else if category == .intervals {
                if intervalChoices.isEmpty {
                    emptyState(tr(
                        "Finish a structured interval workout to compare efforts.",
                        "Fullfør en strukturert intervalløkt for å sammenligne drag."
                    ))
                } else {
                    Picker(tr("Select interval workout", "Velg intervalløkt"),
                           selection: Binding(
                            get: { selectedInterval?.id ?? "" },
                            set: { selectedIntervalID = $0 }
                           )) {
                        ForEach(intervalChoices) { choice in
                            Text(choice.name).tag(choice.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ink)
                    .padding(11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    periodPicker
                    intervalDetail
                }
            } else {
                if activityChoices.isEmpty {
                    emptyState(tr(
                        "Connect Apple Health to compare completed activities.",
                        "Koble til Apple Health for å sammenligne gjennomførte aktiviteter."
                    ))
                } else {
                    Picker(tr("Select activity", "Velg aktivitet"),
                           selection: Binding(
                            get: { selectedActivity ?? "" },
                            set: { selectedWorkoutActivity = $0 }
                           )) {
                        ForEach(activityChoices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ink)
                    .padding(11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    periodPicker
                    workoutDetail
                }
            }

            Label(
                tr(
                    "Only finished workouts and recorded measurements count. A prescribed target is not a result.",
                    "Kun fullførte økter og registrerte målinger teller. Et planlagt mål regnes ikke som et resultat."
                ),
                systemImage: "checkmark.shield"
            )
            .font(.caption2)
            .foregroundStyle(muted)
        }
        .padding(16)
        .athlthPlanCard(radius: 20)
        .onAppear(perform: reloadWatchHistory)
        .task { await loadHealthHistory() }
        .onReceive(NotificationCenter.default.publisher(
            for: .athlthTrainingDataDidChange
        )) { _ in
            reloadWatchHistory()
            Task { await loadHealthHistory() }
        }
    }

    private var periodPicker: some View {
        Picker(tr("Period", "Periode"), selection: $period) {
            ForEach(ATHLTHSpecificProgressEngine.Period.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var strengthDetail: some View {
        if weightPoints.isEmpty {
            emptyState(tr(
                "No completed sets in the selected period.",
                "Ingen fullførte sett i den valgte perioden."
            ))
        } else {
            let weights = weightPoints.compactMap(\.peakWeightKilograms)
            let totalSets = weightPoints.reduce(0) { $0 + $1.completedWorkingSets }
            let bestWeight = weights.max()
            let delta = ATHLTHSpecificProgressEngine.weightChange(weightPoints)

            HStack(spacing: 10) {
                progressStat(
                    title: tr("Best weight", "Beste vekt"),
                    value: bestWeight.map { String(format: "%.1f kg", $0) } ?? "–"
                )
                progressStat(title: tr("Completed sets", "Fullførte sett"),
                             value: "\(totalSets)")
                progressStat(
                    title: tr("Change", "Endring"),
                    value: delta.map {
                        String(format: "%+.1f kg", $0)
                    } ?? "–"
                )
            }

            if !weights.isEmpty {
                Chart(weightPoints) { point in
                    if let kg = point.peakWeightKilograms {
                        LineMark(
                            x: .value("Dato", point.date),
                            y: .value("Kg", kg)
                        )
                        .foregroundStyle(gold)
                        PointMark(
                            x: .value("Dato", point.date),
                            y: .value("Kg", kg)
                        )
                        .foregroundStyle(gold)
                    }
                }
                .frame(height: 200)
                .chartYAxis { AxisMarks(position: .leading) }
                Text(tr("Heaviest actually completed working set each day (kg).",
                        "Tyngste faktisk fullførte arbeidssett per dag (kg)."))
                    .font(.caption2)
                    .foregroundStyle(muted)
            } else {
                Chart(weightPoints) { point in
                    BarMark(
                        x: .value("Dato", point.date),
                        y: .value("Reps", point.completedRepetitions)
                    )
                    .foregroundStyle(gold)
                }
                .frame(height: 180)
                Text(tr("Completed repetitions per day.",
                        "Faktisk gjennomførte repetisjoner per dag."))
                    .font(.caption2)
                    .foregroundStyle(muted)
            }

            resultListHeader
            ForEach(Array(weightPoints.suffix(6).reversed())) { point in
                HStack {
                    Text(point.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text("\(point.completedWorkingSets) " +
                         tr("sets", "sett"))
                    if let kg = point.peakWeightKilograms {
                        Text(String(format: "%.1f kg", kg))
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(ink)
            }
        }
    }

    @ViewBuilder
    private var intervalDetail: some View {
        if selectedRuns.isEmpty {
            emptyState(tr(
                "No completed matching intervals in this period.",
                "Ingen fullførte, tilsvarende intervaller i perioden."
            ))
        } else {
            let speeds = selectedRuns.compactMap(\.averageWorkSpeed)
            let best = speeds.max()
            let change = ATHLTHSpecificProgressEngine.speedChange(selectedRuns)
            HStack(spacing: 10) {
                progressStat(title: tr("Sessions", "Økter"),
                             value: "\(selectedRuns.count)")
                progressStat(
                    title: tr("Best work pace", "Beste dragtempo"),
                    value: best.map { paceText($0) } ?? "–"
                )
                progressStat(
                    title: tr("Speed change", "Fartsendring"),
                    value: change.map { String(format: "%+.1f km/t", $0) } ?? "–"
                )
            }

            Chart(selectedRuns) { run in
                if let speed = run.averageWorkSpeed {
                    LineMark(
                        x: .value("Dato", run.completedAt),
                        y: .value("Km/t", speed)
                    )
                    .foregroundStyle(gold)
                    PointMark(
                        x: .value("Dato", run.completedAt),
                        y: .value("Km/t", speed)
                    )
                    .foregroundStyle(gold)
                }
            }
            .frame(height: 200)
            .chartYAxis { AxisMarks(position: .leading) }

            Text(tr(
                "Average measured speed during work intervals (km/h). Rest is excluded.",
                "Gjennomsnittlig registrert fart under arbeidsdragene (km/t). Pauser er utelatt."
            ))
            .font(.caption2)
            .foregroundStyle(muted)

            resultListHeader
            ForEach(Array(selectedRuns.suffix(6).reversed())) { run in
                HStack(spacing: 6) {
                    Text(run.completedAt.formatted(
                        date: .abbreviated, time: .omitted
                    ))
                    Spacer(minLength: 2)
                    Text("\(run.workSteps.count) " + tr("efforts", "drag"))
                    if let speed = run.averageWorkSpeed {
                        Text(paceText(speed))
                            .fontWeight(.semibold)
                    }
                    if run.userReported {
                        Image(systemName: "pencil")
                            .accessibilityLabel(tr("Manually entered", "Manuelt registrert"))
                    }
                }
                .font(.caption)
                .foregroundStyle(ink)
            }
        }
    }

    @ViewBuilder
    private var workoutDetail: some View {
        if selectedActivityRecords.isEmpty {
            emptyState(tr(
                "No completed workouts of this activity in this period.",
                "Ingen fullførte økter av denne aktiviteten i perioden."
            ))
        } else {
            let workouts = selectedActivityRecords
            let distances = workouts.compactMap(\.distanceMeters).filter {
                $0.isFinite && $0 > 0
            }
            let longestDistance = distances.max()
            let longestTime = workouts.map(\.duration).max() ?? 0
            let averageDuration = workouts.reduce(0.0) {
                $0 + $1.duration
            } / Double(workouts.count)

            HStack(spacing: 10) {
                progressStat(title: tr("Workouts", "Økter"),
                             value: "\(workouts.count)")
                progressStat(
                    title: tr("Average time", "Snittid"),
                    value: String(format: "%.0f min", averageDuration / 60)
                )
                progressStat(
                    title: longestDistance == nil
                        ? tr("Longest", "Lengste")
                        : tr("Longest distance", "Lengste distanse"),
                    value: longestDistance.map {
                        String(format: "%.1f km", $0 / 1_000)
                    } ?? String(format: "%.0f min", longestTime / 60)
                )
            }

            Chart(workouts) { workout in
                if longestDistance != nil {
                    if let meters = workout.distanceMeters, meters > 0 {
                        BarMark(
                            x: .value("Dato", workout.endDate),
                            y: .value("Km", meters / 1_000)
                        )
                        .foregroundStyle(gold)
                    }
                } else {
                    BarMark(
                        x: .value("Dato", workout.endDate),
                        y: .value("Min", workout.duration / 60)
                    )
                    .foregroundStyle(gold)
                }
            }
            .frame(height: 180)
            .chartYAxis { AxisMarks(position: .leading) }

            Text(
                longestDistance != nil
                    ? tr("Recorded distance per session (km).",
                         "Registrert distanse per økt (km).")
                    : tr("Recorded duration per session (minutes).",
                         "Registrert varighet per økt (minutter).")
            )
            .font(.caption2)
            .foregroundStyle(muted)

            resultListHeader
            ForEach(Array(workouts.suffix(6).reversed())) { workout in
                HStack(spacing: 6) {
                    Text(workout.endDate.formatted(
                        date: .abbreviated, time: .omitted
                    ))
                    Spacer(minLength: 2)
                    Text(String(format: "%.0f min", workout.duration / 60))
                    if let meters = workout.distanceMeters, meters > 0 {
                        Text(String(format: "%.1f km", meters / 1_000))
                            .fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(ink)
            }
        }
    }

    private var resultListHeader: some View {
        Text(tr("RECENT RECORDED RESULTS", "SISTE REGISTRERTE RESULTATER"))
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(gold)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(muted)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private func progressStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(ink)
            Text(title)
                .font(.caption2)
                .foregroundStyle(muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(10)
        .background(
            ATHLTHPlanDesign.warmSurface,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func paceText(_ speed: Double) -> String {
        guard speed > 0, speed.isFinite else { return "–" }
        let seconds = Int((3_600 / speed).rounded())
        return String(format: "%d:%02d/km", seconds / 60, seconds % 60)
    }

    private func loadHealthHistory() async {
        guard health.hasRequestedAuthorization else {
            healthSessions = []
            return
        }
        guard let completed = try? await health.workoutHistory() else { return }
        // Apple Health's UUIDs are stable and guard against re-importing one
        // physical activity twice. Exercise-level detail stays in ATHLTH logs.
        var seen = Set<UUID>()
        healthSessions = completed.map(SocialPublishableWorkout.init(summary:))
            .filter { seen.insert($0.id).inserted }
    }

    private func reloadWatchHistory() {
        watchHistory = ATHLTHRunningPerformanceHistory.load(
            userID: session.profile.userID
        )
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}
