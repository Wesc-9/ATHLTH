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

/// The same translucent segmented selector used by Train Today,
/// compressed slightly to fit four Insights destinations on iPhone.
struct ATHLTHInsightsNavigation: View {
    @Binding var selection: ATHLTHInsightsSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 1) {
            ForEach(ATHLTHInsightsSection.allCases) { section in
                let active = selection == section
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        selection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.system(size: 11,
                                      weight: active ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .foregroundStyle(active ? ATHLTHInsightsStyle.ink :
                                         ATHLTHInsightsStyle.ink.opacity(0.76))
                        .padding(.horizontal, 7)
                        .frame(minHeight: 43)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 12,
                                                style: .continuous)
                                    .fill(Color.white.opacity(0.96))
                                    .shadow(color: .black.opacity(0.07), radius: 3, y: 2)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.78), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Insights sections", norwegian: "Innsiktfaner"))
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

/// Relative recorded muscle activation during the last 28 days.
/// The busiest logged region is 100%, never an injury or recovery estimate.
struct ATHLTHInsightsMuscleFocus: Identifiable {
    let region: StrengthMuscleRegion
    let percentage: Int
    let score: Double
    let needsLoadBalanceAttention: Bool
    var id: StrengthMuscleRegion { region }
}

enum ATHLTHInsightsMuscleRanking {
    static func all(_ summary: ATHLTHInsightsMuscleSummary) -> [ATHLTHInsightsMuscleFocus] {
        let ordered = summary.profile.activations
            .filter { $0.score.isFinite && $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.region.rawValue < $1.region.rawValue
                }
                return $0.score > $1.score
            }
        guard let peak = ordered.first?.score, peak > 0 else { return [] }
        // Require a meaningful comparison across at least three regions and
        // three recorded sessions before signaling a concentration in red.
        // A relative percentile alone never establishes fatigue/injury risk.
        let hasComparison = ordered.count >= 3 && summary.sessionCount >= 3
        return ordered.map { item in
            let share = min(max(item.score / peak, 0), 1)
            return ATHLTHInsightsMuscleFocus(
                region: item.region,
                percentage: Int((share * 100).rounded()),
                score: item.score,
                needsLoadBalanceAttention: hasComparison && share >= 0.85
            )
        }
    }

    static func extremes(_ summary: ATHLTHInsightsMuscleSummary)
        -> (most: [ATHLTHInsightsMuscleFocus], least: [ATHLTHInsightsMuscleFocus]) {
        let sorted = all(summary)
        let high = Array(sorted.prefix(2))
        let highRegions = Set(high.map(\.region))
        let low = Array(sorted.reversed().filter {
            !highRegions.contains($0.region)
        }.prefix(2))
        return (high, low)
    }
}

struct ATHLTHInsightsMuscleCard: View {
    let summary: ATHLTHInsightsMuscleSummary
    @State private var showAllMuscles = false

    private let concentrated = Color(red: 0.79, green: 0.29, blue: 0.26)
    private let active = Color(red: 0.66, green: 0.50, blue: 0.32)
    private let elevated = Color(red: 0.86, green: 0.52, blue: 0.22)

    private var allMuscles: [ATHLTHInsightsMuscleFocus] {
        ATHLTHInsightsMuscleRanking.all(summary)
    }

    private var focus: (most: [ATHLTHInsightsMuscleFocus],
                        least: [ATHLTHInsightsMuscleFocus]) {
        ATHLTHInsightsMuscleRanking.extremes(summary)
    }

    private func tint(for muscle: ATHLTHInsightsMuscleFocus) -> Color {
        if muscle.needsLoadBalanceAttention { return concentrated }
        return muscle.percentage >= 60 ? elevated : active
    }

    private var atlasTints: [StrengthMuscleRegion: Color] {
        Dictionary(uniqueKeysWithValues: allMuscles.map {
            ($0.region, tint(for: $0))
        })
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

            if allMuscles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    StrengthMuscleMapView(
                        profile: .empty, compact: true, style: .activation,
                        presentation: .insight,
                        activationTint: ATHLTHInsightsStyle.accent
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 188)
                    Text(ATHLTHLocalization.choose(
                        english: "Muscle balance appears after completed strength sessions with recorded muscle metadata.",
                        norwegian: "Muskelbalansen vises etter fullførte styrkeøkter med registrerte muskelgrupper."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHInsightsStyle.muted)
                }
                .padding(.vertical, 22)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    StrengthMuscleMapView(
                        // Show every logged region, not just the four summaries.
                        profile: summary.profile,
                        compact: true,
                        style: .activation,
                        presentation: .insight,
                        activationTint: active,
                        regionTints: atlasTints
                    )
                    .frame(width: 144, height: 228)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "All logged muscles, colored by relative training concentration",
                        norwegian: "Alle registrerte muskler, farget etter relativ treningsandel"
                    ))

                    VStack(alignment: .leading, spacing: 13) {
                        rankingSection(
                            title: ATHLTHLocalization.choose(
                                english: "MOST TRAINED", norwegian: "MEST TRENT"
                            ),
                            rows: focus.most
                        )
                        if !focus.least.isEmpty {
                            rankingSection(
                                title: ATHLTHLocalization.choose(
                                    english: "LEAST TRAINED", norwegian: "MINST TRENT"
                                ),
                                rows: focus.least
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 5) {
                    Circle().fill(active).frame(width: 7, height: 7)
                    Text(ATHLTHLocalization.choose(
                        english: "Used", norwegian: "Brukt"))
                    Circle().fill(elevated).frame(width: 7, height: 7)
                    Text(ATHLTHLocalization.choose(
                        english: "High", norwegian: "Høyt"))
                    Circle().fill(concentrated).frame(width: 7, height: 7)
                    Text(ATHLTHLocalization.choose(
                        english: "Relative emphasis", norwegian: "Relativt mye"))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ATHLTHInsightsStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

                DisclosureGroup(isExpanded: $showAllMuscles) {
                    VStack(spacing: 10) {
                        ForEach(allMuscles) { muscle in
                            muscleRow(muscle)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    HStack(spacing: 6) {
                        Text(ATHLTHLocalization.choose(
                            english: "All trained muscles", norwegian: "Alle trente muskler"))
                        Spacer(minLength: 0)
                        Text("\(allMuscles.count)")
                            .font(.caption.monospacedDigit())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHInsightsStyle.ink)
                }
                .tint(ATHLTHInsightsStyle.accent)
                .padding(12)
                .background(ATHLTHInsightsStyle.canvas,
                            in: RoundedRectangle(cornerRadius: 15))

                Text(ATHLTHLocalization.choose(
                    english: "Compared with the highest logged muscle activation (100%) across \(summary.sessionCount) strength sessions. Red means relatively concentrated training, NOT injury, fatigue or overtraining. Unrecorded regions stay neutral.",
                    norwegian: "Sammenlignet med mest registrert muskelaktivering (100 %) fra \(summary.sessionCount) styrkeøkter. Rødt viser relativt høy treningskonsentrasjon, IKKE skade, utmattelse eller overtrening. Uregistrerte muskler er nøytrale."
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
        title: String, rows: [ATHLTHInsightsMuscleFocus]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(ATHLTHInsightsStyle.muted)
            ForEach(rows) { muscle in
                muscleRow(muscle)
            }
        }
    }

    private func muscleRow(_ muscle: ATHLTHInsightsMuscleFocus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(muscle.region.activityDisplayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.77)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(muscle.percentage)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint(for: muscle))
            }
            GeometryReader { geometry in
                Capsule().fill(ATHLTHInsightsStyle.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint(for: muscle))
                            .frame(width: max(2, geometry.size.width *
                                CGFloat(muscle.percentage) / 100))
                    }
            }
            .frame(height: 5)
        }
        .foregroundStyle(ATHLTHInsightsStyle.ink)
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
