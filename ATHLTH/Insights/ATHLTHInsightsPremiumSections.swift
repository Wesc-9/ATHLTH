import SwiftUI
import Charts

enum ATHLTHInsightsStyle {
    static let ink = Color(red: 0.11, green: 0.13, blue: 0.16)
    static let muted = Color(red: 0.41, green: 0.43, blue: 0.46)
    static let accent = Color(red: 0.68, green: 0.53, blue: 0.34)
    static let subtleAccent = Color(red: 0.77, green: 0.77, blue: 0.72)
    static let track = Color(red: 0.92, green: 0.92, blue: 0.90)
    static let canvas = Color(red: 0.985, green: 0.984, blue: 0.977)
}

private struct ATHLTHInsightsSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24,
                                                        style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(ATHLTHInsightsStyle.track, lineWidth: 0.8)
            }
            .shadow(color: ATHLTHInsightsStyle.ink.opacity(0.035),
                    radius: 15, y: 5)
    }
}

extension View {
    func athlthInsightsSurface() -> some View {
        modifier(ATHLTHInsightsSurfaceModifier())
    }
}

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
                                        colors: [ATHLTHInsightsStyle.accent,
                                                 Color(red: 0.82, green: 0.71, blue: 0.51)],
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

/// Recorded training share, not a clinical fatigue or recovery percentage.
/// Only regions with positive evidence are ranked: missing data stays unknown.
struct ATHLTHInsightsMuscleFocus: Identifiable {
    let region: StrengthMuscleRegion
    let percentage: Int
    let score: Double
    var id: StrengthMuscleRegion { region }
}

enum ATHLTHInsightsMuscleRanking {
    static func extremes(_ summary: ATHLTHInsightsMuscleSummary)
        -> (most: [ATHLTHInsightsMuscleFocus], least: [ATHLTHInsightsMuscleFocus]) {
        let valid = summary.profile.activations.filter {
            $0.score.isFinite && $0.score > 0
        }
        let total = valid.reduce(0.0) { $0 + $1.score }
        guard total > 0 else { return ([], []) }
        let ordered = valid.sorted {
            if $0.score == $1.score { return $0.region.rawValue < $1.region.rawValue }
            return $0.score > $1.score
        }
        let count = min(2, ordered.count)
        let high = Array(ordered.prefix(count))
        let highIDs = Set(high.map(\.region))
        let low = Array(ordered.reversed().filter {
            !highIDs.contains($0.region)
        }.prefix(2))
        func focus(_ item: StrengthMuscleActivation) -> ATHLTHInsightsMuscleFocus {
            ATHLTHInsightsMuscleFocus(
                region: item.region,
                percentage: Int((100 * item.score / total).rounded()),
                score: item.score
            )
        }
        return (high.map(focus), low.map(focus))
    }
}

struct ATHLTHInsightsMuscleCard: View {
    let summary: ATHLTHInsightsMuscleSummary

    private var focus: (most: [ATHLTHInsightsMuscleFocus],
                        least: [ATHLTHInsightsMuscleFocus]) {
        ATHLTHInsightsMuscleRanking.extremes(summary)
    }

    private var highlightedProfile: StrengthMuscleProfile {
        let chosen = Set((focus.most + focus.least).map(\.region))
        return StrengthMuscleProfile(
            activations: summary.profile.activations.filter {
                chosen.contains($0.region)
            },
            primaryRegions: summary.profile.primaryRegions.intersection(chosen),
            secondaryRegions: summary.profile.secondaryRegions.intersection(chosen)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(ATHLTHLocalization.choose(
                    english: "Your muscle balance", norwegian: "Din muskelbalanse"
                ), systemImage: "figure.strengthtraining.traditional")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                Spacer(minLength: 3)
                Text(ATHLTHLocalization.choose(
                    english: "28 days", norwegian: "28 dager"
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            }

            if focus.most.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    StrengthMuscleMapView(
                        profile: .empty,
                        compact: true,
                        style: .activation,
                        presentation: .insight,
                        activationTint: ATHLTHInsightsStyle.accent
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 188)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "No recorded muscle activation",
                        norwegian: "Ingen registrert muskelaktivering"
                    ))
                    Text(ATHLTHLocalization.choose(
                        english: "Muscle balance appears after completed strength training with recorded muscle metadata.",
                        norwegian: "Muskelbalansen vises etter fullført styrketrening med registrerte muskelgrupper."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }
                .padding(.vertical, 22)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    StrengthMuscleMapView(
                        profile: highlightedProfile,
                        compact: true,
                        style: .activation,
                        presentation: .insight,
                        activationTint: ATHLTHInsightsStyle.accent
                    )
                    .frame(width: 144, height: 228)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "Highlighted most and least trained muscle groups",
                        norwegian: "Fremhever mest og minst trente muskelgrupper"
                    ))
                    VStack(alignment: .leading, spacing: 14) {
                        rankingSection(
                            title: ATHLTHLocalization.choose(
                                english: "MOST TRAINED", norwegian: "MEST TRENT"
                            ),
                            rows: focus.most,
                            accent: ATHLTHInsightsStyle.accent
                        )
                        if !focus.least.isEmpty {
                            rankingSection(
                                title: ATHLTHLocalization.choose(
                                    english: "LEAST TRAINED", norwegian: "MINST TRENT"
                                ),
                                rows: focus.least,
                                accent: ATHLTHInsightsStyle.subtleAccent
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(ATHLTHLocalization.choose(
                    english: "Share of recorded muscle activation across \(summary.sessionCount) strength sessions. Not muscle growth, fatigue or a medical measurement.",
                    norwegian: "Andel registrert muskelaktivering fra \(summary.sessionCount) styrkeøkter. Ikke muskelvekst, utmattelse eller en medisinsk måling."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .athlthInsightsSurface()
    }

    private func rankingSection(
        title: String,
        rows: [ATHLTHInsightsMuscleFocus],
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            ForEach(rows) { muscle in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(muscle.region.activityDisplayTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.77)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(muscle.percentage)%")
                            .font(.system(size: 13, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                    }
                    GeometryReader { geometry in
                        Capsule().fill(ATHLTHInsightsStyle.track)
                            .overlay(alignment: .leading) {
                                Capsule().fill(accent)
                                    .frame(width: max(2, geometry.size.width *
                                        CGFloat(muscle.percentage) / 100))
                            }
                    }
                    .frame(height: 5)
                }
                .foregroundStyle(ATHLTHInsightsStyle.ink)
            }
        }
    }
}

/// Only Apple Health workouts are counted: no duplicate counting of mirrored
/// ATHLTH sessions or fabricated load scores.
struct ATHLTHInsightsTrainingDay: Identifiable {
    let date: Date
    let minutes: Double
    let sessions: Int

    var id: Date { date }

    static func make(from workouts: [WorkoutSummary], at now: Date = Date()) -> [Self] {
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
