import CryptoKit
import Foundation
import Supabase

enum ExerciseMuscleGroup: String, CaseIterable, Identifiable, Hashable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case core = "Core"
    case glutes = "Glutes"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case calves = "Calves"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest:
            return ATHLTHLocalization.choose(
                english: "Chest",
                norwegian: "Bryst"
            )
        case .back:
            return ATHLTHLocalization.choose(
                english: "Back",
                norwegian: "Rygg"
            )
        case .shoulders:
            return ATHLTHLocalization.choose(
                english: "Shoulders",
                norwegian: "Skuldre"
            )
        case .biceps:
            return "Biceps"
        case .triceps:
            return "Triceps"
        case .forearms:
            return ATHLTHLocalization.choose(
                english: "Forearms",
                norwegian: "Underarmer"
            )
        case .core:
            return ATHLTHLocalization.choose(
                english: "Core",
                norwegian: "Kjerne"
            )
        case .glutes:
            return ATHLTHLocalization.choose(
                english: "Glutes",
                norwegian: "Setemuskler"
            )
        case .quads:
            return ATHLTHLocalization.choose(
                english: "Quads",
                norwegian: "Forside lår"
            )
        case .hamstrings:
            return ATHLTHLocalization.choose(
                english: "Hamstrings",
                norwegian: "Bakside lår"
            )
        case .calves:
            return ATHLTHLocalization.choose(
                english: "Calves",
                norwegian: "Legger"
            )
        }
    }
}

@MainActor
final class ExerciseLibraryStore: ObservableObject {
    @Published private(set) var athlthCatalogExercises:
        [ExerciseLibraryEntry] =
            ExerciseLibraryStore.fallbackATHLTHExercises
    @Published private(set) var repDBExercises: [ExerciseLibraryEntry] = []
    @Published private(set) var repDBExpectedCount: Int?
    @Published private(set) var customExercises: [ExerciseLibraryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?

    private let datasetURL = URL(string: "https://exercise-dataset.com/exercises.json")!
    private let imageBaseURL = URL(string: "https://exercise-dataset.com/")!
    private let client: SupabaseClient = SupabaseEnvironment.client

    private var accountID: UUID?
    private var lastATHLTHCatalogRefreshAt: Date?
    private var cachedAllExercises: [ExerciseLibraryEntry]?
    private var cachedBodyParts: [String]?
    private var cachedEquipmentOptions: [String]?

    init() {
        loadCachedRepDB()
    }

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        accountID = userID
        customExercises = []
        invalidateDerivedCaches()
        guard userID != nil else { return }
        loadCustomExercises()
    }

    func localizedBodyPartTitle(
        _ value: String
    ) -> String {
        let normalized =
            value
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        let norwegian: String
        switch normalized {
        case "back":
            norwegian = "Rygg"
        case "chest":
            norwegian = "Bryst"
        case "core":
            norwegian = "Mage og kjerne"
        case "forearms", "lower arms":
            norwegian = "Underarmer"
        case "full body":
            norwegian = "Hele kroppen"
        case "lower legs", "calves":
            norwegian = "Legger"
        case "quads", "quadriceps":
            norwegian = "Forside lår"
        case "shoulders":
            norwegian = "Skuldre"
        case "upper arms":
            norwegian = "Overarmer"
        case "upper legs":
            norwegian = "Lår"
        case "biceps":
            norwegian = "Biceps"
        case "triceps":
            norwegian = "Triceps"
        case "glutes":
            norwegian = "Setemuskler"
        case "hamstrings":
            norwegian = "Bakside lår"
        case "neck":
            norwegian = "Nakke"
        case "cardio":
            norwegian = "Kondisjon"
        default:
            return value
        }

        return ATHLTHLocalization.choose(
            english: value,
            norwegian: norwegian
        )
    }

    // These 20 exercises are ORIGINAL additions to ATHLTH's Supabase
    // exercise_catalog. Never pass off RepDB's existing exercises as new.
    static let originalCoreSlugs: [String] = [
        "athlth-core-plank-shoulder-tap",
        "athlth-core-plank-jack",
        "athlth-core-plank-walkout",
        "athlth-core-rkc-plank",
        "athlth-core-hollow-body-rock",
        "athlth-core-toe-touch-crunch",
        "athlth-core-standing-cable-woodchop",
        "athlth-core-half-kneeling-cable-chop",
        "athlth-core-pallof-step-out",
        "athlth-core-banded-dead-bug-pulldown",
        "athlth-core-bird-dog-row",
        "athlth-core-side-plank-hip-dip",
        "athlth-core-side-plank-reach-through",
        "athlth-core-bear-plank-shoulder-tap",
        "athlth-core-windshield-wiper",
        "athlth-core-stir-the-pot",
        "athlth-core-swiss-ball-body-saw",
        "athlth-core-copenhagen-plank",
        "athlth-core-suitcase-march",
        "athlth-core-standing-knee-elbow-crunch"
    ]

    var featuredCoreExercises: [ExerciseLibraryEntry] {
        let bySlug = Dictionary(
            athlthCatalogExercises.compactMap { entry -> (String, ExerciseLibraryEntry)? in
                guard entry.source == .athlthCatalog,
                      let slug = entry.sourceIdentifier,
                      slug.hasPrefix("athlth-core-") else { return nil }
                return (slug, entry)
            }, uniquingKeysWith: { first, _ in first }
        )
        return Self.originalCoreSlugs.compactMap { bySlug[$0] }
    }

    // Local aliases make Norwegian searches work without altering or
    // redistributing the upstream RepDB dataset.
    static let norwegianExerciseNames: [String: String] = [
        "plank": "Planke",
        "side-plank": "Sideplanke",
        "crunches": "Magecrunch",
        "sit-ups": "Situps",
        "bicycle-crunch": "Sykkelcrunch",
        "reverse-crunches": "Omvendt crunch",
        "dead-bug": "Død bille",
        "bird-dog": "Fuglehund",
        "hollow-body-hold": "Hollow hold",
        "russian-twist": "Russisk rotasjon",
        "hanging-knee-raise": "Hengende kneløft",
        "hanging-leg-raise": "Hengende beinhev",
        "lying-leg-raise": "Liggende beinhev",
        "cable-crunch": "Magecrunch i kabel",
        "cable-pallof-press": "Pallof press",
        "ab-wheel-rollout": "Magehjul",
        "flutter-kicks": "Saksespark",
        "mountain-climbers": "Fjellklatrer",
        "dragon-flag": "Dragon flag",
        "heel-touches": "Hælberøring",
        "machine-back-extension": "Rygghev i maskin",
        "back-extension": "Rygghev",
        "athlth-core-plank-shoulder-tap": "Planke med skulderklapp",
        "athlth-core-plank-jack": "Plankehopp",
        "athlth-core-plank-walkout": "Plankegange",
        "athlth-core-rkc-plank": "RKC-planke",
        "athlth-core-hollow-body-rock": "Hollow rock",
        "athlth-core-toe-touch-crunch": "Tåberøring med crunch",
        "athlth-core-standing-cable-woodchop": "Stående kabelrotasjon",
        "athlth-core-half-kneeling-cable-chop": "Knående kabelrotasjon",
        "athlth-core-pallof-step-out": "Pallof steg ut",
        "athlth-core-banded-dead-bug-pulldown": "Dead bug med strikk",
        "athlth-core-bird-dog-row": "Bird dog med roing",
        "athlth-core-side-plank-hip-dip": "Sideplanke med hoftesenk",
        "athlth-core-side-plank-reach-through": "Sideplanke med rotasjon",
        "athlth-core-bear-plank-shoulder-tap": "Bjørneplanke med skulderklapp",
        "athlth-core-windshield-wiper": "Vindusvisker",
        "athlth-core-stir-the-pot": "Rør i gryten",
        "athlth-core-swiss-ball-body-saw": "Plankesag på ball",
        "athlth-core-copenhagen-plank": "Copenhagen-planke",
        "athlth-core-suitcase-march": "Koffertmarsj",
        "athlth-core-standing-knee-elbow-crunch": "Stående kne-til-albue"
    ]

    // Written specifically for ATHLTH: not copied from the RepDB
    // descriptions or translations. The RepDB photo and exercise
    // attribution remain attached to the original library entry.
    static let norwegianCoreInstructions: [String: [String]] = [
        "plank": ["Plasser albuene under skuldrene og strekk kroppen ut.",
                  "Hold magen aktiv og pust rolig uten å svaie i korsryggen."],
        "side-plank": ["Støtt deg på underarmen med skulderen rett over albuen.",
                       "Løft hoften og hold kroppen i en rett linje."],
        "crunches": ["Ligg på ryggen med knærne bøyd og føttene i gulvet.",
                     "Løft øvre del av ryggen kontrollert og senk rolig tilbake."],
        "sit-ups": ["Ligg på ryggen med bøyde knær.",
                    "Rull overkroppen kontrollert opp og senk den rolig ned igjen."],
        "bicycle-crunch": ["Ligg på ryggen med hendene lett ved hodet.",
                          "Roter skulderen mot motsatt kne og bytt side i rolig tempo."],
        "reverse-crunches": ["Ligg på ryggen og trekk knærne mot brystet.",
                             "Rull bekkenet forsiktig opp og senk det kontrollert."],
        "dead-bug": ["Ligg på ryggen med armer og ben løftet.",
                     "Senk motsatt arm og ben rolig uten å miste kontakten i korsryggen."],
        "bird-dog": ["Stå på alle fire med hendene under skuldrene.",
                     "Strekk motsatt arm og ben ut, hold bekkenet stabilt og bytt."],
        "hollow-body-hold": ["Ligg på ryggen og press korsryggen lett mot gulvet.",
                             "Løft skuldre og ben så langt du kan med god kontroll."],
        "russian-twist": ["Sitt med bøyde knær og en lett bakoverlent overkropp.",
                          "Roter rolig fra side til side uten å rykke."],
        "hanging-knee-raise": ["Heng stabilt i en stang med kontrollert grep.",
                               "Trekk knærne opp, unngå sving og senk langsomt."],
        "hanging-leg-raise": ["Heng i en stang og stabiliser overkroppen.",
                              "Løft bena kontrollert og senk uten å svinge."],
        "lying-leg-raise": ["Ligg flatt på ryggen med hendene langs sidene.",
                            "Løft bena kontrollert og senk til du fortsatt kan holde korsryggen stabil."],
        "cable-crunch": ["Still deg ved kabelapparatet og hold tauet ved hodet.",
                         "Bøy overkroppen ved å trekke ribbeina mot bekkenet, uten å dra med armene."],
        "cable-pallof-press": ["Stå sidelengs mot en kabel med håndtaket ved brystet.",
                               "Press hendene ut foran kroppen og motstå rotasjon."],
        "ab-wheel-rollout": ["Start på knærne med magehjulet under skuldrene.",
                              "Rull rolig frem så langt du klarer uten å svaie, og trekk tilbake."],
        "flutter-kicks": ["Ligg på ryggen med bena strukket.",
                          "Hold magen aktiv og bytt på å heve bena i små kontrollerte bevegelser."],
        "mountain-climbers": ["Start i en stabil høy plankeposisjon.",
                              "Før knærne vekselvis frem uten at hoftene løftes høyt."],
        "dragon-flag": ["Hold fast i et stabilt feste over hodet mens du ligger på ryggen.",
                        "Senk den strake kroppen svært kontrollert; velg en enklere variant ved behov."],
        "heel-touches": ["Ligg på ryggen med knærne bøyd og skuldrene litt hevet.",
                         "Nå vekselvis mot hælene med en liten sidebøy i overkroppen."],
        "athlth-core-plank-shoulder-tap": ["Start i høy planke med hendene under skuldrene.", "Berør motsatt skulder uten å svinge hoftene og bytt rolig side."],
        "athlth-core-plank-jack": ["Start i høy planke med føttene sammen.", "Hopp føttene kontrollert ut og inn mens overkroppen er stabil."],
        "athlth-core-plank-walkout": ["Stå oppreist og bøy deg frem mot gulvet.", "Gå med hendene ut i planke og tilbake før du reiser deg."],
        "athlth-core-rkc-plank": ["Støtt deg på underarmene med stram mage og sete.", "Trekk albuene svakt mot tærne uten å bevege deg, og pust rolig."],
        "athlth-core-hollow-body-rock": ["Ligg på ryggen og hold korsryggen forsiktig ned mot underlaget.", "Løft skuldre og bein og vugg kontrollert uten å miste spennet."],
        "athlth-core-toe-touch-crunch": ["Ligg på ryggen med beina pekt opp mot taket.", "Løft skulderbladene og strekk hendene opp mot tærne før du senker rolig."],
        "athlth-core-standing-cable-woodchop": ["Stå sidelengs mot et kabelapparat med håndtaket høyt.", "Trekk diagonalt ned foran kroppen mens du holder stabil mage."],
        "athlth-core-half-kneeling-cable-chop": ["Sett ett kne i gulvet og hold overkroppen høy.", "Trekk kabelen skrått ned uten å lene deg, og bytt side."],
        "athlth-core-pallof-step-out": ["Stå sidelengs mot kabelen med håndtaket ved brystet.", "Press armene ut og ta et kontrollert sidesteg uten å rotere."],
        "athlth-core-banded-dead-bug-pulldown": ["Ligg på ryggen med knærne over hoftene og strikk festet bak hodet.", "Hold strikken i spenn mens du strekker ett bein kontrollert ut."],
        "athlth-core-bird-dog-row": ["Støtt en hånd og motsatt kne mot en stabil benk.", "Strekk det frie beinet bak og ro en lett manual uten å vri hoftene."],
        "athlth-core-side-plank-hip-dip": ["Start i sideplanke med albuen under skulderen.", "Senk hoften litt mot gulvet og løft rolig tilbake."],
        "athlth-core-side-plank-reach-through": ["Hold en sideplanke og strekk øverste arm mot taket.", "Før armen under overkroppen og roter rolig tilbake."],
        "athlth-core-bear-plank-shoulder-tap": ["Stå på alle fire og løft knærne noen centimeter fra gulvet.", "Berør motsatt skulder uten å flytte hoftene."],
        "athlth-core-windshield-wiper": ["Ligg på ryggen med armene ut til siden og beina løftet.", "Før beina et kort stykke side til side uten å miste kontrollen."],
        "athlth-core-stir-the-pot": ["Støtt underarmene på en treningsball i plankeposisjon.", "Tegn små sirkler med albuene mens du stabiliserer hoftene."],
        "athlth-core-swiss-ball-body-saw": ["Plasser underarmene på en stabil treningsball i planke.", "Flytt kroppen rolig litt frem og tilbake uten å svaie i ryggen."],
        "athlth-core-copenhagen-plank": ["Støtt øverste bein på en stabil, polstret benk i sideplanke.", "Løft hoften og hold kroppen rett mens innside lår jobber."],
        "athlth-core-suitcase-march": ["Hold én manual eller kettlebell langs den ene siden.", "Marsjer rolig på stedet uten å lene deg bort fra vekten."],
        "athlth-core-standing-knee-elbow-crunch": ["Stå oppreist med hendene lett ved hodet.", "Løft kneet mot albuen på samme side uten å dra i nakken."]
    ]

    func localizedExerciseInstructions(_ entry: ExerciseLibraryEntry) -> [String] {
        if ATHLTHLocalization.isNorwegian,
           let key = entry.sourceIdentifier,
           (entry.source == .repDB ||
            (entry.source == .athlthCatalog && key.hasPrefix("athlth-core-"))),
           let steps = Self.norwegianCoreInstructions[key] {
            return steps
        }
        return entry.exercise.instructions
    }

    func localizedExerciseName(_ entry: ExerciseLibraryEntry) -> String {
        guard ATHLTHLocalization.isNorwegian,
              let id = entry.sourceIdentifier,
              (entry.source == .repDB ||
               (entry.source == .athlthCatalog && id.hasPrefix("athlth-core-")))
        else { return entry.name }
        return Self.norwegianExerciseNames[id] ?? entry.name
    }

    private static let norwegianMuscleSearchTerms: [String: [String]] = [
        "core": ["mage", "magen", "magemuskler", "kjerne", "kjernemuskler", "buk", "skråmage"],
        "back": ["rygg", "ryggmuskler", "rygghev"],
        "lower back": ["korsrygg", "nedrerygg", "ryggstrekkere"],
        "chest": ["bryst"],
        "shoulders": ["skulder", "skuldre"],
        "glutes": ["sete", "rumpa", "setemuskler"],
        "quadriceps": ["forsidelår", "lår", "bein"],
        "hamstrings": ["bakside", "bakside lår"],
        "calves": ["legger", "tåhev"],
        "hip flexors": ["hoftebøyer", "hoftebøyere"]
    ]

    static func searchableNorwegianTerms(
        sourceIdentifier: String?,
        bodyPart: String?,
        primaryMuscles: [String]
    ) -> String {
        var words: [String] = []
        if let sourceIdentifier,
           let localized = norwegianExerciseNames[sourceIdentifier] {
            words.append(localized)
        }
        let groups = ([bodyPart].compactMap { $0 } + primaryMuscles)
            .map {
                $0.replacingOccurrences(of: "_", with: " ").lowercased()
            }
        for (muscle, synonyms) in norwegianMuscleSearchTerms {
            if groups.contains(where: { $0 == muscle || $0.contains(muscle) }) {
                words.append(contentsOf: synonyms)
            }
        }
        return words.joined(separator: " ")
    }

    var allExercises: [ExerciseLibraryEntry] {
        if let cachedAllExercises {
            return cachedAllExercises
        }

        let resolved =
            (
                customExercises +
                athlthCatalogExercises +
                repDBExercises
            )
            .reduce(
                into:
                    [UUID:
                        ExerciseLibraryEntry]()
            ) {
                result,
                entry in
                result[entry.id] =
                    entry
            }
            .values
            .sorted {
                $0.canonicalName
                    .localizedCaseInsensitiveCompare(
                        $1.canonicalName
                    ) ==
                    .orderedAscending
            }

        cachedAllExercises = resolved
        return resolved
    }

    var bodyParts: [String] {
        if let cachedBodyParts {
            return cachedBodyParts
        }

        let resolved =
            Array(
                Set(
                    allExercises.compactMap {
                        $0.bodyPart
                    }
                )
            )
            .sorted()

        cachedBodyParts = resolved
        return resolved
    }

    var equipmentOptions: [String] {
        if let cachedEquipmentOptions {
            return cachedEquipmentOptions
        }

        let resolved =
            Array(
                Set(
                    allExercises.flatMap {
                        $0.exercise.equipment
                    }
                )
            )
            .sorted()

        cachedEquipmentOptions = resolved
        return resolved
    }

    private func invalidateDerivedCaches() {
        cachedAllExercises = nil
        cachedBodyParts = nil
        cachedEquipmentOptions = nil
    }

    func refresh(force: Bool = false) async {
        await refreshATHLTHCatalog(
            force: force
        )

        if !force,
           !repDBExercises.isEmpty,
           let lastUpdated,
           Date().timeIntervalSince(lastUpdated) < 7 * 24 * 3_600 {
            return
        }

        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: datasetURL)
            request.timeoutInterval = 30
            request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw ExerciseLibraryError.httpStatus(http.statusCode)
            }

            let dataset = try JSONDecoder().decode(
                RepDBDataset.self,
                from: data
            )

            let mapped = dataset.exercises.map(mapRepDB)
            repDBExpectedCount = dataset.count ?? mapped.count
            repDBExercises = mapped
            invalidateDerivedCaches()
            lastUpdated = Date()
            persistRepDBCache(data)
        } catch {
            errorMessage = error.localizedDescription

            if repDBExercises.isEmpty {
                loadCachedRepDB()
            }
        }
    }

    func search(
        query: String,
        bodyPart: String? = nil,
        equipment: String? = nil
    ) -> [ExerciseLibraryEntry] {
        let cleanQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "nb_NO"))
            .lowercased()

        return allExercises.filter { entry in
            let matchesText: Bool
            if cleanQuery.isEmpty {
                matchesText = true
            } else {
                let haystack = [
                    entry.exercise.searchNames.joined(separator: " "),
                    entry.summary ?? "",
                    entry.bodyPart ?? "",
                    entry.exercise.primaryMuscles.joined(separator: " "),
                    entry.exercise.secondaryMuscles.joined(separator: " "),
                    entry.exercise.equipment.joined(separator: " "),
                    Self.searchableNorwegianTerms(
                        sourceIdentifier: entry.sourceIdentifier,
                        bodyPart: entry.bodyPart,
                        primaryMuscles: entry.exercise.primaryMuscles
                    )
                ]
                .joined(separator: " ")
                .folding(options: [.diacriticInsensitive, .caseInsensitive],
                         locale: Locale(identifier: "nb_NO"))
                .lowercased()

                let queryTokens =
                    cleanQuery
                        .split(whereSeparator: { $0.isWhitespace })
                        .map(String.init)

                matchesText =
                    queryTokens.allSatisfy {
                        haystack.contains($0)
                    }
            }

            let matchesBodyPart =
                bodyPart == nil ||
                bodyPart == "All" ||
                entry.bodyPart == bodyPart

            let matchesEquipment = equipment.map {
                $0 == "All" ||
                entry.exercise.equipment.contains($0)
            } ?? true

            return matchesText && matchesBodyPart && matchesEquipment
        }
    }

    func createCustomExercise(
        ownerID: UUID,
        name: String,
        instructions: [String],
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: [String],
        isVisibleOutsideOwnerLibrary: Bool,
        imageData: Data? = nil,
        videoURL: URL? = nil
    ) -> ExerciseLibraryEntry {
        let exerciseID = UUID()
        let imageURL = imageData.flatMap {
            try? saveCustomImageData($0, exerciseID: exerciseID)
        }

        let exercise = Exercise(
            id: exerciseID,
            origin: .custom,
            ownerID: ownerID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: instructions.cleanExerciseStrings,
            primaryMuscles: primaryMuscles.cleanExerciseStrings,
            secondaryMuscles: secondaryMuscles.cleanExerciseStrings,
            equipment: equipment.cleanExerciseStrings,
            imageURL: imageURL,
            isVisibleOutsideOwnerLibrary: isVisibleOutsideOwnerLibrary,
            videoURL: videoURL
        )

        let entry = ExerciseLibraryEntry(
            id: exercise.id,
            exercise: exercise,
            source: .custom,
            sourceIdentifier: nil,
            summary: nil,
            tips: [],
            category: "custom",
            difficulty: nil,
            bodyPart: primaryMuscles.cleanExerciseStrings.first,
            imageStartURL: imageURL,
            imagePeakURL: nil
        )

        customExercises.append(entry)
        customExercises.sort {
            $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
        }
        invalidateDerivedCaches()
        persistCustomExercises()
        return entry
    }

    func updateCustomExercise(_ exercise: Exercise) {
        guard exercise.origin == .custom, exercise.ownerID == accountID else { return }

        let entry = ExerciseLibraryEntry(
            id: exercise.id,
            exercise: exercise,
            source: .custom,
            sourceIdentifier: nil,
            summary: nil,
            tips: [],
            category: "custom",
            difficulty: nil,
            bodyPart: exercise.primaryMuscles.first,
            imageStartURL: exercise.imageURL,
            imagePeakURL: nil
        )

        if let index = customExercises.firstIndex(where: { $0.id == exercise.id }) {
            customExercises[index] = entry
        } else {
            customExercises.append(entry)
        }

        customExercises.sort {
            $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
        }
        invalidateDerivedCaches()
        persistCustomExercises()
    }

    func deleteCustomExercise(_ id: UUID) {
        if let entry = customExercises.first(where: { $0.id == id }),
           let imageURL = entry.exercise.imageURL,
           imageURL.isFileURL {
            try? FileManager.default.removeItem(at: imageURL)
        }

        customExercises.removeAll { $0.id == id }
        invalidateDerivedCaches()
        persistCustomExercises()
    }


    private func refreshATHLTHCatalog(
        force: Bool = false
    ) async {
        if !force,
           !athlthCatalogExercises.isEmpty,
           let lastATHLTHCatalogRefreshAt,
           Date().timeIntervalSince(
                lastATHLTHCatalogRefreshAt
           ) < 30 * 60 {
            return
        }

        do {
            let rows: [ATHLTHExerciseCatalogRecord] =
                try await client
                    .from("exercise_catalog")
                    .select(
                        "id,slug,name,summary,instructions,primary_muscles,secondary_muscles,equipment,category,difficulty,source_label,source_url,sort_order"
                    )
                    .eq("is_published", value: true)
                    .order("sort_order", ascending: true)
                    .execute()
                    .value

            lastATHLTHCatalogRefreshAt =
                Date()

            if !rows.isEmpty {
                let refreshed =
                    rows.map(mapATHLTHCatalog)

                let currentSignature =
                    athlthCatalogExercises.map {
                        "\($0.id.uuidString)|\($0.name)|\($0.exercise.primaryMuscles.joined(separator: ","))|\($0.exercise.secondaryMuscles.joined(separator: ","))"
                    }
                let refreshedSignature =
                    refreshed.map {
                        "\($0.id.uuidString)|\($0.name)|\($0.exercise.primaryMuscles.joined(separator: ","))|\($0.exercise.secondaryMuscles.joined(separator: ","))"
                    }

                if currentSignature !=
                    refreshedSignature {
                    athlthCatalogExercises =
                        refreshed
                    invalidateDerivedCaches()
                }
            }
        } catch {
            if athlthCatalogExercises.isEmpty {
                athlthCatalogExercises =
                    Self.fallbackATHLTHExercises
                invalidateDerivedCaches()
            }
        }
    }

    private func mapATHLTHCatalog(
        _ source: ATHLTHExerciseCatalogRecord
    ) -> ExerciseLibraryEntry {
        let exercise = Exercise(
            id: source.id,
            origin: .publicCatalog,
            ownerID: nil,
            name: source.name,
            instructions: source.instructions,
            primaryMuscles: source.primaryMuscles,
            secondaryMuscles: source.secondaryMuscles,
            equipment: source.equipment,
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: true,
            videoURL: nil
        )

        return ExerciseLibraryEntry(
            id: source.id,
            exercise: exercise,
            source: .athlthCatalog,
            sourceIdentifier: source.slug,
            summary: source.summary,
            tips: [],
            category: source.category,
            difficulty: source.difficulty,
            bodyPart: source.primaryMuscles.first,
            imageStartURL: nil,
            imagePeakURL: nil
        )
    }

    private func mapRepDB(_ source: RepDBExercise) -> ExerciseLibraryEntry {
        let startURL = source.images?.flat?.start
            .flatMap { URL(string: $0, relativeTo: imageBaseURL)?.absoluteURL }
        let peakURL = source.images?.flat?.peak
            .flatMap { URL(string: $0, relativeTo: imageBaseURL)?.absoluteURL }
        let mainURL = source.images?.flat?.main
            .flatMap { URL(string: $0, relativeTo: imageBaseURL)?.absoluteURL }

        let imageURL = startURL ?? mainURL ?? peakURL
        let equipment = source.equipment.map { [$0.humanizedRepDB] } ?? []

        let primaryMuscles =
            resolvedRepDBPrimaryMuscles(
                source
            )

        let exercise = Exercise(
            id: Self.stableUUID(for: "repdb:\(source.id)"),
            origin: .publicCatalog,
            ownerID: nil,
            name: source.nameEnglish,
            instructions: source.instructionsEnglish ?? [],
            primaryMuscles: primaryMuscles,
            secondaryMuscles: (source.secondaryMuscles ?? []).map(\.humanizedRepDB),
            equipment: equipment,
            imageURL: imageURL,
            isVisibleOutsideOwnerLibrary: true
        )

        return ExerciseLibraryEntry(
            id: exercise.id,
            exercise: exercise,
            source: .repDB,
            sourceIdentifier: source.id,
            summary: source.descriptionEnglish,
            tips: source.tipsEnglish ?? [],
            category: source.category?.humanizedRepDB,
            difficulty: source.difficulty?.humanizedRepDB,
            bodyPart: source.bodyPart?.humanizedRepDB,
            imageStartURL: startURL ?? mainURL,
            imagePeakURL: peakURL
        )
    }

    private func resolvedRepDBPrimaryMuscles(
        _ source: RepDBExercise
    ) -> [String] {
        let supplied =
            (source.primaryMuscles ?? [])
                .map(\.humanizedRepDB)
                .filter {
                    !$0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                }

        if !supplied.isEmpty {
            return supplied
        }

        guard let bodyPart =
                source.bodyPart?
                    .humanizedRepDB
                    .lowercased()
        else {
            return []
        }

        switch bodyPart {
        case "chest":
            return ["Chest"]
        case "back":
            return ["Back"]
        case "shoulders":
            return ["Shoulders"]
        case "upper arms":
            return ["Biceps", "Triceps"]
        case "lower arms":
            return ["Forearms"]
        case "core", "waist":
            return ["Core"]
        case "upper legs":
            return ["Quads", "Hamstrings", "Glutes"]
        case "lower legs":
            return ["Calves"]
        default:
            return []
        }
    }

    private func saveCustomImageData(
        _ data: Data,
        exerciseID: UUID
    ) throws -> URL {
        guard let directory = Self.customMediaDirectory else {
            throw ExerciseLibraryError.storageUnavailable
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let url = directory
            .appendingPathComponent(exerciseID.uuidString)
            .appendingPathExtension("image")

        try data.write(to: url, options: .atomic)
        return url
    }

    private func loadCachedRepDB() {
        guard let url = Self.repDBCacheURL,
              let data = try? Data(contentsOf: url),
              let dataset = try? JSONDecoder().decode(
                  RepDBDataset.self,
                  from: data
              )
        else {
            return
        }

        repDBExercises = dataset.exercises.map(mapRepDB)
        repDBExpectedCount = dataset.count ?? repDBExercises.count
        invalidateDerivedCaches()

        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) {
            lastUpdated = values.contentModificationDate
        }
    }

    private func persistRepDBCache(_ data: Data) {
        guard let url = Self.repDBCacheURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private func loadCustomExercises() {
        guard let accountID else { return }
        let decoded: [Exercise]
        if let stored = AccountLocalStorage.read([Exercise].self, name: "exerciseLibrary", userID: accountID) {
            decoded = stored
        } else if let url = Self.customExercisesURL,
                  let data = try? Data(contentsOf: url),
                  let legacy = try? JSONDecoder().decode([Exercise].self, from: data) {
            // The legacy file contains owner IDs. Only migrate this account's records.
            decoded = legacy.filter { $0.ownerID == accountID }
            AccountLocalStorage.write(decoded, name: "exerciseLibrary", userID: accountID)
        } else {
            decoded = []
        }

        customExercises = decoded.map { exercise in
            ExerciseLibraryEntry(
                id: exercise.id,
                exercise: exercise,
                source: .custom,
                sourceIdentifier: nil,
                summary: nil,
                tips: [],
                category: "custom",
                difficulty: nil,
                bodyPart: exercise.primaryMuscles.first,
                imageStartURL: exercise.imageURL,
                imagePeakURL: nil
            )
        }
        invalidateDerivedCaches()
    }

    private func persistCustomExercises() {
        guard let accountID else { return }
        AccountLocalStorage.write(customExercises.map(\.exercise), name: "exerciseLibrary", userID: accountID)
        ATHLTHTrainingDataChangeSignal.post(userID: accountID)
    }


    private static var fallbackATHLTHExercises:
        [ExerciseLibraryEntry] {
        let values:
            [(UUID, String, String, [String], [String], [String])] = [
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000001")!,
                    "SkiErg",
                    "Full-body ski ergometer station for sustained pulling power and aerobic output.",
                    ["Back", "Core"],
                    ["Shoulders", "Arms", "Glutes"],
                    ["SkiErg"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000002")!,
                    "Sled Push",
                    "Heavy horizontal push performed over a prescribed distance.",
                    ["Quads", "Glutes"],
                    ["Calves", "Core"],
                    ["Sled"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000003")!,
                    "Sled Pull",
                    "Rope sled pull combining posterior-chain, back and grip endurance.",
                    ["Back", "Glutes"],
                    ["Biceps", "Core", "Hamstrings"],
                    ["Sled", "Rope"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000004")!,
                    "Burpee Broad Jump",
                    "Chest-to-floor burpee followed by a two-foot broad jump.",
                    ["Quads", "Glutes", "Chest", "Core"],
                    ["Shoulders", "Calves"],
                    ["Bodyweight"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000005")!,
                    "Rowing",
                    "Indoor rowing station performed for distance.",
                    ["Back", "Quads"],
                    ["Glutes", "Hamstrings", "Arms", "Core"],
                    ["RowErg"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000006")!,
                    "Farmers Carry",
                    "Loaded carry with one implement in each hand.",
                    ["Forearms", "Core"],
                    ["Upper Back", "Shoulders", "Glutes"],
                    ["Kettlebells", "Dumbbells"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000007")!,
                    "Sandbag Walking Lunge",
                    "Alternating walking lunges performed while carrying a sandbag.",
                    ["Quads", "Glutes"],
                    ["Hamstrings", "Core"],
                    ["Sandbag"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000008")!,
                    "Wall Ball",
                    "Squat-to-throw movement using a medicine ball and wall target.",
                    ["Quads", "Glutes"],
                    ["Shoulders", "Core"],
                    ["Medicine Ball", "Wall Target"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000009")!,
                    "Stationary Lunge",
                    "Alternating in-place lunges for repetitions.",
                    ["Quads", "Glutes"],
                    ["Hamstrings", "Core"],
                    ["Bodyweight"]
                ),
                (
                    UUID(uuidString: "C2000000-0000-0000-0000-000000000010")!,
                    "Hand-Release Push-Up",
                    "Push-up variation with a brief hand release at the bottom.",
                    ["Chest", "Triceps"],
                    ["Shoulders", "Core"],
                    ["Bodyweight"]
                )
            ]

        return values.map {
            id, name, summary, primary, secondary, equipment in
            let exercise = Exercise(
                id: id,
                origin: .publicCatalog,
                ownerID: nil,
                name: name,
                instructions: [],
                primaryMuscles: primary,
                secondaryMuscles: secondary,
                equipment: equipment,
                imageURL: nil,
                isVisibleOutsideOwnerLibrary: true
            )

            return ExerciseLibraryEntry(
                id: id,
                exercise: exercise,
                source: .athlthCatalog,
                sourceIdentifier:
                    "athlth:" +
                    name.lowercased()
                        .replacingOccurrences(
                            of: " ",
                            with: "-"
                        ),
                summary: summary,
                tips: [],
                category: "functional",
                difficulty: "All levels",
                bodyPart: primary.first,
                imageStartURL: nil,
                imagePeakURL: nil
            )
        }
    }

    private static var storageDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("ExerciseLibrary", isDirectory: true)
    }

    private static var repDBCacheURL: URL? {
        storageDirectory?.appendingPathComponent(
            "repdb-exercises-cache.json",
            isDirectory: false
        )
    }

    private static var customExercisesURL: URL? {
        storageDirectory?.appendingPathComponent(
            "custom-exercises.json",
            isDirectory: false
        )
    }

    private static var customMediaDirectory: URL? {
        storageDirectory?.appendingPathComponent(
            "CustomMedia",
            isDirectory: true
        )
    }

    private static func stableUUID(for string: String) -> UUID {
        let digest = SHA256.hash(data: Data(string.utf8))
        let hex = digest.prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()

        let value =
            "\(hex.prefix(8))-" +
            "\(hex.dropFirst(8).prefix(4))-" +
            "\(hex.dropFirst(12).prefix(4))-" +
            "\(hex.dropFirst(16).prefix(4))-" +
            "\(hex.dropFirst(20).prefix(12))"

        return UUID(uuidString: value) ?? UUID()
    }
}

enum ExerciseLibraryError: LocalizedError {
    case httpStatus(Int)
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "RepDB exercise library returned HTTP \(status)."
        case .storageUnavailable:
            return "ATHLTH could not store the custom exercise media."
        }
    }
}


private struct ATHLTHExerciseCatalogRecord: Decodable {
    let id: UUID
    let slug: String
    let name: String
    let summary: String
    let instructions: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]
    let category: String
    let difficulty: String
    let sourceLabel: String?
    let sourceURL: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case summary
        case instructions
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case equipment
        case category
        case difficulty
        case sourceLabel = "source_label"
        case sourceURL = "source_url"
        case sortOrder = "sort_order"
    }
}

private struct RepDBDataset: Decodable {
    let count: Int?
    let exercises: [RepDBExercise]
}

private struct RepDBExercise: Decodable {
    let id: String
    let nameEnglish: String
    let descriptionEnglish: String?
    let instructionsEnglish: [String]?
    let tipsEnglish: [String]?
    let category: String?
    let difficulty: String?
    let equipment: String?
    let bodyPart: String?
    let primaryMuscles: [String]?
    let secondaryMuscles: [String]?
    let images: RepDBImages?

    enum CodingKeys: String, CodingKey {
        case id
        case nameEnglish = "name_en"
        case descriptionEnglish = "description_en"
        case instructionsEnglish = "instructions_en"
        case tipsEnglish = "tips_en"
        case category
        case difficulty
        case equipment
        case bodyPart = "body_part"
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case images
    }
}

private struct RepDBImages: Decodable {
    let flat: RepDBFlatImages?
}

private struct RepDBFlatImages: Decodable {
    let start: String?
    let peak: String?
    let main: String?
}

private extension String {
    var humanizedRepDB: String {
        replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private extension Array where Element == String {
    var cleanExerciseStrings: [String] {
        self
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
