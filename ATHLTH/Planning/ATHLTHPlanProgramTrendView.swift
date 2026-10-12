import SwiftUI

/// A compact, navigable overview of the *planned* program. All metrics come
/// from ATHLTHPlanProgramTrendAdvisor, not a separate UI calculation.
struct ATHLTHPlanProgramTrendView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let plan: TrainingPlan
    let onSelectWeek: (UUID) -> Void
    @State private var showsAllWeeks = false

    var body: some View {
        let report = ATHLTHPlanProgramTrendAdvisor.inspect(plan)
        let actual = ATHLTHPlanActualProgress.inspect(
            plan: plan,
            store: session,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )

        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH / PROGRAM")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHPlanDesign.accent)

                Text(ATHLTHLocalization.choose(
                    english: "Program trajectory",
                    norwegian: "Utvikling gjennom programmet"
                ))
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)

                Text(ATHLTHLocalization.choose(
                    english: "Planned workouts and confirmed or manually marked completion by week. Not a measure of exercise intensity or recovery.",
                    norwegian: "Planlagte økter og registrert eller manuelt markert gjennomføring per uke. Ikke et mål på intensitet eller restitusjon."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                metric(
                    value: report.totalRuns,
                    title: ATHLTHLocalization.choose(english: "Runs", norwegian: "Løp")
                )
                metric(
                    value: report.totalStrength,
                    title: ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
                )
                metric(
                    value: report.totalOther,
                    title: ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")
                )
                Spacer(minLength: 0)
            }

            if actual.totalPlanned > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(actual.totalCompleted) / \(actual.totalPlanned)")
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "completed or marked",
                            norwegian: "registrert eller markert fullført"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        Spacer(minLength: 0)
                    }
                    ProgressView(
                        value: Double(actual.totalCompleted),
                        total: Double(max(actual.totalPlanned, 1))
                    )
                    .tint(ATHLTHPlanDesign.accent)
                    Text(ATHLTHLocalization.choose(
                        english: "\(actual.totalRecorded) linked recordings · \(actual.totalManuallyMarked) manually marked · \(actual.totalSkipped) skipped. Future sessions remain planned, not missed.",
                        norwegian: "\(actual.totalRecorded) registrerte økter · \(actual.totalManuallyMarked) manuelt markert · \(actual.totalSkipped) hoppet over. Fremtidige økter er planlagt, ikke mislykket."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius)
                )
            }

            if report.weeks.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Add a training week to see the trajectory.",
                    norwegian: "Legg til en treningsuke for å se utviklingen."
                ))
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                HStack(spacing: 11) {
                    legend(
                        ATHLTHLocalization.choose(english: "Running", norwegian: "Løping"),
                        color: ATHLTHPlanDesign.accent
                    )
                    legend(
                        ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke"),
                        color: ATHLTHTheme.accentDeep
                    )
                    if report.totalOther > 0 {
                        legend(
                            ATHLTHLocalization.choose(english: "Other", norwegian: "Annet"),
                            color: ATHLTHPlanDesign.secondaryInk.opacity(0.28)
                        )
                    }
                }

                VStack(spacing: 8) {
                    ForEach(Array(report.weeks.prefix(
                        showsAllWeeks ? report.weeks.count : 6
                    ))) { week in
                        Button {
                            onSelectWeek(week.id)
                        } label: {
                            HStack(spacing: 10) {
                                Text(ATHLTHLocalization.choose(
                                    english: "W\(week.number)",
                                    norwegian: "U\(week.number)"
                                ))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .frame(width: 31, alignment: .leading)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text("\(week.sessionCount) " +
                                            ATHLTHLocalization.choose(
                                                english: "workouts", norwegian: "økter"
                                            ))
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(ATHLTHPlanDesign.ink)

                                        if week.deload {
                                            Text(ATHLTHLocalization.choose(
                                                english: "Deload", norwegian: "Lett uke"
                                            ))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(ATHLTHTheme.accentDeep)
                                        }
                                        Spacer(minLength: 0)
                                        Text(changeLabel(week.comparison))
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    }

                                    GeometryReader { geometry in
                                        HStack(spacing: 0) {
                                            segment(
                                                count: week.running,
                                                total: report.maximumWeekSessions,
                                                width: geometry.size.width,
                                                color: ATHLTHPlanDesign.accent
                                            )
                                            segment(
                                                count: week.strength,
                                                total: report.maximumWeekSessions,
                                                width: geometry.size.width,
                                                color: ATHLTHTheme.accentDeep
                                            )
                                            segment(
                                                count: week.other,
                                                total: report.maximumWeekSessions,
                                                width: geometry.size.width,
                                                color: ATHLTHPlanDesign.secondaryInk.opacity(0.28)
                                            )
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .frame(height: 7)
                                    .background(
                                        ATHLTHPlanDesign.selectedSurface,
                                        in: Capsule()
                                    )

                                    if let finished = actual.week(id: week.id),
                                       finished.planned > 0 {
                                        HStack(spacing: 5) {
                                            Image(systemName: "checkmark.circle")
                                                .font(.caption2)
                                                .accessibilityHidden(true)
                                            Text("\(finished.completed)/\(finished.planned) " +
                                                ATHLTHLocalization.choose(
                                                    english: "completed", norwegian: "fullført"
                                                ))
                                            if finished.skipped > 0 {
                                                Text("· \(finished.skipped) " +
                                                    ATHLTHLocalization.choose(
                                                        english: "skipped", norwegian: "hoppet over"
                                                    ))
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .font(.caption2.weight(.medium))
                                        .monospacedDigit()
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    }

                                    HStack(spacing: 8) {
                                        if let minutes = week.plannedMinutes,
                                           week.sessionCount > 0 {
                                            Text("\(minutes) min")
                                        } else if week.sessionCount > 0 {
                                            Text(ATHLTHLocalization.choose(
                                                english: "Duration incomplete",
                                                norwegian: "Tid ikke komplett"
                                            ))
                                        }
                                        if let distance = week.plannedRunKilometers,
                                           week.running > 0 {
                                            Text("\(distance.formatted(.number.precision(.fractionLength(1)))) km")
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                         .accessibilityLabel(
                            weekAccessibilityLabel(week, actual: actual.week(id: week.id))
                        )
                        .accessibilityHint(ATHLTHLocalization.choose(
                            english: "Open week details", norwegian: "Åpne detaljer for uken"
                        ))
                    }
                }

                if report.weeks.count > 6 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsAllWeeks.toggle()
                        }
                    } label: {
                        Label(
                            showsAllWeeks
                                ? ATHLTHLocalization.choose(
                                    english: "Show fewer weeks", norwegian: "Vis færre uker"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Show all \(report.weeks.count) weeks",
                                    norwegian: "Vis alle \(report.weeks.count) ukene"
                                ),
                            systemImage: showsAllWeeks ? "chevron.up" : "chevron.down"
                        )
                        .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }

                if report.weeksWithUnknownTime > 0 {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Total planned time cannot be compared reliably: duration is missing in \(report.weeksWithUnknownTime) weeks.",
                            norwegian: "Samlet planlagt tid kan ikke sammenlignes sikkert: \(report.weeksWithUnknownTime) uker mangler varighet på én eller flere økter."
                        ),
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let increase = report.largestIncrease,
                   increase >= 2 {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "The largest week-to-week jump is +\(increase) workouts. Review the session types and your available time before making changes.",
                            norwegian: "Største økning fra én uke til neste er +\(increase) økter. Kontroller økttypene og tilgjengelig tid før du gjør endringer."
                        ),
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func metric(value: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
    }

    private func segment(
        count: Int, total: Int, width: CGFloat, color: Color
    ) -> some View {
        Capsule()
            .fill(color)
            .frame(width: max(0, width * CGFloat(count) / CGFloat(total)))
    }

    private func changeLabel(
        _ comparison: ATHLTHPlanProgramTrendAdvisor.Comparison?
    ) -> String {
        switch comparison {
        case .higher(let increase): return "+\(increase)"
        case .lower(let decrease): return "−\(decrease)"
        case .unchanged: return "±0"
        case .noBaseline, .none: return "—"
        }
    }

    private func weekAccessibilityLabel(
        _ week: ATHLTHPlanProgramTrendAdvisor.Week,
        actual: ATHLTHPlanActualProgress.Week?
    ) -> String {
        let prefix = ATHLTHLocalization.choose(
            english: "Week \(week.number), \(week.running) runs, \(week.strength) strength, \(week.other) other workouts",
            norwegian: "Uke \(week.number), \(week.running) løpeøkter, \(week.strength) styrkeøkter, \(week.other) andre økter"
        )
        guard let actual else { return prefix }
        return prefix + ". " + ATHLTHLocalization.choose(
            english: "\(actual.completed) completed of \(actual.planned), \(actual.skipped) skipped",
            norwegian: "\(actual.completed) av \(actual.planned) fullført, \(actual.skipped) hoppet over"
        )
    }
}
