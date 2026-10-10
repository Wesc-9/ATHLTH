import SwiftUI
import Charts

/// A new read-only progress surface over preserved workout history.
/// Planned and performed sessions are always kept distinct.
struct ATHLTHTrainProgressPremiumView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let onOpenPlan: () -> Void

    @State private var selectedProgressArea: ProgressArea = .trainingPlan

    private enum ProgressArea: String, CaseIterable, Identifiable {
        case trainingPlan
        case general

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trainingPlan:
                return ATHLTHLocalization.choose(
                    english: "Training plan",
                    norwegian: "Treningsplan"
                )
            case .general:
                return ATHLTHLocalization.choose(
                    english: "General progress",
                    norwegian: "Generell fremgang"
                )
            }
        }
    }

    @State private var showingDetailedAnalysis = false
    @State private var showingGoals = false
    @State private var showingTrends = false
    @State private var showingCoach = false
    @State private var showingRecoveryAdvice = false

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let muted = Color(red: 0.46, green: 0.45, blue: 0.43)
    private let champagne = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let hairline = Color(red: 0.89, green: 0.87, blue: 0.84)
    private let warm = Color(red: 0.965, green: 0.950, blue: 0.925)

    private var plan: TrainingPlan? { session.activePlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("THE WORK BEHIND THE RESULTS", "VEIEN MOT MÅLET"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(champagne)
                Text(tr("Progress", "Fremgang"))
                    .font(.system(size: 35, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(tr(
                    "Follow what you planned, what you actually trained, and how far you've come.",
                    "Se forskjellen på det du planla, det du gjennomførte og hva du har oppnådd."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            }

            HStack(spacing: 4) {
                ForEach(ProgressArea.allCases) { area in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedProgressArea = area
                        }
                    } label: {
                        Text(area.title)
                            .font(.subheadline.weight(
                                selectedProgressArea == area ? .semibold : .medium
                            ))
                            .foregroundStyle(
                                selectedProgressArea == area ? Color.white : ink
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                            .frame(maxWidth: .infinity)
                            .frame(height: 43)
                            .background(
                                selectedProgressArea == area
                                    ? ink
                                    : Color.clear,
                                in: RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selectedProgressArea == area ? .isSelected : []
                    )
                }
            }
            .padding(4)
            .background(
                Color(red: 0.93, green: 0.92, blue: 0.90),
                in: RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
            )

            switch selectedProgressArea {
            case .trainingPlan:
                if let plan {
                    progressContent(for: plan)
                } else {
                    noPlanContent
                }
            case .general:
                ATHLTHTrainGeneralProgressContent()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingDetailedAnalysis) {
            if let plan {
                TrainingPlanProgressDetailView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingGoals) {
            if let plan {
                ATHLTHTrainGoalHubView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingTrends) {
            if let plan {
                ATHLTHTrainTrendsView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingCoach) {
            if let plan {
                ATHLTHTrainProgressionCoachView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingRecoveryAdvice) {
            if let plan {
                ATHLTHTrainRecoveryAdviceView(planID: plan.id)
            }
        }
    }

    private func progressContent(for plan: TrainingPlan) -> some View {
        let snapshot = session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let planned = snapshot.totalSessions
        let finished = min(max(snapshot.completedSessions, 0), planned)
        let skipped = snapshot.skippedSessions
        let fraction = snapshot.completionFraction

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("ACTIVE PROGRAM", "AKTIVT PROGRAM"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(champagne)
                Text(plan.title)
                    .font(.system(size: 27, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((fraction * 100).rounded()))")
                        .font(.system(size: 57, weight: .light, design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(muted)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(finished) / \(planned)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(tr("completed workouts", "gjennomførte økter"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                }
                GeometryReader { geometry in
                    Capsule()
                        .fill(hairline.opacity(0.65))
                        .overlay(alignment: .leading) {
                            Capsule().fill(champagne)
                                .frame(width: geometry.size.width * fraction)
                        }
                }
                .frame(height: 7)

                HStack(spacing: 0) {
                    stat(tr("PLANNED", "PLANLAGT"), value: "\(planned)")
                    Rectangle().fill(hairline).frame(width: 0.7, height: 39)
                    stat(tr("PERFORMED", "GJENNOMFØRT"), value: "\(finished)")
                    Rectangle().fill(hairline).frame(width: 0.7, height: 39)
                    stat(tr("SKIPPED", "HOPPET OVER"), value: "\(skipped)")
                }
                .padding(.top, 5)
            }
            .padding(18)
            .freshProgressSurface(line: hairline)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("TRAINING BY WEEK", "TRENING UKE FOR UKE"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(champagne)
                    Spacer()
                    Text(tr("Actual / Planned", "Utført / Planlagt"))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, week in
                        let workouts = week.days.flatMap(\.sessions)
                        let done = workouts.filter {
                            session.isPlanSessionCompleted(
                                planID: plan.id,
                                sessionID: $0.id,
                                healthWorkouts: health.workouts,
                                strengthHistory: strength.workoutHistory
                            )
                        }.count
                        VStack(spacing: 6) {
                            GeometryReader { proxy in
                                let height = max(proxy.size.height, 1)
                                let full = CGFloat(workouts.count) /
                                    CGFloat(max(maxSessionsPerWeek(plan), 1)) * height
                                let performed = CGFloat(done) /
                                    CGFloat(max(maxSessionsPerWeek(plan), 1)) * height
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(warm)
                                        .frame(height: full)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(champagne)
                                        .frame(height: performed)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .bottom)
                            }
                            .frame(height: 95)
                            Text("\(index + 1)")
                                .font(.system(size: 9))
                                .foregroundStyle(muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if plan.weeks.count > 9 {
                    Text(tr("Weeks are shown in order. Scroll for additional detail in analysis.",
                            "Uker vises i rekkefølge. Åpne analyse for mer detaljer."))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
            }
            .padding(15)
            .freshProgressSurface(line: hairline)

            if !snapshot.missed.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("Workouts to review", "Økter som trenger oppfølging"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr(
                            "\(snapshot.missed.count) planned sessions were not completed. You decide whether to move or skip them.",
                            "\(snapshot.missed.count) tidligere planlagte økter mangler. Du bestemmer om de skal flyttes eller hoppes over."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(15)
                .freshProgressSurface(line: hairline)
            }

            Button {
                showingRecoveryAdvice = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "leaf")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Recovery suggestions", "Restitusjonsforslag"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Optional, local adjustments to upcoming strength training",
                                "Valgfrie, lokale tilpasninger av kommende styrkeøkter"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.caption)
                }
                .foregroundStyle(ink)
                .padding(15)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)

            Button {
                showingCoach = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Progression suggestions", "Forslag til progresjon"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Optional adjustments based on logged training",
                                "Valgfrie endringer basert på gjennomført trening"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(ink)
                .padding(15)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)

            Button {
                showingTrends = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Exercise and volume trends", "Øvelser og treningsutvikling"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Actual loads, working sets and progress toward goals",
                                "Arbeidsvekter, sett og utvikling mot treningsmål"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(ink)
                .padding(15)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)

            Button {
                showingGoals = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Goals and training blocks", "Mål og treningsblokker"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Planned vs. completed – with real evidence",
                                "Planlagt og utført – med faktiske resultater"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(ink)
                .padding(15)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)

            Button {
                showingDetailedAnalysis = true
            } label: {
                HStack {
                    Spacer()
                    Text(tr("Detailed analysis", "Detaljert treningsanalyse"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(15)
                .background(ink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button(action: onOpenPlan) {
                HStack {
                    Text(tr("Back to training plan", "Tilbake til treningsplan"))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
                .padding(14)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)
        }
    }

    private var noPlanContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(champagne)
            Text(tr("Progress begins with a plan", "Fremgang starter med en plan"))
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(tr("Create a plan to follow your program and compare planned sessions with actual training.",
                    "Opprett en plan for å følge treningsutviklingen og sammenligne planlagt med faktisk trening."))
                .font(.subheadline)
                .foregroundStyle(muted)
            Button(action: onOpenPlan) {
                Label(tr("Open Plan", "Gå til Plan"), systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
            }
            .buttonStyle(.plain)
            .padding(.top, 7)
        }
        .padding(18)
        .freshProgressSurface(line: hairline)
    }

    private func maxSessionsPerWeek(_ plan: TrainingPlan) -> Int {
        plan.weeks.map {
            $0.days.reduce(0) { result, day in
                result + day.sessions.count
            }
        }.max() ?? 0
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 23, weight: .regular, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

// General progress is deliberately independent of any active training plan.
// All figures come from recorded completed workouts, not planned sessions.
private struct ATHLTHTrainGeneralProgressContent: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    @State private var exerciseID = ""
    @State private var period: TimePeriod = .all

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let muted = Color(red: 0.46, green: 0.45, blue: 0.43)
    private let champagne = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let hairline = Color(red: 0.89, green: 0.87, blue: 0.84)

    private enum TimePeriod: String, CaseIterable, Identifiable {
        case fourWeeks
        case twelveWeeks
        case all

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fourWeeks:
                return ATHLTHLocalization.choose(
                    english: "4 weeks", norwegian: "4 uker"
                )
            case .twelveWeeks:
                return ATHLTHLocalization.choose(
                    english: "12 weeks", norwegian: "12 uker"
                )
            case .all:
                return ATHLTHLocalization.choose(
                    english: "All time", norwegian: "Alle"
                )
            }
        }

        var earliestDate: Date {
            switch self {
            case .fourWeeks:
                return Calendar.current.date(
                    byAdding: .day, value: -28, to: .now
                ) ?? .distantPast
            case .twelveWeeks:
                return Calendar.current.date(
                    byAdding: .day, value: -84, to: .now
                ) ?? .distantPast
            case .all:
                return .distantPast
            }
        }
    }

    private var snapshot: ATHLTHTrainTrendEngine.Snapshot {
        ATHLTHTrainTrendEngine.makeGeneral(
            strengthHistory: strength.workoutHistory
        )
    }

    private var weightedExercises: [ATHLTHTrainTrendEngine.Exercise] {
        snapshot.exercises.filter { exercise in
            snapshot.points(for: exercise.id).contains {
                ($0.peakWeightKilograms ?? 0) > 0
            }
        }
    }

    private var selectedExercise: ATHLTHTrainTrendEngine.Exercise? {
        weightedExercises.first { $0.id == exerciseID }
            ?? weightedExercises.first
    }

    private var points: [ATHLTHTrainTrendEngine.Point] {
        guard let selectedExercise else { return [] }
        return snapshot.points(for: selectedExercise.id).filter {
            $0.date >= period.earliestDate &&
            ($0.peakWeightKilograms ?? 0) > 0
        }
    }

    private var maximumWeight: Double {
        points.compactMap(\.peakWeightKilograms).max() ?? 0
    }

    private var changeFromFirst: Double? {
        guard points.count > 1,
              let first = points.first?.peakWeightKilograms,
              let last = points.last?.peakWeightKilograms
        else { return nil }
        return last - first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("ALL YOUR TRAINING", "ALL DIN TRENING"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(champagne)

                Text(tr("Progress beyond the plan", "Fremgang utover planen"))
                    .font(.system(size: 25, weight: .regular, design: .serif))
                    .foregroundStyle(ink)

                Text(tr(
                    "Track your recorded strength workouts and exercise loads, whether you used a plan or Quick Train.",
                    "Følg utviklingen i styrkeøktene dine – både fra treningsplaner og Quick Train."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            }

            HStack(spacing: 8) {
                summaryStat(
                    value: "\(snapshot.linkedWorkoutCount)",
                    title: tr("Strength workouts", "Styrkeøkter"),
                    icon: "dumbbell.fill"
                )
                summaryStat(
                    value: "\(weightedExercises.count)",
                    title: tr("Weighted exercises", "Vektøvelser"),
                    icon: "chart.xyaxis.line"
                )
                summaryStat(
                    value: "\(health.workouts.count)",
                    title: tr("Apple Health workouts", "Health-økter"),
                    icon: "heart.text.square"
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("WEIGHT PROGRESSION", "VEKTUTVIKLING"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(champagne)
                    Spacer(minLength: 5)
                    Text(tr("Max working weight · kg", "Tyngste arbeidsvekt · kg"))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }

                if weightedExercises.isEmpty {
                    VStack(spacing: 11) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(champagne)
                        Text(tr(
                            "No recorded weighted exercises yet",
                            "Ingen registrerte vektøvelser ennå"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        Text(tr(
                            "Complete a strength workout with weighted working sets. Your exercise history will appear here automatically.",
                            "Fullfør en styrkeøkt med registrerte arbeidssett og vekt. Da kommer utviklingen automatisk hit."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Exercise", "Øvelse"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(muted)
                        Picker(
                            tr("Choose exercise", "Velg øvelse"),
                            selection: Binding(
                                get: { selectedExercise?.id ?? "" },
                                set: { exerciseID = $0 }
                            )
                        ) {
                            ForEach(weightedExercises) { exercise in
                                Text(exercise.title).tag(exercise.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 45)
                        .background(
                            Color.white.opacity(0.88),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                            .stroke(hairline, lineWidth: 0.7)
                        }
                    }

                    Picker(
                        tr("Period", "Periode"),
                        selection: $period
                    ) {
                        ForEach(TimePeriod.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)

                    if points.isEmpty {
                        Text(tr(
                            "No completed sets with weight during this period.",
                            "Ingen fullførte sett med vekt i denne perioden."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tr("PERSONAL BEST IN PERIOD", "BESTE VEKT I PERIODEN"))
                                    .font(.system(size: 9, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(muted)
                                Text(
                                    maximumWeight.formatted(
                                        .number.precision(.fractionLength(0...1))
                                    ) + " kg"
                                )
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink)
                            }
                            Spacer()
                            if let changeFromFirst {
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(tr("CHANGE", "ENDRING"))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(muted)
                                    Text(
                                        (changeFromFirst > 0 ? "+" : "") +
                                        changeFromFirst.formatted(
                                            .number.precision(.fractionLength(0...1))
                                        ) + " kg"
                                    )
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(
                                        changeFromFirst >= 0
                                            ? Color(red: 0.28, green: 0.53, blue: 0.43)
                                            : ink
                                    )
                                }
                            }
                        }

                        Chart {
                            ForEach(points) { point in
                                if let weight = point.peakWeightKilograms {
                                    LineMark(
                                        x: .value("Dato", point.date),
                                        y: .value("Vekt", weight)
                                    )
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(champagne)

                                    PointMark(
                                        x: .value("Dato", point.date),
                                        y: .value("Vekt", weight)
                                    )
                                    .foregroundStyle(champagne)
                                    .symbolSize(46)
                                }
                            }
                        }
                        .chartYScale(domain: 0...max(1, maximumWeight * 1.15))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisGridLine(
                                    stroke: StrokeStyle(lineWidth: 0.5)
                                )
                                AxisValueLabel(
                                    format: .dateTime.day().month(.abbreviated)
                                )
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisGridLine(
                                    stroke: StrokeStyle(lineWidth: 0.5)
                                )
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 218)

                        Text(tr(
                            "Each point is the heaviest completed working-set load for that exercise on that day.",
                            "Hvert punkt viser tyngste fullførte arbeidsvekt for øvelsen den dagen."
                        ))
                        .font(.caption2)
                        .foregroundStyle(muted)
                    }
                }
            }
            .padding(16)
            .freshProgressSurface(line: hairline)

            if let selectedExercise, !points.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("RECENT RESULTS", "SISTE RESULTATER"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(champagne)
                    ForEach(Array(points.suffix(5).reversed())) { point in
                        HStack(spacing: 10) {
                            Image(systemName: "dumbbell.fill")
                                .font(.caption)
                                .foregroundStyle(champagne)
                            Text(selectedExercise.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                            Spacer(minLength: 3)
                            Text(point.date.formatted(
                                date: .abbreviated,
                                time: .omitted
                            ))
                            .font(.caption2)
                            .foregroundStyle(muted)
                            if let weight = point.peakWeightKilograms {
                                Text(
                                    weight.formatted(
                                        .number.precision(.fractionLength(0...1))
                                    ) + " kg"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                                .monospacedDigit()
                            }
                        }
                    }
                }
                .padding(15)
                .freshProgressSurface(line: hairline)
            }

            Label(
                tr(
                    "The strength graph uses ATHLTH workout logs. Apple Health-only workouts are counted separately and cannot supply exercise weights.",
                    "Styrkegrafen bruker ATHLTHs øktlogg. Økter kun fra Apple Health telles separat og inneholder ikke øvelsesvekter her."
                ),
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryStat(
        value: String,
        title: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(champagne)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 110, alignment: .topLeading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 0.8)
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

private extension View {
    func freshProgressSurface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(line, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.03), radius: 9, y: 4)
    }
}
