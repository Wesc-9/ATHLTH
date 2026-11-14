import Foundation
import SwiftUI

/// Account-scoped profile highlights. Counts reflect completed activity,
/// never planned sessions or a guessed global leaderboard.
enum ATHLTHProfileHighlights {
    enum ActivityKind: String, CaseIterable, Identifiable {
        case all, exercise, interval, route

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return ATHLTHLocalization.choose(english: "All", norwegian: "Alle")
            case .exercise: return ATHLTHLocalization.choose(english: "Exercises", norwegian: "Øvelser")
            case .interval: return ATHLTHLocalization.choose(english: "Intervals", norwegian: "Intervaller")
            case .route: return ATHLTHLocalization.choose(english: "Routes", norwegian: "Ruter")
            }
        }
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .exercise: return "dumbbell"
            case .interval: return "timer"
            case .route: return "point.topleft.down.to.point.bottomright.curvepath"
            }
        }
    }

    struct TrainedItem: Identifiable, Equatable {
        let id: String
        let title: String
        let kind: ActivityKind
        let count: Int
        let lastCompleted: Date
    }

    struct CompetitionSnapshot: Equatable {
        let wins: Int
        let draws: Int
        let losses: Int
        let uniqueOpponents: Int
        var finished: Int { wins + draws + losses }
        var winPercent: Double {
            finished == 0 ? 0 : Double(wins) / Double(finished) * 100
        }
    }

    /// Uses only participant-accepted, eligible scoring results. In a
    /// multi-person contest, tying for first is a draw; an opponent with a
    /// better result is a loss. No ranking is fabricated from local duels.
    @MainActor
    static func competitions(
        _ store: ChallengeStore,
        athleteID: UUID,
        since: Date?
    ) -> CompetitionSnapshot {
        var won = 0, drawn = 0, lost = 0
        var opponentIDs = Set<UUID>()
        for challenge in store.challenges where challenge.status == .completed {
            guard challenge.hasAcceptedOpponent,
                  let own = challenge.participants.first(where: {
                      $0.userID == athleteID &&
                      ($0.state == .creator || $0.state == .accepted)
                  }) else { continue }

            // Treat a contest's real finish or latest submitted effort as
            // its date, not the invitation/creation date.
            let finish = challenge.rules.endsAt ??
                challenge.attempts.map(\.submittedAt).max()
            if let since {
                guard let finish, finish >= since else { continue }
            }
            let scores = store.leaderboard(for: challenge.id).filter {
                $0.score?.isFinite == true
            }
            guard let myScore = scores.first(where: {
                $0.participant.id == own.id
            })?.score else { continue }
            let opponents = scores.filter {
                $0.participant.userID != athleteID
            }
            guard !opponents.isEmpty else { continue }

            let otherScores = opponents.compactMap(\.score)
            guard !otherScores.isEmpty else { continue }
            for other in opponents {
                if let id = other.participant.userID { opponentIDs.insert(id) }
            }
            let bestOpponent = challenge.rules.scoring.prefersLowerScore
                ? otherScores.min()! : otherScores.max()!
            let delta = myScore - bestOpponent
            // Equality is an explicit scored tie, not a falsely created win.
            if abs(delta) < 0.000_001 {
                drawn += 1
            } else if (challenge.rules.scoring.prefersLowerScore && delta < 0) ||
                        (!challenge.rules.scoring.prefersLowerScore && delta > 0) {
                won += 1
            } else {
                lost += 1
            }
        }
        return CompetitionSnapshot(wins: won, draws: drawn,
                                   losses: lost, uniqueOpponents: opponentIDs.count)
    }

    /// One completed workout counts once for a given exercise, even if it
    /// contains multiple working sets of the same movement.
    static func mostTrained(
        strength: [StrengthWorkoutLog],
        running: [ATHLTHCompletedRunningPerformance],
        phone: [PhoneWorkout]
    ) -> [TrainedItem] {
        struct Aggregate {
            let name: String
            let kind: ActivityKind
            var sessions: Set<UUID>
            var latest: Date
        }
        var counts: [String: Aggregate] = [:]
        func record(_ name: String, kind: ActivityKind,
                    sessionID: UUID, at date: Date, identity: String? = nil) {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            let key = kind.rawValue + "|" +
                (identity ?? clean.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                           locale: .current).lowercased())
            if var item = counts[key] {
                item.sessions.insert(sessionID)
                item.latest = max(item.latest, date)
                counts[key] = item
            } else {
                counts[key] = Aggregate(name: clean, kind: kind,
                                        sessions: [sessionID], latest: date)
            }
        }

        for workout in strength where workout.isFinished {
            for entry in workout.exercises where entry.sets.contains(where: {
                $0.countsTowardTrainingLoad
            }) {
                // The exercise name is the only common identifier between
                // standalone and plan-sourced workouts. This is exercise
                // activity, never the containing strength workout title.
                record(entry.exercise.name, kind: .exercise,
                       sessionID: workout.id,
                       at: entry.completedAt ?? workout.endedAt ?? workout.startedAt)
            }
        }

        // Multiple measured work steps distinguish real structured
        // intervals from a free run or a single unstructured workout.
        for workout in running where workout.workSteps.count >= 2 {
            let name = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let generics: Set<String> = [
                "running", "løping", "run", "løpeøkt", "walking",
                "gåtur", "tredemølle", "indoor running"
            ]
            guard !generics.contains(name.lowercased()) else { continue }
            record(name, kind: .interval, sessionID: workout.id,
                   at: workout.completedAt)
        }

        for workout in phone {
            guard let date = workout.end,
                  let routeID = workout.plannedRouteID,
                  let routeTitle = workout.plannedRouteTitle,
                  !routeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            record(routeTitle, kind: .route, sessionID: workout.id,
                   at: date, identity: routeID.uuidString)
        }

        return counts.map { key, entry in
            TrainedItem(id: key, title: entry.name, kind: entry.kind,
                        count: entry.sessions.count, lastCompleted: entry.latest)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.lastCompleted != $1.lastCompleted {
                return $0.lastCompleted > $1.lastCompleted
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

struct ATHLTHProfileCompetitionCard: View {
    @EnvironmentObject private var challenges: ChallengeStore
    let userID: UUID
    @State private var period: Period = .month

    private enum Period: String, CaseIterable, Identifiable {
        case month, year, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .month: return ATHLTHLocalization.choose(english: "This month", norwegian: "Denne måneden")
            case .year: return ATHLTHLocalization.choose(english: "This year", norwegian: "I år")
            case .all: return ATHLTHLocalization.choose(english: "All time", norwegian: "Alle tider")
            }
        }
        var startDate: Date? {
            switch self {
            case .all: return nil
            case .month: return Calendar.current.dateInterval(of: .month, for: Date())?.start
            case .year: return Calendar.current.dateInterval(of: .year, for: Date())?.start
            }
        }
    }

    private var stats: ATHLTHProfileHighlights.CompetitionSnapshot {
        ATHLTHProfileHighlights.competitions(
            challenges, athleteID: userID, since: period.startDate
        )
    }
    private let gold = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(gold)
                    .font(.subheadline)
                Text(tr("Competition statistics", "Konkurransestatistikk"))
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 5)
                Menu {
                    ForEach(Period.allCases) { p in
                        Button {
                            period = p
                        } label: {
                            if period == p {
                                Label(p.title, systemImage: "checkmark")
                            } else { Text(p.title) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(period.title)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dim)
                }
                .accessibilityIdentifier("athlth-profile-competition-period")
            }

            HStack(alignment: .center, spacing: 5) {
                ring(value: stats.wins, label: tr("Wins", "Seire"),
                     fraction: Double(stats.wins) / Double(max(stats.finished, 1)),
                     tint: Color(red: 0.20, green: 0.62, blue: 0.42))
                ring(value: stats.draws, label: tr("Draws", "Uavgjort"),
                     fraction: Double(stats.draws) / Double(max(stats.finished, 1)),
                     tint: Color.gray)
                ring(value: stats.losses, label: tr("Losses", "Tap"),
                     fraction: Double(stats.losses) / Double(max(stats.finished, 1)),
                     tint: Color(red: 0.82, green: 0.30, blue: 0.31))
                ring(value: Int(stats.winPercent.rounded()),
                     label: tr("Win rate", "Vinnprosent"),
                     fraction: stats.winPercent / 100,
                     tint: gold, percent: true)
            }

            Rectangle().fill(ATHLTHPlanDesign.warmDivider).frame(height: 0.7)
            HStack(spacing: 6) {
                metric(icon: "bolt.fill", value: "\(stats.finished)",
                       label: tr("Finished", "Fullførte"))
                Rectangle().fill(ATHLTHPlanDesign.warmDivider).frame(width: 1, height: 34)
                metric(icon: "person.2.fill", value: "\(stats.uniqueOpponents)",
                       label: tr("Opponents", "Konkurrenter"))
                Rectangle().fill(ATHLTHPlanDesign.warmDivider).frame(width: 1, height: 34)
                metric(icon: "star.fill", value: "—",
                       label: tr("App ranking", "Rangering"))
            }
            Text(tr(
                "Only completed challenges with eligible scored results are counted. An overall app ranking is not available.",
                "Kun fullførte konkurranser med gyldige resultater telles. Samlet app-rangering er ikke tilgjengelig."
            ))
            .font(.caption2)
            .foregroundStyle(dim)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .athlthTrainPaper()
        .accessibilityIdentifier("athlth-profile-competition-statistics")
    }

    private func ring(value: Int, label: String, fraction: Double,
                      tint: Color, percent: Bool = false) -> some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let diameter = min(geo.size.width, 84.0)
                ZStack {
                    Circle().stroke(tint.opacity(0.14), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: min(max(fraction, 0), 1))
                        .stroke(tint, style: StrokeStyle(lineWidth: 5,
                                                          lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(percent ? "\(value)%" : "\(value)")
                            .font(.system(size: diameter > 65 ? 19 : 16,
                                          weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(dim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.67)
                    }
                }
                .frame(width: diameter, height: diameter)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 84)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)\(percent ? "%" : "")")
    }

    private func metric(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(gold)
                    .font(.caption)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ATHLTHProfileCompactTrophyCard: View {
    let trophies: [TrophyProgressItem]
    let unlockedCount: Int
    private let gold = ATHLTHPlanDesign.accentInk
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 5) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(gold)
                    .font(.caption)
                Text(ATHLTHLocalization.choose(english: "Trophies", norwegian: "Troféer"))
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    if trophies.indices.contains(index) {
                        ATHLTHTrophyCoreView(trophy: trophies[index], size: 45)
                            .frame(width: 46, height: 52)
                            .accessibilityLabel(trophies[index].title)
                    } else {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.light))
                            .foregroundStyle(gold.opacity(0.7))
                            .frame(width: 46, height: 52)
                            .background(ATHLTHPlanDesign.selectedSurface,
                                        in: RoundedRectangle(cornerRadius: 13))
                    }
                }
                Spacer(minLength: 0)
            }
            Text(
                ATHLTHLocalization.choose(
                    english: "\(unlockedCount) unlocked",
                    norwegian: "\(unlockedCount) låst opp"
                )
            )
            .font(.caption2)
            .foregroundStyle(dim)
            Spacer(minLength: 0)
            NavigationLink {
                TrophyCollectionView(startInCabinet: true)
            } label: {
                HStack(spacing: 5) {
                    Text(ATHLTHLocalization.choose(english: "See all", norwegian: "Se alle"))
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(gold)
                .frame(minHeight: 36, alignment: .leading)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .athlthTrainPaper()
        .accessibilityIdentifier("athlth-profile-trophy-compact")
    }
}

struct ATHLTHProfileMostTrainedCard: View {
    let items: [ATHLTHProfileHighlights.TrainedItem]
    @State private var filter: ATHLTHProfileHighlights.ActivityKind = .all
    private let ink = ATHLTHPlanDesign.ink
    private let dim = ATHLTHPlanDesign.secondaryInk
    private let gold = ATHLTHPlanDesign.accentInk

    private var top: [ATHLTHProfileHighlights.TrainedItem] {
        Array(items.filter { filter == .all || $0.kind == filter }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 3) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.caption)
                    .foregroundStyle(gold)
                Text(ATHLTHLocalization.choose(english: "Most trained", norwegian: "Mest trent"))
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Menu {
                    ForEach(ATHLTHProfileHighlights.ActivityKind.allCases) { kind in
                        Button {
                            filter = kind
                        } label: {
                            if filter == kind {
                                Label(kind.title, systemImage: "checkmark")
                            } else {
                                Label(kind.title, systemImage: kind.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(gold)
                        .font(.subheadline)
                        .frame(width: 29, height: 31)
                }
                .accessibilityLabel(filter.title)
                .accessibilityIdentifier("athlth-profile-most-trained-filter")
            }
            if top.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Your completed exercises, intervals and routes appear here.",
                    norwegian: "Fullførte øvelser, intervaller og ruter vises her."
                ))
                .font(.caption)
                .foregroundStyle(dim)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ForEach(top.indices, id: \.self) { index in
                    let item = top[index]
                    HStack(alignment: .center, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(gold)
                            .frame(width: 17, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(item.kind.title)
                                .font(.system(size: 10))
                                .foregroundStyle(dim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 1)
                        Text("\(item.count)×")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(gold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                    if index < top.count - 1 {
                        Divider().overlay(ATHLTHPlanDesign.warmDivider)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .athlthTrainPaper()
        .accessibilityIdentifier("athlth-profile-most-trained")
    }
}
