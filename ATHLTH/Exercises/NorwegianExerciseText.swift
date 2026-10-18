import Foundation

/// Display-only Norwegian overlay. Stable English RepDB IDs, training
/// records, image paths and media remain unchanged. A compact JSON file can
/// contain translations for only the exercises whose text has been reviewed.
/// Do not ship guessed safety-critical instructions.
enum NorwegianExerciseText {
    struct Record: Decodable, Sendable {
        let summary: String?
        let instructions: [String]?
        let tips: [String]?
    }

    // Short names load independently from potentially longer exercise
    // instructions. Opening the exercise list never decodes the detail pack.
    private static let names: [String: String] = {
        guard let url = Bundle.main.url(
            forResource: "ExerciseNames", withExtension: "json"
        ), let data = try? Data(contentsOf: url),
           let result = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return result
    }()

    private static let records: [String: Record] = {
        guard let url = Bundle.main.url(
            forResource: "ExerciseDetails", withExtension: "json"
        ), let data = try? Data(contentsOf: url),
           let result = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return result
    }()

    static func name(for identifier: String?) -> String? {
        guard ATHLTHLocalization.isNorwegian,
              let identifier else { return nil }
        return names[identifier]
    }

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
        return equipmentNames[key] ?? value
    }

    // Deliberately mixed Norwegian/established English gym vocabulary.
    // Prefer the names athletes actually use: "Tredemølle", but "Hack squat".
    // Only display titles change; equipment IDs remain canonical English.
    private static let equipmentNames: [String: String] = [
        "ab crunch machine": "Magemaskin",
        "ab wheel": "Magehjul",
        "air bike": "Airbike",
        "assisted pullup machine": "Assistert pull-up-maskin",
        "assisted pull up machine": "Assistert pull-up-maskin",
        "back extension bench": "Rygghevbenk",
        "back extension machine": "Rygghevmaskin",
        "barbell": "Vektstang",
        "barbells": "Vektstenger",
        "battle rope": "Battle rope",
        "battle ropes": "Battle ropes",
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
        "climbing rope": "Klatretau",
        "dumbbell": "Manual",
        "dumbbells": "Manualer",
        "dumbbell pair": "Manualpar",
        "exercise ball": "Treningsball",
        "foam roller": "Foam roller",
        "gym mat": "Treningsmatte",
        "jump rope": "Hoppetau",
        "kettlebell": "Kettlebell",
        "kettlebells": "Kettlebells",
        "lat pulldown machine": "Nedtrekksapparat",
        "leg press": "Beinpress",
        "leg press machine": "Beinpressmaskin",
        "machine": "Treningsapparat",
        "medicine ball": "Medisinball",
        "mini band": "Ministrikk",
        "no equipment": "Uten utstyr",
        "none": "Uten utstyr",
        "other": "Annet",
        "plate": "Vektskive",
        "plates": "Vektskiver",
        "power rack": "Power rack",
        "pull up bar": "Pull-up-stang",
        "pullup bar": "Pull-up-stang",
        "resistance band": "Treningsstrikk",
        "resistance bands": "Treningsstrikker",
        "rowing machine": "Romaskin",
        "rower": "Romaskin",
        "smith machine": "Smithmaskin",
        "squat rack": "Knebøyrack",
        "stability ball": "Treningsball",
        "step": "Stepkasse",
        "step platform": "Stepkasse",
        "treadmill": "Tredemølle",
        "trap bar": "Trap bar",
        "trx": "TRX",
        "weight": "Vekt",
        "weighted vest": "Vektvest",

        // RepDB machines: keep familiar English movement names where
        // translating would make equipment harder to recognize at a gym.
        "bicycle": "Sykkel",
        "chest fly machine": "Chest fly-maskin",
        "chest press machine": "Chest press-maskin",
        "dip machine": "Dipsmaskin",
        "dip station": "Dipsstativ",
        "donkey calf raise machine": "Donkey calf raise-maskin",
        "elliptical": "Ellipsemaskin",
        "ez bar": "EZ-stang",
        "glute ham developer": "GHD-benk",
        "hack squat": "Hack squat",
        "hip abduction machine": "Utside lår-maskin",
        "hip adduction machine": "Innside lår-maskin",
        "hip thrust machine": "Hip thrust-maskin",
        "leg curl": "Leg curl",
        "leg extension": "Leg extension",
        "loop band": "Ministrikk",
        "pec deck": "Pec deck",
        "plate loaded dip machine": "Dipsmaskin (skivebelastet)",
        "plate loaded lateral raise machine": "Sidehev-maskin",
        "plyo box": "Plyoboks",
        "preacher curl machine": "Preacher curl-maskin",
        "reverse fly machine": "Reverse fly-maskin",
        "rings": "Turnringer",
        "seated calf raise machine": "Sittende tåhev-maskin",
        "seated row machine": "Sittende roapparat",
        "shoulder press machine": "Skulderpressmaskin",
        "shrug machine": "Shrug-maskin",
        "ski erg": "SkiErg",
        "slam ball": "Slam ball",
        "sled": "Treningsslede",
        "stair climber": "Trappemaskin",
        "standing calf raise machine": "Stående tåhev-maskin",
        "stationary bike": "Treningssykkel",
        "suspension trainer": "TRX / slyngetrening",
        "tricep extension machine": "Tricepsmaskin",
        "wall ball": "Wall ball",
        "wrist roller": "Wrist roller"
    ]

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
