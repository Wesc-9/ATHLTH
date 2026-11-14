import SwiftUI
import UIKit

/// Deterministic local imagery for ATHLTH training plans and their daily
/// sessions. The image must fit the workout, not just its broad category.
/// Keep the policy separate from view code so all plan layouts agree.
/// Every asset name below exists in ATHLTH/Assets.xcassets and works offline.
enum ATHLTHPlanWorkoutArtwork {
    enum TrainingScene: String {
        case stadiumIntervals
        case stadiumRace
        case trailEndurance
        case easyRun
        case uphillRunning
        case strength
        case hybrid
        case recovery
        case walking
    }

    static func scene(for entry: TrainingPlanCatalogEntry) -> TrainingScene {
        let phrase = (
            entry.slug + " " + entry.title + " " + entry.goal + " " +
            entry.workoutPattern.joined(separator: " ") + " " +
            entry.tags.joined(separator: " ")
        ).lowercased()

        if matches(phrase, ["recovery", "rest", "restitusjon", "mobility", "yoga"]) {
            return .recovery
        }
        if matches(phrase, ["hill", "mountain", "bakke", "trail", "terreng", "vertical"]) {
            return .uphillRunning
        }
        if matches(phrase, ["interval", "vo2", "vma", "sprint", "speed", "4x4",
                            "hurtig", "tempo_run", "threshold"]) {
            return .stadiumIntervals
        }
        if entry.category == "hybrid" ||
           matches(phrase, ["hyrox", "hybrid", "cross_training", "functional_fitness"]) {
            return .hybrid
        }
        if entry.category == "strength" || entry.category == "muscle_focus" {
            return .strength
        }
        if matches(phrase, ["race", "competition", "marathon", "half_marathon",
                            "10k", "5k", "konkurranse", "event", "finish"]) {
            return .stadiumRace
        }
        if matches(phrase, ["long_run", "endurance", "long_distance",
                            "langtur", "utholdenhet", "aerobic"]) {
            return .trailEndurance
        }
        if matches(phrase, ["walking", "walk", "gåtur", "hike"]) {
            return .walking
        }
        if entry.category == "running" { return .easyRun }
        return .hybrid
    }

    static func scene(for workout: PlannedSession) -> TrainingScene {
        let blocks = workout.resolvedWorkoutBlocks
        let phrase = (
            workout.title + " " +
            (workout.sourcePlanSessionType ?? "") + " " +
            (workout.workoutCategory ?? "")
        ).lowercased()

        if matches(phrase, ["recovery", "rest", "mobility", "yoga", "restitusjon"]) {
            return .recovery
        }
        if matches(phrase, ["walk", "walking", "gåtur"]) {
            return .walking
        }
        if matches(phrase, ["hill", "mountain", "trail", "bakke", "terreng"]) ||
           blocks.contains(where: {
               ($0.targetGradientPercent ?? 0) > 0 ||
               ($0.targetElevationGainMeters ?? 0) > 0
           }) {
            return .uphillRunning
        }
        if matches(phrase, ["hyrox", "hybrid", "functional"]) ||
           (blocks.contains(where: { $0.kind == .exercise }) &&
            blocks.contains(where: { $0.kind == .run })) {
            return .hybrid
        }
        if blocks.contains(where: { $0.kind == .exercise }) ||
           workout.workoutCategory == "strength" {
            return .strength
        }
        if matches(phrase, ["interval", "sprint", "vo2", "vma", "4x4", "threshold"]) ||
           blocks.contains(where: { ($0.targetHeartRateZone ?? 0) >= 4 }) {
            return .stadiumIntervals
        }
        if matches(phrase, ["race", "competition", "10k", "5k", "marathon"]) {
            return .stadiumRace
        }
        if matches(phrase, ["long", "langtur", "endurance"]) ||
           (workout.targetDistanceKilometers ?? 0) >= 10 {
            return .trailEndurance
        }
        return .easyRun
    }

    /// A new editorial image activates as soon as the imageset is bundled.
    /// Existing shipped artwork remains a safe offline fallback during the
    /// transition, so no image request, blank tile or per-card image lookup.
    private static let resolvedAssets: [TrainingScene: String] = {
        let candidates: [(TrainingScene, String, String)] = [
            (.stadiumIntervals, "ATHLTHTrackIntervals", "GoalRunning"),
            (.stadiumRace, "ATHLTHTrackRace", "GoalProgress"),
            (.trailEndurance, "ATHLTHTrailEndurance", "GoalEndurance"),
            (.easyRun, "ATHLTHTrackTeam", "GoalEndurance"),
            (.uphillRunning, "ATHLTHHillRun", "GoalSprint"),
            (.strength, "ATHLTHStrengthTeam", "StrengthQuickHero"),
            (.hybrid, "ATHLTHHybridSled", "StrengthQuickHero"),
            (.recovery, "ATHLTHRecoveryWalk", "GoalRecovery"),
            (.walking, "ATHLTHRecoveryWalk", "GoalWalking")
        ]
        return Dictionary(uniqueKeysWithValues: candidates.map {
            scene, newAsset, existingAsset in
            (scene, UIImage(named: newAsset) == nil ? existingAsset : newAsset)
        })
    }()

    static func asset(for scene: TrainingScene) -> String {
        resolvedAssets[scene] ?? "GoalRunning"
    }

    static func asset(for entry: TrainingPlanCatalogEntry) -> String {
        asset(for: scene(for: entry))
    }

    static func asset(for workout: PlannedSession) -> String {
        asset(for: scene(for: workout))
    }

    static func label(for workout: PlannedSession) -> String {
        switch scene(for: workout) {
        case .stadiumIntervals:
            return ATHLTHLocalization.choose(english: "Intervals", norwegian: "Intervaller")
        case .stadiumRace:
            return ATHLTHLocalization.choose(english: "Race day", norwegian: "Konkurranse")
        case .trailEndurance:
            return ATHLTHLocalization.choose(english: "Long run", norwegian: "Langtur")
        case .easyRun:
            return ATHLTHLocalization.choose(english: "Run", norwegian: "Løping")
        case .uphillRunning:
            return ATHLTHLocalization.choose(english: "Hills", norwegian: "Bakkeløp")
        case .strength:
            return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
        case .hybrid:
            return "Hybrid"
        case .recovery:
            return ATHLTHLocalization.choose(english: "Recovery", norwegian: "Restitusjon")
        case .walking:
            return ATHLTHLocalization.choose(english: "Walk", norwegian: "Gåtur")
        }
    }

    private static func matches(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }
}
