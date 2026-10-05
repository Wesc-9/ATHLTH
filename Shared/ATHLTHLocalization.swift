import Foundation

enum ATHLTHLocalization {
    private static var selectedLocale: Locale {
        let value =
            UserDefaults.standard.string(
                forKey: "settings.language"
            )

        guard let value,
              value != "system",
              !value.isEmpty
        else {
            return .autoupdatingCurrent
        }

        return Locale(identifier: value)
    }

    static func string(
        _ key: String.LocalizationValue
    ) -> String {
        String(
            localized: key,
            locale: selectedLocale
        )
    }

    static func format(
        _ key: String.LocalizationValue,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key),
            locale: selectedLocale,
            arguments: arguments
        )
    }

    static var isNorwegian: Bool {
        let identifier =
            selectedLocale
                .language
                .languageCode?
                .identifier
                .lowercased()

        return identifier == "nb" ||
            identifier == "no" ||
            identifier == "nn"
    }

    static func choose(
        english: String,
        norwegian: String
    ) -> String {
        isNorwegian
            ? norwegian
            : english
    }

    static func format(
        english: String,
        norwegian: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format:
                isNorwegian
                    ? norwegian
                    : english,
            locale: selectedLocale,
            arguments: arguments
        )
    }

    static func counted(
        _ count: Int,
        englishSingular: String,
        englishPlural: String,
        norwegianSingular: String,
        norwegianPlural: String
    ) -> String {
        let noun =
            count == 1
                ? choose(
                    english:
                        englishSingular,
                    norwegian:
                        norwegianSingular
                )
                : choose(
                    english:
                        englishPlural,
                    norwegian:
                        norwegianPlural
                )

        return "\(count) \(noun)"
    }
}


// Dynamic public exercise data is stored with a stable English canonical name.
// Keep localization at the presentation/search layer so workout history,
// favorites, sync payloads and third-party IDs stay language independent.
private final class ATHLTHExerciseNameLocalizationCache:
    @unchecked Sendable {
    private let lock = NSLock()
    private var norwegianNames: [String: String] = [:]
    private var searchTerms: [String: [String]] = [:]

    func norwegianName(
        for key: String
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return norwegianNames[key]
    }

    func storeNorwegianName(
        _ value: String,
        for key: String
    ) {
        lock.lock()
        norwegianNames[key] = value
        lock.unlock()
    }

    func terms(
        for key: String
    ) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        return searchTerms[key]
    }

    func storeTerms(
        _ value: [String],
        for key: String
    ) {
        lock.lock()
        searchTerms[key] = value
        lock.unlock()
    }
}

enum ATHLTHExerciseNameLocalization {
    private static let cache =
        ATHLTHExerciseNameLocalizationCache()

    private static let exactNorwegianNames: [String: String] = [
        "bench press": "Benkpress",
        "barbell bench press": "Benkpress med stang",
        "dumbbell bench press": "Benkpress med manualer",
        "incline bench press": "Skråbenk",
        "incline barbell bench press": "Skråbenk med stang",
        "incline dumbbell bench press": "Skråbenk med manualer",
        "decline bench press": "Negativ benkpress",
        "machine chest press": "Brystpress i maskin",
        "chest press": "Brystpress",
        "push up": "Armheving",
        "hand release push up": "Armheving med håndslipp",
        "chest fly": "Brystflyes",
        "cable fly": "Kabelflyes",
        "deadlift": "Markløft",
        "barbell deadlift": "Markløft med stang",
        "dumbbell deadlift": "Markløft med manualer",
        "romanian deadlift": "Rumensk markløft",
        "stiff leg deadlift": "Strakmark",
        "sumo deadlift": "Sumo markløft",
        "squat": "Knebøy",
        "back squat": "Knebøy",
        "barbell back squat": "Knebøy med stang",
        "front squat": "Frontbøy",
        "goblet squat": "Goblet-knebøy",
        "bulgarian split squat": "Bulgarsk splittknebøy",
        "split squat": "Splittknebøy",
        "leg press": "Beinpress",
        "leg extension": "Beinstrekk",
        "leg curl": "Lårcurl",
        "lying leg curl": "Liggende lårcurl",
        "seated leg curl": "Sittende lårcurl",
        "calf raise": "Tåhev",
        "standing calf raise": "Stående tåhev",
        "seated calf raise": "Sittende tåhev",
        "hip thrust": "Hip thrust",
        "glute bridge": "Seteløft",
        "walking lunge": "Gående utfall",
        "reverse lunge": "Bakoverutfall",
        "stationary lunge": "Utfall på stedet",
        "lunge": "Utfall",
        "lat pulldown": "Nedtrekk",
        "pull up": "Pull-up",
        "chin up": "Chins",
        "barbell row": "Stangroing",
        "dumbbell row": "Manualroing",
        "one arm dumbbell row": "Enarms manualroing",
        "single arm dumbbell row": "Enarms manualroing",
        "cable row": "Kabelroing",
        "seated cable row": "Sittende kabelroing",
        "bent over row": "Foroverbøyd roing",
        "shoulder press": "Skulderpress",
        "dumbbell shoulder press": "Skulderpress med manualer",
        "barbell shoulder press": "Skulderpress med stang",
        "machine shoulder press": "Skulderpress i maskin",
        "overhead press": "Skulderpress",
        "military press": "Militærpress",
        "lateral raise": "Sidehev",
        "front raise": "Fronthev",
        "rear delt fly": "Omvendt flyes",
        "face pull": "Face pull",
        "shrug": "Skuldertrekk",
        "biceps curl": "Bicepscurl",
        "dumbbell biceps curl": "Bicepscurl med manualer",
        "barbell curl": "Bicepscurl med stang",
        "hammer curl": "Hammercurl",
        "preacher curl": "Preacher curl",
        "triceps pushdown": "Tricepspress",
        "triceps extension": "Tricepsstrekk",
        "skull crusher": "Liggende tricepspress",
        "dip": "Dips",
        "dips": "Dips",
        "plank": "Planke",
        "side plank": "Sideplanke",
        "hanging leg raise": "Hengende beinhev",
        "leg raise": "Beinhev",
        "russian twist": "Russisk twist",
        "ab wheel rollout": "Utrulling med magehjul",
        "rowing": "Roing",
        "rowing machine": "Romaskin",
        "skierg": "SkiErg",
        "sled push": "Sledepush",
        "sled pull": "Slededrag",
        "burpee broad jump": "Burpee med lengdehopp",
        "farmers carry": "Farmers walk",
        "farmer carry": "Farmers walk",
        "sandbag walking lunge": "Gående utfall med sandsekk",
        "wall ball": "Wall ball",
        "box jump": "Kassehopp",
        "kettlebell swing": "Kettlebell-sving",
        "clean and jerk": "Støt",
        "power clean": "Styrkevending",
        "hang clean": "Hengvending",
        "power snatch": "Styrkerykk",
        "snatch": "Rykk"
    ]

    // Extra gym terms make Norwegian search tolerant of the names people
    // actually use, while the English canonical name always remains searchable.
    private static let norwegianAliases: [String: [String]] = [
        "bench press": ["benk", "brystpress"],
        "deadlift": ["mark"],
        "romanian deadlift": ["rumensk mark", "rmark"],
        "squat": ["bøy"],
        "back squat": ["bøy"],
        "front squat": ["frontbøy"],
        "pull up": ["kroppsheving", "pullup"],
        "chin up": ["kroppsheving", "chins"],
        "lat pulldown": ["latdrag", "nedtrekk"],
        "push up": ["pushup", "armheving"],
        "overhead press": ["militærpress", "skulderpress"],
        "shoulder press": ["militærpress"],
        "leg extension": ["lårstrekk", "quadriceps"],
        "leg curl": ["hamstringcurl", "bakside lår"],
        "calf raise": ["legghev", "tåhev"],
        "triceps pushdown": ["pushdown", "tricepspress"],
        "biceps curl": ["curl", "bicepscurl"],
        "farmers carry": ["farmers walk", "bondens gange"],
        "farmer carry": ["farmers walk", "bondens gange"],
        "rowing": ["romaskin", "roing"]
    ]

    // Ordered longest/specific phrases first. This gives useful Norwegian
    // names for the long tail of RepDB exercises without a network translator.
    private static let phraseReplacements: [(String, String)] = [
        ("hand-release push-up", "armheving med håndslipp"),
        ("hand release push up", "armheving med håndslipp"),
        ("bulgarian split squat", "bulgarsk splittknebøy"),
        ("incline bench press", "skråbenk"),
        ("decline bench press", "negativ benkpress"),
        ("romanian deadlift", "rumensk markløft"),
        ("stiff-leg deadlift", "strakmark"),
        ("stiff leg deadlift", "strakmark"),
        ("clean and jerk", "støt"),
        ("seated cable row", "sittende kabelroing"),
        ("bent-over row", "foroverbøyd roing"),
        ("bent over row", "foroverbøyd roing"),
        ("triceps pushdown", "tricepspress"),
        ("overhead press", "skulderpress"),
        ("shoulder press", "skulderpress"),
        ("lateral raise", "sidehev"),
        ("front raise", "fronthev"),
        ("rear delt fly", "omvendt flyes"),
        ("lat pulldown", "nedtrekk"),
        ("bench press", "benkpress"),
        ("chest press", "brystpress"),
        ("chest fly", "brystflyes"),
        ("cable fly", "kabelflyes"),
        ("leg press", "beinpress"),
        ("leg extension", "beinstrekk"),
        ("leg curl", "lårcurl"),
        ("calf raise", "tåhev"),
        ("glute bridge", "seteløft"),
        ("hip thrust", "hip thrust"),
        ("split squat", "splittknebøy"),
        ("walking lunge", "gående utfall"),
        ("reverse lunge", "bakoverutfall"),
        ("biceps curl", "bicepscurl"),
        ("hammer curl", "hammercurl"),
        ("triceps extension", "tricepsstrekk"),
        ("hanging leg raise", "hengende beinhev"),
        ("leg raise", "beinhev"),
        ("side plank", "sideplanke"),
        ("russian twist", "russisk twist"),
        ("ab wheel rollout", "utrulling med magehjul"),
        ("kettlebell swing", "kettlebell-sving"),
        ("burpee broad jump", "burpee med lengdehopp"),
        ("farmers carry", "farmers walk"),
        ("farmer's carry", "farmers walk"),
        ("farmer carry", "farmers walk"),
        ("sled push", "sledepush"),
        ("sled pull", "slededrag"),
        ("box jump", "kassehopp"),
        ("power clean", "styrkevending"),
        ("hang clean", "hengvending"),
        ("power snatch", "styrkerykk"),
        ("push-up", "armheving"),
        ("push up", "armheving"),
        ("pull-up", "pull-up"),
        ("pull up", "pull-up"),
        ("chin-up", "chins"),
        ("chin up", "chins"),
        ("deadlift", "markløft"),
        ("front squat", "frontbøy"),
        ("back squat", "knebøy"),
        ("goblet squat", "goblet-knebøy"),
        ("squat", "knebøy"),
        ("lunge", "utfall"),
        ("seated", "sittende"),
        ("standing", "stående"),
        ("lying", "liggende"),
        ("single-arm", "enarms"),
        ("single arm", "enarms"),
        ("one-arm", "enarms"),
        ("one arm", "enarms"),
        ("single-leg", "ettbeins"),
        ("single leg", "ettbeins"),
        ("close-grip", "smalt grep"),
        ("close grip", "smalt grep"),
        ("wide-grip", "bredt grep"),
        ("wide grip", "bredt grep"),
        ("reverse-grip", "omvendt grep"),
        ("reverse grip", "omvendt grep"),
        ("smith machine", "smithmaskin"),
        ("resistance band", "treningsstrikk"),
        ("medicine ball", "medisinball"),
        ("stability ball", "treningsball"),
        ("dumbbell", "manual"),
        ("barbell", "stang"),
        ("cable", "kabel"),
        ("machine", "maskin"),
        ("bodyweight", "kroppsvekt"),
        ("assisted", "assistert"),
        ("alternating", "vekselvis"),
        ("rowing", "roing"),
        ("row", "roing"),
        ("plank", "planke"),
        ("snatch", "rykk"),
        ("clean", "vending")
    ]

    static func norwegianName(for englishName: String) -> String {
        let trimmed =
            englishName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty else {
            return englishName
        }

        if let cached =
                cache.norwegianName(
                    for: trimmed
                ) {
            return cached
        }

        let key = normalizedKey(trimmed)
        let resolved: String

        if let exact =
                exactNorwegianNames[key] {
            resolved = exact
        } else {
            var translated = trimmed

            for (english, norwegian) in
                phraseReplacements
            where translated.range(
                of: english,
                options: [.caseInsensitive]
            ) != nil {
                translated =
                    translated
                        .replacingOccurrences(
                            of: english,
                            with: norwegian,
                            options: [.caseInsensitive]
                        )
            }

            resolved =
                translated == trimmed
                    ? trimmed
                    : capitalizingFirstCharacter(
                        translated
                    )
        }

        cache.storeNorwegianName(
            resolved,
            for: trimmed
        )
        return resolved
    }

    static func searchTerms(for englishName: String) -> [String] {
        if let cached =
                cache.terms(
                    for: englishName
                ) {
            return cached
        }

        let key = normalizedKey(englishName)
        var values = [
            englishName,
            norwegianName(for: englishName)
        ]
        values.append(
            contentsOf:
                norwegianAliases[key] ?? []
        )

        var seen = Set<String>()
        let resolved =
            values.filter { value in
                let normalized = value
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased()
                guard !normalized.isEmpty
                else {
                    return false
                }
                return seen.insert(
                    normalized
                ).inserted
            }

        cache.storeTerms(
            resolved,
            for: englishName
        )
        return resolved
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .split {
                $0.isWhitespace ||
                $0 == "-" ||
                $0 == "_"
            }
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    private static func capitalizingFirstCharacter(
        _ value: String
    ) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + String(value.dropFirst())
    }
}
