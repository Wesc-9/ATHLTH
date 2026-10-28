import Foundation

/// Original, locally bundled ATHLTH strength sessions.
/// Distinct programs are deliberately divided by muscle group and experience.
/// These prescriptions never assign a kilogram value; the athlete chooses
/// resistance for every strength set, including the first workout.
enum ATHLTHPremiumStrengthSessions {
    struct Movement: Decodable {
        let name: String
        let sets: Int
        let repsMin: Int?
        let repsMax: Int?
        let durationSeconds: Int?
        let restSeconds: Int
        let rir: Int
    }

    struct Recipe: Decodable {
        let id: Int
        let focus: String
        let level: String
        let levelNO: String
        let titleEN: String
        let titleNO: String
        let summaryEN: String
        let summaryNO: String
        let environment: String
        let warmupMinutes: Int
        let estimatedDurationMinutes: Int
        let moves: [Movement]
    }

    static let recipes: [Recipe] = {
        guard let url = Bundle.main.url(
            forResource: "ATHLTHPremiumStrengthSessions", withExtension: "json"
        ), let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Recipe].self, from: data)
        else { return [] }
        return decoded.filter { recipe in
            (1...99).contains(recipe.id) &&
            (3...8).contains(recipe.moves.count) &&
            (3...15).contains(recipe.warmupMinutes) &&
            (15...150).contains(recipe.estimatedDurationMinutes) &&
            recipe.moves.allSatisfy {
                (1...6).contains($0.sets) &&
                (30...360).contains($0.restSeconds) &&
                (1...4).contains($0.rir) &&
                ($0.durationSeconds.map { (15...120).contains($0) } ??
                    (1...25).contains($0.repsMin ?? -1)) &&
                ($0.durationSeconds != nil ||
                    (($0.repsMax ?? 0) >= ($0.repsMin ?? 100) &&
                     ($0.repsMax ?? 0) <= 30))
            }
        }
    }()

    static func recipes(for focus: String) -> [Recipe] {
        recipes.filter { $0.focus == focus }
    }

    static var entries: [WorkoutTemplateCatalogEntry] {
        recipes.map { recipe in
            let localeIsNorwegian = ATHLTHLocalization.isNorwegian
            let title = localeIsNorwegian ? recipe.titleNO : recipe.titleEN
            let summary = localeIsNorwegian ? recipe.summaryNO : recipe.summaryEN
            let level = localeIsNorwegian ? recipe.levelNO : recipe.level
            return WorkoutTemplateCatalogEntry(
                id: UUID(uuidString: String(
                    format: "C7000000-0000-0000-0000-%012d", recipe.id
                ))!,
                slug: "athlth-premium-strength-\(recipe.focus)-\(recipe.level.lowercased())",
                title: title,
                summary: summary + " · " + ATHLTHLocalization.choose(
                    english: "Choose your own working weights.",
                    norwegian: "Du velger selv treningsvektene."
                ),
                category: "strength",
                difficulty: level,
                estimatedDurationMinutes: recipe.estimatedDurationMinutes,
                tags: [
                    "athlth", "premium-strength", "strength", "styrke",
                    recipe.focus, recipe.level.lowercased(),
                    recipe.levelNO.lowercased(), recipe.environment,
                    recipe.titleEN, recipe.titleNO
                ],
                sourceLabel: "ATHLTH",
                sourceURL: nil,
                blocks: blocks(for: recipe),
                sortOrder: 150 + recipe.id
            )
        }
    }

    static func blocks(for recipe: Recipe) -> [WorkoutTemplateBlock] {
        var result: [WorkoutTemplateBlock] = [
            WorkoutTemplateBlock(
                sequence: 1,
                kind: .note,
                title: ATHLTHLocalization.choose(english: "Warm-up and lighter practice sets",
                          norwegian: "Oppvarming og lette innkjøringssett"),
                exerciseSlug: nil,
                distanceMeters: nil,
                repetitions: nil,
                durationSeconds: TimeInterval(recipe.warmupMinutes * 60),
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: ATHLTHLocalization.choose(
                    english: "Start with gentle movement. Practise the first lift with a light weight of your own choosing before working sets. Stop or adapt if you feel pain.",
                    norwegian: "Start med rolig bevegelse. Øv inn første løft med en lett vekt du velger selv før arbeidssettene. Stopp eller tilpass ved smerte."
                ),
                phase: .warmup
            )
        ]

        for move in recipe.moves {
            let id = ATHLTHExerciseReferenceResolver.nativeSourceIdentifier(
                for: move.name
            )
            let translatedName = NorwegianExerciseText.name(for: id) ??
                (ATHLTHLocalization.isNorwegian
                 ? ATHLTHExerciseNameLocalization.norwegianName(for: move.name)
                 : move.name)
            let repTarget = move.durationSeconds.map { "\($0) s" } ??
                "\(move.repsMin ?? 0)–\(move.repsMax ?? 0)"
            let instruction = ATHLTHLocalization.choose(
                english: "\(repTarget) per set · \(move.rir) reps in reserve (RIR). You choose the weight and may change it before or between sets.",
                norwegian: "\(repTarget) per sett · \(move.rir) repetisjoner i reserve (RIR). Du velger vekten og kan endre den før eller mellom settene."
            )
            var block = WorkoutTemplateBlock(
                sequence: result.count + 1,
                kind: .exercise,
                title: translatedName,
                exerciseSlug: id,
                distanceMeters: nil,
                repetitions: move.durationSeconds == nil ? move.repsMin : nil,
                durationSeconds: move.durationSeconds.map(TimeInterval.init),
                targetWeightKilograms: nil,
                loadNote: nil,
                notes: instruction,
                phase: .main,
                setCount: move.sets,
                restBetweenSetsSeconds: TimeInterval(move.restSeconds)
            )
            block.targetEffortRPE = 10 - move.rir
            result.append(block)
        }
        return result
    }
}
