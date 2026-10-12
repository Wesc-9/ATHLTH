import SwiftUI

/// Registered measurements on plan-linked sessions only.
/// Displays paired totals: never compares a complete plan budget with
/// the incomplete measurements of a subset of workouts.
struct ATHLTHPlanRecordedMetricsView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let plan: TrainingPlan
    let onSelectWeek: (UUID) -> Void
    @State private var showAllWeeks = false

    var body: some View {
        let report = ATHLTHPlanRecordedMetrics.inspect(
            plan: plan,
            store: session,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let comparableWeeks = report.comparableWeeks

        ATHLTHPlanSurface {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(ATHLTHPlanDesign.accent)
                    .font(.system(size: 20, weight: .medium))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "Target vs recorded",
                        norwegian: "Mål mot registrert"
                    ))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(ATHLTHLocalization.choose(
                        english: "Only workouts with both a planned target and a linked measurement are compared. Manually completed sessions without measurements are not estimated.",
                        norwegian: "Bare økter med både planlagt mål og koblet måling sammenlignes. Manuelt fullførte økter uten måledata blir ikke anslått."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !report.hasComparisons {
                Label(
                    ATHLTHLocalization.choose(
                        english: "No directly comparable measurements yet. Complete a planned workout and link the recording to see comparisons.",
                        norwegian: "Ingen direkte sammenlignbare målinger ennå. Gjennomfør en planlagt økt og knytt registreringen til den for å se tall."
                    ),
                    systemImage: "info.circle"
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                metrics(report.runningMinutes,
                        title: ATHLTHLocalization.choose(
                            english: "Running time", norwegian: "Løpetid"
                        ),
                        unit: "min",
                        decimals: 0)
                metrics(report.strengthMinutes,
                        title: ATHLTHLocalization.choose(
                            english: "Strength time", norwegian: "Styrketid"
                        ),
                        unit: "min",
                        decimals: 0)
                metrics(report.runningKilometers,
                        title: ATHLTHLocalization.choose(
                            english: "Running distance", norwegian: "Løpedistanse"
                        ),
                        unit: "km",
                        decimals: 1)

                Text(ATHLTHLocalization.choose(
                    english: "Measured duration can include pauses, depending on the recording source. These differences are descriptive, not training-load or recovery scores.",
                    norwegian: "Registrert varighet kan inkludere pauser, avhengig av datakilden. Forskjellene beskriver gjennomføringen, ikke treningsbelastning eller restitusjon."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(Array(comparableWeeks.prefix(
                        showAllWeeks ? comparableWeeks.count : 5
                    ))) { week in
                        if week.runningMinutes.sessions > 0 ||
                            week.strengthMinutes.sessions > 0 ||
                            week.runningKilometers.sessions > 0 {
                            Button {
                                onSelectWeek(week.id)
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "W\(week.number)",
                                        norwegian: "U\(week.number)"
                                    ))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                    .frame(width: 34, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        weekLine(week.runningMinutes,
                                                 name: ATHLTHLocalization.choose(
                                                    english: "Run",
                                                    norwegian: "Løp"
                                                 ),
                                                 unit: "min", decimals: 0)
                                        weekLine(week.strengthMinutes,
                                                 name: ATHLTHLocalization.choose(
                                                    english: "Strength",
                                                    norwegian: "Styrke"
                                                 ),
                                                 unit: "min", decimals: 0)
                                        weekLine(week.runningKilometers,
                                                 name: ATHLTHLocalization.choose(
                                                    english: "Distance",
                                                    norwegian: "Distanse"
                                                 ),
                                                 unit: "km", decimals: 1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        .accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if comparableWeeks.count > 5 {
                    Button {
                        showAllWeeks.toggle()
                    } label: {
                        Label(
                            showAllWeeks
                                ? ATHLTHLocalization.choose(
                                    english: "Show fewer weeks", norwegian: "Vis færre uker"
                                )
                                : ATHLTHLocalization.choose(
                                    english: "Show all weeks", norwegian: "Vis alle ukene"
                                ),
                            systemImage: showAllWeeks ? "chevron.up" : "chevron.down"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private func metrics(
        _ pair: ATHLTHPlanRecordedMetrics.Paired,
        title: String,
        unit: String,
        decimals: Int
    ) -> some View {
        if pair.sessions > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Spacer(minLength: 0)
                    Text("\(pair.sessions) " +
                        ATHLTHLocalization.choose(
                            english: "matched sessions",
                            norwegian: "sammenlignbare økter"
                        ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                HStack(spacing: 9) {
                    value(pair.planned, decimals: decimals)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .accessibilityHidden(true)
                    value(pair.actual, decimals: decimals)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ATHLTHLocalization.choose(
                        english: "Planned → recorded",
                        norwegian: "Planlagt → registrert"
                    ))
                    Spacer(minLength: 0)
                    Text(ATHLTHLocalization.choose(
                        english: "Difference",
                        norwegian: "Differanse"
                    ) + ": " + signedValue(pair.difference, decimals: decimals) + " " + unit)
                    .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .padding(10)
            .background(
                ATHLTHPlanDesign.selectedSurface,
                in: RoundedRectangle(cornerRadius: ATHLTHPlanDesign.fieldRadius)
            )
        }
    }

    @ViewBuilder
    private func weekLine(
        _ pair: ATHLTHPlanRecordedMetrics.Paired,
        name: String,
        unit: String,
        decimals: Int
    ) -> some View {
        if pair.sessions > 0 {
            Text("\(name): \(formatted(pair.planned, decimals: decimals)) → " +
                 "\(formatted(pair.actual, decimals: decimals)) \(unit)" +
                 " · \(pair.sessions) " +
                 ATHLTHLocalization.choose(english: "sessions", norwegian: "økter"))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .multilineTextAlignment(.leading)
        }
    }

    private func value(_ number: Double, decimals: Int) -> some View {
        Text(formatted(number, decimals: decimals))
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(ATHLTHPlanDesign.ink)
    }

    private func formatted(_ number: Double, decimals: Int) -> String {
        number.formatted(.number.precision(.fractionLength(decimals)))
    }

    private func signedValue(_ number: Double, decimals: Int) -> String {
        // Avoid showing -0 from floating-point rounding.
        let factor = pow(10.0, Double(decimals))
        let rounded = (number * factor).rounded() / factor
        let prefix = rounded > 0 ? "+" : ""
        return prefix + formatted(rounded, decimals: decimals)
    }
}
