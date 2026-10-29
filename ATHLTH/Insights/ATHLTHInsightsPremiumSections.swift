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

/// Completed, muscle-attributed strength training is the only source of this
/// activity estimate. It is not a clinical assessment of muscle fatigue.
struct ATHLTHInsightsMuscleSummary {
    let profile: StrengthMuscleProfile
    let sessionCount: Int
    /// Time-weighted equivalent weekly muscle sets, over the last 28 days.
    var weeklyLoad: [StrengthMuscleRegion: Double] = [:]
    /// The preceding twelve weeks provide a personal reference when present.
    var previousWeeklyLoad: [StrengthMuscleRegion: Double] = [:]
    var reliableBaselineRegions: Set<StrengthMuscleRegion> = []

    static let empty = ATHLTHInsightsMuscleSummary(profile: .empty, sessionCount: 0)

    struct ActivityEstimate {
        let weeklyLoad: [StrengthMuscleRegion: Double]
        let previousWeeklyLoad: [StrengthMuscleRegion: Double]
        let reliableBaselineRegions: Set<StrengthMuscleRegion>
    }

    /// Half-life affects the age of the logged training, NOT tissue recovery.
    /// The denominator converts an exponentially weighted 28-day sum back
    /// into weekly-equivalent sets, rather than forcing the peak to 100%.
    static func estimateActivity(
        samples: [(date: Date, profile: StrengthMuscleProfile)],
        at now: Date
    ) -> ActivityEstimate {
        let recentDays = 28.0
        let previousDays = 84.0
        let halfLifeDays = 10.0
        let dailyDecay = log(2.0) / halfLifeDays
        let weeklyNormalization = (1 - exp(-dailyDecay * recentDays))
            / (dailyDecay * 7.0)

        var weighted: [StrengthMuscleRegion: Double] = [:]
        var previousTotal: [StrengthMuscleRegion: Double] = [:]
        var previousWeeks: [StrengthMuscleRegion: Set<Date>] = [:]
        var previousExposureCount: [StrengthMuscleRegion: Int] = [:]
        let calendar = Calendar.current

        for sample in samples {
            let ageDays = now.timeIntervalSince(sample.date) / 86_400
            guard ageDays >= 0, ageDays < recentDays + previousDays else {
                continue
            }
            for activation in sample.profile.activations {
                guard activation.score.isFinite, activation.score > 0 else {
                    continue
                }
                if ageDays < recentDays {
                    weighted[activation.region, default: 0] +=
                        activation.score * exp(-dailyDecay * ageDays)
                } else {
                    previousTotal[activation.region, default: 0] += activation.score
                    previousExposureCount[activation.region, default: 0] += 1
                    let weekStart = calendar.dateInterval(
                        of: .weekOfYear, for: sample.date
                    )?.start ?? calendar.startOfDay(for: sample.date)
                    previousWeeks[activation.region, default: []].insert(weekStart)
                }
            }
        }

        let reference = previousTotal.mapValues { $0 / (previousDays / 7.0) }
        let reliable = Set(reference.keys.filter { region in
            (previousExposureCount[region] ?? 0) >= 3 &&
                (previousWeeks[region]?.count ?? 0) >= 3
        })
        return ActivityEstimate(
            weeklyLoad: weighted.mapValues { $0 / weeklyNormalization },
            previousWeeklyLoad: reference,
            reliableBaselineRegions: reliable
        )
    }

    static func make(from history: [StrengthWorkoutLog], at now: Date = Date()) -> Self {
        let recentCutoff = now.addingTimeInterval(-28 * 86_400)
        let historyCutoff = now.addingTimeInterval(-112 * 86_400)
        // Incomplete, future and zero-working-set logs must not inflate the map.
        let usable = history.filter {
            $0.isFinished && $0.totalWorkingSets > 0 &&
                $0.startedAt >= historyCutoff && $0.startedAt <= now
        }

        var samples: [(date: Date, profile: StrengthMuscleProfile)] = []
        var values: [StrengthMuscleRegion: Double] = [:]
        var primary: Set<StrengthMuscleRegion> = []
        var secondary: Set<StrengthMuscleRegion> = []
        var recentCount = 0

        for workout in usable {
            let profile = StrengthMuscleProfileBuilder
                .make(
                    workout: workout,
                    library: [],
                    completedWorkingSetsOnly: true
                ).profile
            samples.append((date: workout.startedAt, profile: profile))
            guard workout.startedAt >= recentCutoff else { continue }
            recentCount += 1
            for activation in profile.activations
                where activation.score.isFinite && activation.score > 0 {
                values[activation.region, default: 0] += activation.score
            }
            primary.formUnion(profile.primaryRegions)
            secondary.formUnion(profile.secondaryRegions)
        }

        guard recentCount > 0 else { return .empty }
        let activity = estimateActivity(samples: samples, at: now)
        return ATHLTHInsightsMuscleSummary(
            profile: StrengthMuscleProfile(
                activations: values.map {
                    StrengthMuscleActivation(region: $0.key, score: $0.value)
                },
                primaryRegions: primary,
                secondaryRegions: secondary
            ),
            sessionCount: recentCount,
            weeklyLoad: activity.weeklyLoad,
            previousWeeklyLoad: activity.previousWeeklyLoad,
            reliableBaselineRegions: activity.reliableBaselineRegions
        )
    }
}

/// Percentage of a training-activity reference, NOT percent muscle exhaustion.
/// A conservative minimum reference protects sparse histories from exaggeration.
struct ATHLTHInsightsMuscleFocus: Identifiable {
    let region: StrengthMuscleRegion
    let percentage: Int
    let score: Double
    let needsLoadBalanceAttention: Bool
    var id: StrengthMuscleRegion { region }
}

enum ATHLTHInsightsMuscleRanking {
    /// Heuristic reference: 12 effective working sets per week per muscle.
    /// Personal history can increase this reference, but never make it tiny.
    private static let minimumWeeklyReference = 12.0

    static func all(_ summary: ATHLTHInsightsMuscleSummary) -> [ATHLTHInsightsMuscleFocus] {
        summary.profile.activations.compactMap { item in
            guard item.score.isFinite && item.score > 0 else { return nil }
            let weekly = summary.weeklyLoad[item.region] ?? item.score
            guard weekly.isFinite, weekly > 0 else { return nil }
            let baseline = summary.reliableBaselineRegions.contains(item.region)
                ? (summary.previousWeeklyLoad[item.region] ?? 0) : 0
            let target = max(minimumWeeklyReference, baseline * 1.25)
            let fraction = min(max(weekly / target, 0), 1)
            // 100% is earned only at a meaningful dose, not awarded to the
            // largest logged muscle just because it is ranked first.
            let percentage = Int((fraction * 100).rounded())
            let unusuallyElevated = summary.reliableBaselineRegions.contains(item.region)
                && summary.sessionCount >= 3 && baseline >= 3
                && weekly >= minimumWeeklyReference
                && weekly >= baseline * 1.5
                && percentage >= 85

            return ATHLTHInsightsMuscleFocus(
                region: item.region,
                percentage: percentage,
                score: weekly,
                needsLoadBalanceAttention: unusuallyElevated
            )
        }.sorted {
            if $0.percentage != $1.percentage {
                return $0.percentage > $1.percentage
            }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.region.rawValue < $1.region.rawValue
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

    private func tint(for muscle: ATHLTHInsightsMuscleFocus) -> Color {
        if muscle.needsLoadBalanceAttention { return concentrated }
        return muscle.percentage >= 60 ? elevated : active
    }

    var body: some View {
        // Compute muscle ranking once per render; the same result drives the
        // empty state, map colors and most/least-trained summaries.
        let allMuscles = ATHLTHInsightsMuscleRanking.all(summary)
        let most = Array(allMuscles.prefix(2))
        let mostRegions = Set(most.map(\.region))
        let least = Array(allMuscles.reversed().filter {
            !mostRegions.contains($0.region)
        }.prefix(2))
        let atlasTints = Dictionary(uniqueKeysWithValues: allMuscles.map {
            ($0.region, tint(for: $0))
        })

        return VStack(alignment: .leading, spacing: 13) {
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
                            rows: most
                        )
                        if !least.isEmpty {
                            rankingSection(
                                title: ATHLTHLocalization.choose(
                                    english: "LEAST TRAINED", norwegian: "MINST TRENT"
                                ),
                                rows: least
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
                    english: "Estimated training activity from \(summary.sessionCount) strength sessions in 28 days. Older sessions count less. Compared with your prior training when available, otherwise a conservative reference. 100% is not muscle exhaustion. Red is not a diagnosis. Unlogged areas stay neutral.",
                    norwegian: "Anslått treningsmengde fra \(summary.sessionCount) styrkeøkter på 28 dager. Eldre økter teller mindre. Sammenlignes med din historikk når mulig, ellers et nøkternt referansenivå. 100 % betyr ikke utmattet muskel. Rødt er ingen diagnose. Uregistrerte muskler er nøytrale."
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
