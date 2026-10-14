import Foundation

/// Display-only Norwegian overlay. Stable English RepDB IDs, training
/// records, image paths and media remain unchanged. A compact JSON file can
/// contain translations for only the exercises whose text has been reviewed.
/// Do not ship guessed safety-critical instructions.
enum NorwegianExerciseText {
    struct Record: Decodable, Sendable {
        let name: String?
        let summary: String?
        let instructions: [String]?
        let tips: [String]?
    }

    // Lazy, read once. Bundled translation text is small and separate from
    // RepDB's large media snapshot. Missing entries use existing fallbacks.
    private static let records: [String: Record] = {
        guard let url = Bundle.main.url(
            forResource: "ExerciseTranslations",
            withExtension: "nb.json"
        ), let data = try? Data(contentsOf: url),
           let values = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return values
    }()

    static func record(for identifier: String?) -> Record? {
        guard ATHLTHLocalization.isNorwegian,
              let identifier else { return nil }
        return records[identifier]
    }

    /// Keep canonical values in selection state and persist only the canonical
    /// ID. Equipment display titles never go back into filter queries.
    static func equipment(_ value: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return value }
        let key = normalize(value)
        let names: [String: String] = [
            "ab crunch machine": "Magemaskin",
            "ab wheel": "Magehjul",
            "air bike": "Airbike",
            "assisted pullup machine": "Assistert pull-up-maskin",
            "assisted pull up machine": "Assistert pull-up-maskin",
            "back extension bench": "Rygghevbenk",
            "back extension machine": "Rygghevmaskin",
            "barbell": "Vektstang",
            "barbells": "Vektstenger",
            "battle rope": "Treningstau",
            "battle ropes": "Treningstau",
            "bench": "Benk",
            "flat bench": "Flat benk",
            "adjustable bench": "Justerbar benk",
            "incline bench": "Skråbenk",
            "decline bench": "Nedovervendt benk",
            "bicep curl machine": "Bicepscurlmaskin",
            "biceps curl machine": "Bicepscurlmaskin",
            "bodyweight": "Kroppsvekt",
            "body weight": "Kroppsvekt",
            "cable": "Kabelapparat",
            "cable machine": "Kabelapparat",
            "cable pulley": "Kabeltrekk",
            "chair": "Stol",
            "dumbbell": "Manual",
            "dumbbells": "Manualer",
            "dumbbell pair": "Manualpar",
            "exercise ball": "Treningsball",
            "foam roller": "Skumrulle",
            "gym mat": "Treningsmatte",
            "jump rope": "Hoppetau",
            "kettlebell": "Kettlebell",
            "kettlebells": "Kettlebells",
            "lat pulldown machine": "Nedtrekksapparat",
            "leg press machine": "Beinpressmaskin",
            "machine": "Treningsapparat",
            "medicine ball": "Medisinball",
            "mini band": "Ministrikk",
            "no equipment": "Uten utstyr",
            "none": "Uten utstyr",
            "other": "Annet",
            "plate": "Vektskive",
            "plates": "Vektskiver",
            "power rack": "Styrkerack",
            "pull up bar": "Pull-up-stang",
            "pullup bar": "Pull-up-stang",
            "resistance band": "Treningsstrikk",
            "resistance bands": "Treningsstrikker",
            "rowing machine": "Romaskin",
            "smith machine": "Smithmaskin",
            "squat rack": "Knebøyrack",
            "stability ball": "Treningsball",
            "step": "Stepkasse",
            "step platform": "Stepkasse",
            "treadmill": "Tredemølle",
            "trap bar": "Hex-stang",
            "trx": "Slyngetrening",
            "weight": "Vekt",
            "weighted vest": "Vektvest"
        ]
        return names[key] ?? value
    }

    static func difficulty(_ value: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return value }
        switch normalize(value) {
        case "beginner": return "Nybegynner"
        case "intermediate": return "Viderekommen"
        case "advanced": return "Avansert"
        case "expert": return "Ekspert"
        default: return value
        }
    }

    static func category(_ value: String) -> String {
        guard ATHLTHLocalization.isNorwegian else { return value }
        switch normalize(value) {
        case "strength": return "Styrke"
        case "stretching", "stretch": return "Tøying"
        case "cardio": return "Kondisjon"
        case "plyometrics": return "Spenst"
        case "powerlifting": return "Styrkeløft"
        case "olympic weightlifting": return "Vektløfting"
        case "mobility": return "Mobilitet"
        case "warm up": return "Oppvarming"
        default: return value
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
