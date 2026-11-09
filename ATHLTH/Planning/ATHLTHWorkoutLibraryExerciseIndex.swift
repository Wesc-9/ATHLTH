import Foundation

/// A compact preview and exact exercise membership query for all library
/// sources. Legacy recipes are projected through the same editor adapter
/// used by the workout engine, without expanding set/recovery repeats.
enum ATHLTHWorkoutLibraryExerciseIndex {
    static func mainTitles(from blocks: [WorkoutTemplateBlock]) -> [String] {
        // Exercises, running steps, and genuinely executable wellness or
        // cycling sections count. Instruction-only notes and pauses do not.
        let activities = blocks.filter { block in
            guard !block.isRestOrActiveRecovery else { return false }
            switch block.kind {
            case .exercise, .run: return true
            case .note: return block.wellnessKind != nil ||
                block.activityTag == "cycling"
            case .rest: return false
            }
        }
        let main = activities.filter { $0.resolvedPhase == .main }
        let candidates = main.isEmpty ? activities : main
        var seen: Set<String> = []
        return candidates.compactMap { block in
            let name = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(normalize(name)).inserted else {
                return nil
            }
            return name
        }
    }

    static func preview(for workout: PlannedSession, limit: Int = 2)
        -> (titles: [String], remaining: Int) {
        preview(blocks: ATHLTHUnifiedWorkout.editorBlocks(from: workout), limit: limit)
    }

    static func preview(blocks: [WorkoutTemplateBlock], limit: Int = 2)
        -> (titles: [String], remaining: Int) {
        let titles = mainTitles(from: blocks)
        let shown = max(0, limit)
        return (Array(titles.prefix(shown)), max(0, titles.count - shown))
    }

    static func availableExercises(in blocks: [WorkoutTemplateBlock]) -> [String] {
        blocks.filter { $0.kind == .exercise }
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func containsExercise(_ name: String, in blocks: [WorkoutTemplateBlock]) -> Bool {
        let target = normalize(name)
        guard !target.isEmpty else { return true }
        return blocks.contains { block in
            block.kind == .exercise && (
                normalize(block.title) == target ||
                (block.exerciseSlug.map(normalize) == target)
            )
        }
    }

    static func containsExercise(_ name: String, in workout: PlannedSession) -> Bool {
        containsExercise(name, in: ATHLTHUnifiedWorkout.editorBlocks(from: workout))
    }

    static func normalize(_ text: String) -> String {
        // Unicode diacritic folding does not map Scandinavian ø/æ on all
        // Foundation platforms. Support natural Norwegian ASCII searches.
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "nb_NO"))
            .lowercased()
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "å", with: "a")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
