import SwiftUI
import Charts
import HealthKit

/// Insights uses the same editorial navigation and colors as Train.
/// The sections filter presentation only; none change health or workout data.
enum ATHLTHInsightsSection: String, CaseIterable, Identifiable {
    case overview, health, training, development

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return ATHLTHLocalization.choose(english: "Overview", norwegian: "Oversikt")
        case .health: return ATHLTHLocalization.choose(english: "Body & health", norwegian: "Kropp & helse")
        case .training: return ATHLTHLocalization.choose(english: "Training", norwegian: "Trening")
        case .development: return ATHLTHLocalization.choose(english: "Trends", norwegian: "Utvikling")
        }
    }
}

struct ATHLTHInsightsNavigation: View {
    @Binding var selection: ATHLTHInsightsSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ATHLTHInsightsSection.allCases) { section in
                let active = selection == section
                Button {
                    if reduceMotion {
                        selection = section
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = section
                        }
                    }
                } label: {
                    Text(section.title)
                        .font(.system(size: 11, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Color.white : ATHLTHTrainDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 2)
                        .background {
                            if active {
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [ATHLTHTrainDesign.bronze, ATHLTHTrainDesign.gold],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(5)
        .background(ATHLTHTrainDesign.paper, in: Capsule())
        .overlay { Capsule().strokeBorder(ATHLTHTrainDesign.rule.opacity(0.5), lineWidth: 0.7) }
        .shadow(color: ATHLTHTrainDesign.bronze.opacity(0.06), radius: 9, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ATHLTHLocalization.choose(english: "Insights sections", norwegian: "Innsiktfaner"))
    }
}

/// Aggregates completed, logged ATHLTH strength sessions once per history
/// publication. Never infers muscle training from unrelated Health workouts.
struct ATHLTHInsightsMuscleSummary {
    let profile: StrengthMuscleProfile
    let sessionCount: Int

    static let empty = ATHLTHInsightsMuscleSummary(profile: .empty, sessionCount: 0)

    static func make(from history: [StrengthWorkoutLog], at now: Date = Date()) -> Self {
        let cutoff = now.addingTimeInterval(-28 * 86_400)
        let sessions = history.filter {
            $0.isFinished && $0.startedAt >= cutoff && $0.startedAt <= now
        }
        guard !sessions.isEmpty else { return .empty }

        var values: [StrengthMuscleRegion: Double] = [:]
        var primary: Set<StrengthMuscleRegion> = []
        var secondary: Set<StrengthMuscleRegion> = []

        for workout in sessions {
            // Modern workout snapshots contain muscle metadata. Missing
            // legacy metadata is not invented from exercise names.
            let summary = StrengthMuscleProfileBuilder.make(workout: workout, library: [])
            for activation in summary.profile.activations {
                values[activation.region, default: 0] += activation.score
            }
            primary.formUnion(summary.profile.primaryRegions)
            secondary.formUnion(summary.profile.secondaryRegions)
        }

        let activations = values.map {
            StrengthMuscleActivation(region: $0.key, score: $0.value)
        }
        return ATHLTHInsightsMuscleSummary(
            profile: StrengthMuscleProfile(
                activations: activations,
                primaryRegions: primary,
                secondaryRegions: secondary
            ),
            sessionCount: sessions.count
        )
    }
}

struct ATHLTHInsightsMuscleCard: View {
    let summary: ATHLTHInsightsMuscleSummary
    private let palette = ATHLTHTrainDesign.self

    private var topMuscles: String {
        var seen: Set<String> = []
        let names = summary.profile.topActivations.compactMap { activation -> String? in
            let name = activation.region.activityDisplayTitle
            guard seen.insert(name).inserted else { return nil }
            return name
        }
        return names.prefix(4).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Label(ATHLTHLocalization.choose(
                    english: "Muscles trained", norwegian: "Muskler i bruk"
                ), systemImage: "figure.strengthtraining.traditional")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer(minLength: 4)
                Text(ATHLTHLocalization.choose(english: "Last 28 days", norwegian: "Siste 28 dager"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "dumbbell")
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Text("\(summary.sessionCount) " + ATHLTHLocalization.choose(
                    english: "completed strength workouts", norwegian: "fullførte styrkeøkter"
                ))
                .foregroundStyle(ATHLTHTrainDesign.secondary)
                .font(.caption)
            }

            StrengthMuscleMapView(
                profile: summary.profile,
                compact: false,
                style: .activation,
                presentation: .insight,
                activationTint: ATHLTHTrainDesign.gold
            )
            .frame(maxWidth: 470)
            .frame(height: 268)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [ATHLTHTrainDesign.paleGold.opacity(0.30), Color.white.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )

            if topMuscles.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Complete a strength session with recorded exercises to see your actual muscle distribution here.",
                    norwegian: "Fullfør en styrkeøkt med registrerte øvelser for å se hvilke muskler du faktisk har trent."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ATHLTHLocalization.choose(
                        english: "Main muscle groups", norwegian: "Mest trente muskelgrupper"
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    Text(topMuscles)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(ATHLTHLocalization.choose(
                    english: "Highlights reflect completed ATHLTH strength exercises with muscle data — not a measurement of muscle growth.",
                    norwegian: "Markeringene bygger på utførte styrkeøvelser med muskeldata, ikke målinger av muskelvekst."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
        .padding(18)
        .athlthTrainPaper()
    }
}

/// Only Apple Health workouts are counted: no duplicate counting of mirrored
/// ATHLTH sessions or fabricated load scores.
struct ATHLTHInsightsTrainingDay: Identifiable {
    let date: Date
    let minutes: Double
    let sessions: Int

    var id: Date { date }

    static func make(from workouts: [HKWorkout], at now: Date = Date()) -> [Self] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        var minutesByDay: [Date: Double] = [:]
        var countsByDay: [Date: Int] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            guard day >= start && day <= end else { continue }
            minutesByDay[day, default: 0] += max(0, workout.duration / 60)
            countsByDay[day, default: 0] += 1
        }
        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else {
                return nil
            }
            return Self(
                date: date,
                minutes: minutesByDay[date, default: 0],
                sessions: countsByDay[date, default: 0]
            )
        }
    }
}

struct ATHLTHInsightsTrainingWeekCard: View {
    let days: [ATHLTHInsightsTrainingDay]

    private var minutes: Int { Int(days.reduce(0) { $0 + $1.minutes }.rounded()) }
    private var sessions: Int { days.reduce(0) { $0 + $1.sessions } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(ATHLTHLocalization.choose(
                    english: "Training activity", norwegian: "Treningsaktivitet"
                ), systemImage: "chart.bar.xaxis")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Spacer()
                Text(ATHLTHLocalization.choose(english: "7 days", norwegian: "7 dager"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(minutes) min")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .monospacedDigit()
                Spacer()
                Text("\(sessions) " + ATHLTHLocalization.choose(
                    english: "workouts", norwegian: "økter"
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            }

            if sessions == 0 {
                Text(ATHLTHLocalization.choose(
                    english: "No Apple Health workouts recorded in the last seven days.",
                    norwegian: "Ingen økter registrert i Apple Health de siste sju dagene."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }

            Chart(days) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Minutes", day.minutes)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [ATHLTHTrainDesign.gold, ATHLTHTrainDesign.bronze],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(6)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: days.map(\.date)) {
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .frame(height: 154)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Daily training minutes over seven days",
                norwegian: "Daglige treningsminutter de siste sju dagene"
            ))

            Text(ATHLTHLocalization.choose(
                english: "Completed workouts in Apple Health. Training load is not inferred from duration alone.",
                norwegian: "Registrerte økter i Apple Health. Treningsbelastning beregnes ikke ut fra varighet alene."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHTrainDesign.secondary)
        }
        .padding(18)
        .athlthTrainPaper()
    }
}
