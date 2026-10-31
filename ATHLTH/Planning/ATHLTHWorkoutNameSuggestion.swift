import Foundation

/// Display-only suggestion until the user saves a nameless workout.
/// Never writes into the editor's TextField binding.
enum ATHLTHWorkoutNameSuggestion {
    static func suggested(
        activity: ATHLTHPlannedWorkoutType?,
        blocks: [WorkoutTemplateBlock],
        durationMinutes: Int?,
        routeTitle: String?
    ) -> String {
        let hasRun = blocks.contains { $0.kind == .run && $0.cardioActivity != .walking }
        let hasWalk = blocks.contains { $0.kind == .run && $0.cardioActivity == .walking }
        let hasStrength = blocks.contains { $0.kind == .exercise }
        let hasCycle = blocks.contains { $0.activityTag == "cycling" }
        let isHybrid = [hasRun, hasWalk, hasStrength, hasCycle].filter { $0 }.count > 1
        let isInterval = blocks.contains { $0.groupKind == .intervals }
        let isTreadmill = blocks.contains {
            $0.kind == .run && $0.treadmillInclinePercent != nil
        }

        let label: String
        if isHybrid {
            label = ATHLTHLocalization.choose(english: "Hybrid workout", norwegian: "Hybridøkt")
        } else if isInterval {
            label = ATHLTHLocalization.choose(english: "Interval workout", norwegian: "Intervalløkt")
        } else if isTreadmill {
            label = ATHLTHLocalization.choose(english: "Treadmill run", norwegian: "Tredemølle")
        } else if hasStrength {
            label = ATHLTHLocalization.choose(english: "Strength workout", norwegian: "Styrkeøkt")
        } else if let activity {
            label = activity.title
        } else if hasRun {
            label = ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        } else if hasWalk {
            label = ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
        } else if hasCycle {
            label = ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
        } else {
            label = ATHLTHLocalization.choose(english: "Workout", norwegian: "Treningsøkt")
        }

        if let minutes = durationMinutes, minutes > 0 {
            return "\(label) • \(minutes) min"
        }
        if let routeTitle, !routeTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(label) • \(routeTitle)"
        }
        return label
    }

    static func displayStepTitle(_ block: WorkoutTemplateBlock) -> String {
        // Older imported/existing recipes can contain an English default,
        // even when the app is now displayed in Norwegian.
        switch block.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "running", "run":
            return ATHLTHLocalization.choose(english: "Running", norwegian: "Løping")
        case "walking", "walk":
            return ATHLTHLocalization.choose(english: "Walking", norwegian: "Gåing")
        case "rest", "recovery":
            return ATHLTHLocalization.choose(english: "Rest", norwegian: "Pause")
        default:
            return block.title
        }
    }
}
