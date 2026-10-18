import Foundation

/// Transparent, offline-first recommendations for the Home day sheet.
/// No AI claim or medical inference: uses actual available workout recipes
/// and broad recent workout types, never guessed readiness or target loads.
struct ATHLTHInspirationRecentActivity: Hashable {
    let kind: WorkoutKind
    let startedAt: Date
}

enum ATHLTHHomeWorkoutInspirationPolicy {
    private static func category(_ workout: PlannedSession) -> String {
        if let value = workout.workoutCategory { return value }
        return workout.kind.rawValue
    }

    private static func isHighIntensity(_ workout: PlannedSession) -> Bool {
        let label = workout.title.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current
        ).lowercased()
        return ["interval", "intervall", "hyrox", "race", "konkurranse",
                "tabata", "tempo", "pft", "sprint", "4 x 4", "4×4"].contains {
            label.contains($0)
        }
    }

    static func ranked(
        from workouts: [PlannedSession],
        recent: [ATHLTHInspirationRecentActivity],
        minutes: Int,
        goal: AchievementGoal? = nil,
        now: Date = Date()
    ) -> [PlannedSession] {
        let recentActivities = recent.filter {
            $0.startedAt <= now && now.timeIntervalSince($0.startedAt) < 48 * 3_600
        }
        let recentStrength = recentActivities.contains {
            $0.kind == .strength && now.timeIntervalSince($0.startedAt) < 36 * 3_600
        }
        let recentRun = recentActivities.contains {
            $0.kind == .running && now.timeIntervalSince($0.startedAt) < 30 * 3_600
        }

        var unique = Set<String>()
        let candidates = workouts.enumerated().compactMap { index, workout -> (Int, Int, PlannedSession)? in
            let key = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !key.isEmpty, unique.insert(key).inserted else { return nil }

            let time = workout.durationMinutes ?? 45
            let kind = category(workout)
            var score = 120 - min(abs(time - minutes), 80)
            if time > minutes + 15 { score -= 30 }
            if isHighIntensity(workout) {
                score -= 35 // Don't default to a hard session without context.
            }
            if kind == "strength" {
                score += 10
                if recentStrength { score -= 75 }
            }
            if kind == "running" {
                score += 5
                if recentRun { score -= 55 }
            }
            if kind == "hybrid" {
                score -= 30
                if recentStrength || recentRun { score -= 40 }
            }
            if kind == "walking" || workout.kind == .walking {
                score += 8
            }
            // A declared training goal is a preference, not permission to
            // override recent training load or invent personal readiness.
            switch goal {
            case .buildMuscle, .getStronger:
                if kind == "strength" { score += 28 }
            case .runBetter, .improveEndurance:
                if kind == "running" { score += 26 }
            case .moveMore, .maintainHealth, .loseWeight:
                if kind == "walking" || workout.kind == .walking { score += 20 }
            case .recoverySleep, .mobility:
                if workout.kind == .recovery || workout.kind == .mobility {
                    score += 28
                }
            case .event:
                if kind == "running" { score += 10 }
            case nil:
                break
            }
            if workout.kind == .recovery || workout.kind == .mobility {
                score += recentStrength || recentRun ? 22 : 2
            }
            return (score, index, workout)
        }
        // Preserve catalog order for tied scores, so the UI does not shuffle
        // suggestions on every SwiftUI update.
        return candidates.sorted {
            if $0.0 == $1.0 { return $0.1 < $1.1 }
            return $0.0 > $1.0
        }.map { $0.2 }
    }

    static func explanation(
        for workout: PlannedSession,
        recent: [ATHLTHInspirationRecentActivity],
        goal: AchievementGoal? = nil,
        now: Date = Date()
    ) -> String {
        let last = recent.filter { $0.startedAt <= now }
            .max(by: { $0.startedAt < $1.startedAt })
        guard let last, now.timeIntervalSince(last.startedAt) < 48 * 3_600 else {
            return goal == nil
                ? ATHLTHLocalization.choose(
                    english: "A ready-made session from Workouts. We don't have enough recent training history to personalize this suggestion yet.",
                    norwegian: "En ferdig økt fra Workouts. Vi har ikke nok nyere treningshistorikk til å tilpasse forslaget ennå."
                )
                : ATHLTHLocalization.choose(
                    english: "Suggested with your chosen training goal and available time in mind. We don't have enough recent sessions to estimate recovery.",
                    norwegian: "Foreslått ut fra treningsmålet ditt og tiden du har. Vi har ikke nok nyere økter til å vurdere restitusjonen."
                )
        }
        switch last.kind {
        case .strength:
            return ATHLTHLocalization.choose(
                english: "You recently logged strength training. This is an alternative to consider based on your available time; adjust the effort to how you feel.",
                norwegian: "Du har nylig registrert styrketrening. Dette er et alternativ ut fra tiden du har. Tilpass belastningen etter dagsformen."
            )
        case .running:
            return ATHLTHLocalization.choose(
                english: "You recently logged a run. Consider this option and adjust the intensity to your recovery and training goals.",
                norwegian: "Du har nylig registrert løping. Vurder dette alternativet og tilpass intensiteten etter restitusjon og treningsmål."
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Selected from existing workouts based on your time preference. Adapt the session to your level.",
                norwegian: "Valgt fra eksisterende økter ut fra ønsket tidsbruk. Tilpass økten til nivået ditt."
            )
        }
    }
}
