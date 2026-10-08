import SwiftUI

/// Opened on demand, so the planner never has to compute strength history
/// while the athlete scrolls through days and workouts.
struct TrainingPlanProgressDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var health: HealthKitManager

    let planID: UUID

    @State private var showAllMuscles = false
    @State private var showAllWeeks = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = session.trainingPlan(withID: planID) {
                    let overall = session.trainingPlanProgress(
                        plan,
                        healthWorkouts: health.workouts,
                        strengthHistory: strength.workoutHistory
                    )
                    let report = TrainingPlanStrengthReport.make(
                        plan: plan,
                        strengthHistory: strength.workoutHistory
                    )

                    LazyVStack(alignment: .leading, spacing: 16) {
                        header(plan: plan)
                        overallCard(overall)
                        strengthCard(report)
                        muscleCard(report)
                        weeklyCard(report, currentWeek: overall.currentWeek)
                        sourceNote
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "Training plan unavailable",
                            norwegian: "Treningsplanen er ikke tilgjengelig"
                        ),
                        systemImage: "calendar.badge.exclamationmark"
                    )
                    .padding()
                }
            }
            .scrollIndicators(.hidden)
            .background(
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.accent.opacity(0.25)
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Plan progress",
                    norwegian: "Planprogresjon"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func header(plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                ATHLTHLocalization.choose(
                    english: "YOUR DEVELOPMENT",
                    norwegian: "DIN UTVIKLING"
                )
            )
            .font(.system(size: 10, weight: .bold))
            .tracking(1.7)
            .foregroundStyle(ATHLTHTheme.accentDeep)

            Text(plan.title)
                .font(.system(size: 29, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                ATHLTHLocalization.choose(
                    english: "See what you planned and what ATHLTH actually recorded.",
                    norwegian: "Se hva du planla, og hva ATHLTH faktisk har registrert."
                )
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overallCard(_ progress: TrainingPlanProgressSnapshot) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 13) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Program completion",
                        norwegian: "Gjennomføring av programmet"
                    ),
                    systemImage: "checkmark.circle"
                )
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(progress.completedSessions) / \(progress.totalSessions)")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text("\(Int((progress.completionFraction * 100).rounded())) %")
                        .font(.title3.bold())
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .monospacedDigit()
                }
                ProgressView(value: progress.completionFraction)
                    .tint(ATHLTHTheme.accent)

                HStack(spacing: 15) {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "\(progress.skippedSessions) skipped",
                            norwegian: "\(progress.skippedSessions) hoppet over"
                        ),
                        systemImage: "forward.fill"
                    )
                    Label(
                        ATHLTHLocalization.choose(
                            english: "\(progress.missed.count) missed",
                            norwegian: "\(progress.missed.count) ikke gjennomført"
                        ),
                        systemImage: "clock"
                    )
                }
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Includes confirmed workout matches and sessions manually marked as completed. Future workouts remain planned.",
                        norwegian: "Inkluderer bekreftede treningsøkter og økter som er markert fullført manuelt. Fremtidige økter forblir planlagt."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func strengthCard(_ report: TrainingPlanStrengthReport) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Recorded strength",
                        norwegian: "Registrert styrke"
                    ),
                    systemImage: "dumbbell.fill"
                )
                .font(.headline)
                .foregroundStyle(ATHLTHTheme.primaryText)

                HStack(spacing: 12) {
                    metric(
                        value: "\(report.loggedSessionCount)",
                        caption: ATHLTHLocalization.choose(
                            english: "Logged sessions",
                            norwegian: "Loggførte økter"
                        )
                    )
                    metric(
                        value: "\(report.totalPerformedStrengthSets)",
                        caption: ATHLTHLocalization.choose(
                            english: "Work sets",
                            norwegian: "Arbeidssett"
                        )
                    )
                    metric(
                        value: report.totalRecordedVolumeKilograms
                            .formatted(.number.precision(.fractionLength(0))) + " kg",
                        caption: ATHLTHLocalization.choose(
                            english: "Volume",
                            norwegian: "Volum"
                        )
                    )
                }
                Text(
                    ATHLTHLocalization.choose(
                        english: "Volume means recorded weight × reps. Timed sets, unloaded movements and warm-up sets are not assigned made-up kilogram values.",
                        norwegian: "Volum betyr registrert vekt × repetisjoner. Tidsbaserte sett, øvelser uten oppgitt vekt og oppvarmingssett får ikke beregnet kunstige kilo."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func muscleCard(_ report: TrainingPlanStrengthReport) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Muscle-group focus",
                        norwegian: "Muskelgrupper"
                    ),
                    systemImage: "figure.strengthtraining.traditional"
                )
                .font(.headline)

                if report.muscles.isEmpty {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Add exercises to your strength days to see the distribution.",
                            norwegian: "Legg til øvelser på styrkedagene for å se fordelingen."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    let visible = showAllMuscles
                        ? report.muscles
                        : Array(report.muscles.prefix(6))

                    ForEach(visible) { muscle in
                        muscleRow(muscle)
                    }

                    if report.muscles.count > 6 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllMuscles.toggle()
                            }
                        } label: {
                            Label(
                                showAllMuscles
                                    ? ATHLTHLocalization.choose(
                                        english: "Show fewer",
                                        norwegian: "Vis færre"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Show all muscles",
                                        norwegian: "Vis alle muskelgrupper"
                                    ),
                                systemImage: showAllMuscles
                                    ? "chevron.up" : "chevron.down"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                }

                Text(
                    ATHLTHLocalization.choose(
                        english: "Primary muscle groups only. One compound exercise may count toward several muscles; this is a set distribution, not a measure of muscle growth.",
                        norwegian: "Kun primære muskelgrupper. Én sammensatt øvelse kan telle på flere muskler. Dette viser settfordeling, ikke målt muskelvekst."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func muscleRow(_ muscle: TrainingPlanStrengthReport.Muscle) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(muscle.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(
                    ATHLTHLocalization.choose(
                        english: "\(muscle.plannedWorkingSets) planned · \(muscle.performedWorkingSets) logged",
                        norwegian: "\(muscle.plannedWorkingSets) planlagt · \(muscle.performedWorkingSets) registrert"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            GeometryReader { geometry in
                let total = max(muscle.plannedWorkingSets, muscle.performedWorkingSets, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ATHLTHTheme.accent.opacity(0.12))
                    Capsule()
                        .fill(ATHLTHTheme.accentDeep.opacity(0.48))
                        .frame(
                            width: geometry.size.width
                                * CGFloat(muscle.plannedWorkingSets)
                                / CGFloat(total)
                        )
                    Capsule()
                        .fill(ATHLTHTheme.vitality)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(muscle.performedWorkingSets)
                                / CGFloat(total)
                        )
                        .frame(height: 4)
                }
            }
            .frame(height: 8)
        }
    }

    private func weeklyCard(
        _ report: TrainingPlanStrengthReport,
        currentWeek: Int
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Week-by-week",
                        norwegian: "Uke for uke"
                    ),
                    systemImage: "calendar"
                )
                .font(.headline)

                let visible = showAllWeeks
                    ? report.weeks
                    : Array(report.weeks.prefix(8))

                ForEach(visible) { week in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Week \(week.number)",
                                        norwegian: "Uke \(week.number)"
                                    )
                                )
                                .font(.subheadline.weight(.semibold))
                                if week.number == currentWeek {
                                    Circle()
                                        .fill(ATHLTHTheme.accentDeep)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "\(week.plannedSessions) sessions planned · \(week.loggedStrengthSessions) strength sessions logged",
                                    norwegian: "\(week.plannedSessions) økter planlagt · \(week.loggedStrengthSessions) styrkeøkter loggført"
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(week.performedWorkingSets) / \(week.plannedWorkingSets)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Logged / planned sets",
                                    norwegian: "Logget / planlagte sett"
                                )
                            )
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if week.id != visible.last?.id {
                        Divider().opacity(0.4)
                    }
                }

                if report.weeks.count > 8 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllWeeks.toggle()
                        }
                    } label: {
                        Label(
                            showAllWeeks
                                ? ATHLTHLocalization.choose(
                                    english: "Show fewer weeks",
                                    norwegian: "Vis færre uker"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Show all weeks",
                                    norwegian: "Vis alle uker"
                                ),
                            systemImage: showAllWeeks
                                ? "chevron.up" : "chevron.down"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }
        }
    }

    private func metric(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceNote: some View {
        Text(
            ATHLTHLocalization.choose(
                english: "Detailed sets and volume are based only on completed ATHLTH strength logs explicitly linked to this plan. Apple Health and manually completed sessions can count toward overall completion, but cannot provide exercise-level numbers here.",
                norwegian: "Detaljerte sett og volum hentes bare fra fullførte ATHLTH-styrkelogger som er knyttet direkte til planen. Apple Health og manuelt fullførte økter kan telle i total fremdrift, men gir ikke øvelsesdetaljer her."
            )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}
