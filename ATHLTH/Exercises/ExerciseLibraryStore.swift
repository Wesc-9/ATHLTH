import CryptoKit
import Foundation

/// Local demonstration clips remain private on this device. Studio videos
/// are never uploaded or described as AI-generated training instructions.
enum ExerciseStudioVideoStorage {
    static let maximumBytes: Int = 120 * 1024 * 1024
    private static let formats: Set<String> = ["mp4", "mov", "m4v"]

    private static var directory: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?
            .appendingPathComponent("ATHLTH", isDirectory: true)
            .appendingPathComponent("ExerciseLibrary", isDirectory: true)
            .appendingPathComponent("CustomMedia", isDirectory: true)
    }

    static func importVideo(from source: URL) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard formats.contains(ext) else {
            throw ExerciseStudioVideoError.unsupportedFormat
        }
        guard let directory else { throw ExerciseStudioVideoError.storageUnavailable }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maximumBytes { throw ExerciseStudioVideoError.fileTooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(
            "exercise-video-" + UUID().uuidString
        ).appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            let copiedSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard copiedSize > 0 && copiedSize <= maximumBytes else {
                throw copiedSize > maximumBytes
                    ? ExerciseStudioVideoError.fileTooLarge
                    : ExerciseStudioVideoError.invalidVideo
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Never delete media outside ATHLTH's own video namespace.
    static func discardOwnedVideo(_ url: URL?) {
        guard let url, url.isFileURL, let directory,
              url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              url.lastPathComponent.hasPrefix("exercise-video-"),
              formats.contains(url.pathExtension.lowercased()) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func isOwnedVideo(_ url: URL?) -> Bool {
        guard let url, url.isFileURL, let directory else { return false }
        return url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL &&
            url.lastPathComponent.hasPrefix("exercise-video-")
    }
}

enum ExerciseStudioVideoError: LocalizedError {
    case unsupportedFormat
    case fileTooLarge
    case invalidVideo
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return ATHLTHLocalization.choose(
                english: "Choose an MP4, MOV or M4V video.",
                norwegian: "Velg en MP4-, MOV- eller M4V-video."
            )
        case .fileTooLarge:
            return ATHLTHLocalization.choose(
                english: "Maximum video size is 120 MB.",
                norwegian: "Videoen kan ikke være større enn 120 MB."
            )
        case .invalidVideo:
            return ATHLTHLocalization.choose(
                english: "The selected video is empty or invalid.",
                norwegian: "Den valgte videoen er tom eller ugyldig."
            )
        case .storageUnavailable:
            return ATHLTHLocalization.choose(
                english: "Video storage is unavailable.",
                norwegian: "Videolagring er ikke tilgjengelig."
            )
        }
    }
}

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
            ExerciseLibraryStore.nativeATHLTHExercises +
            ExerciseLibraryStore.fallbackATHLTHExercises
    @Published private(set) var repDBExercises: [ExerciseLibraryEntry] = []
    @Published private(set) var repDBExpectedCount: Int?
    @Published private(set) var customExercises: [ExerciseLibraryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?

    // RepDB is a published, downloadable data snapshot rather than a live exercise API.
    // Keep a persisted local copy so existing users can train during an outage.
    private let datasetURL = URL(string: "https://exercise-dataset.com/exercises.json")!
    private let imageBaseURL = URL(string: "https://exercise-dataset.com/")!

    /// Full catalog and images packaged into the app at release build time.
    /// Users can browse every shipped exercise on the very first offline launch.
    private static var bundledRepDBRoot: URL? {
        Bundle.main.url(forResource: "RepDBOffline", withExtension: "bundle")
    }

    private var accountID: UUID?
    private var cachedAllExercises: [ExerciseLibraryEntry]?
    private var cachedBodyParts: [String]?
    private var cachedEquipmentOptions: [String]?

    private struct SearchRequest: Equatable {
        let query: String
        let bodyPart: String?
        let equipment: String?
    }
    private var cachedSearchText: [UUID: String] = [:]
    private var lastSearchRequest: SearchRequest?
    private var lastSearchTranslationRevision = -1
    private var lastSearchResults: [ExerciseLibraryEntry] = []

    init() {
        // Prefer a valid persisted snapshot; fall back to the bundled offline catalog.
        // This avoids decoding the same large exercise dataset twice at startup.
        loadCachedRepDB()
        if repDBExercises.isEmpty { loadBundledRepDB() }
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
        case "legs":
            norwegian = "Lår"
        case "adductors", "inner thigh":
            norwegian = "Innsiden av lårene"
        case "hip flexors":
            norwegian = "Hoftebøyere"
        case "lower back", "erector spinae":
            norwegian = "Nedre rygg"
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
            norwegian = "Sete"
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

    // Preserve the 20 retired catalog identifiers to exclude only these
    // entries from NEW exercise selection. Keep the underlying records and
    // translations intact for previously saved workouts on older versions.
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

    private static let retiredCoreSlugSet = Set(originalCoreSlugs)

    static func isRetiredOriginalCoreSlug(_ slug: String?) -> Bool {
        guard let slug else { return false }
        return retiredCoreSlugSet.contains(slug)
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
        guard ATHLTHLocalization.isNorwegian else {
            return entry.exercise.instructions
        }
        if let reviewed = NorwegianExerciseText.record(
            for: entry.sourceIdentifier
        )?.instructions, !reviewed.isEmpty {
            return reviewed
        }
        if let key = entry.sourceIdentifier {
            if let native = Self.nativeNorwegianInstructions[key] {
                return native
            }
            if (entry.source == .repDB ||
                (entry.source == .athlthCatalog &&
                 key.hasPrefix("athlth-core-"))),
               let steps = Self.norwegianCoreInstructions[key] {
                return steps
            }
        }
        guard entry.source == .repDB else { return entry.exercise.instructions }
        return entry.exercise.instructions.map {
            NorwegianExerciseAutoTranslation.shared.translated($0) ?? $0
        }
    }

    func localizedExerciseName(_ entry: ExerciseLibraryEntry) -> String {
        guard ATHLTHLocalization.isNorwegian, entry.source != .custom else {
            return entry.name
        }
        if let reviewed = NorwegianExerciseText.name(for: entry.sourceIdentifier),
           !reviewed.isEmpty {
            return reviewed
        }
        if let id = entry.sourceIdentifier {
            if let native = Self.nativeNorwegianNames[id] { return native }
            if let alias = Self.norwegianExerciseNames[id] { return alias }
        }
        let curated = ATHLTHExerciseNameLocalization.norwegianName(for: entry.name)
        if curated != entry.name { return curated }
        return NorwegianExerciseAutoTranslation.shared.translated(entry.name)
            ?? entry.name
    }

    func localizedExerciseSummary(_ entry: ExerciseLibraryEntry) -> String? {
        guard ATHLTHLocalization.isNorwegian else { return entry.summary }
        if let reviewed = NorwegianExerciseText.record(
            for: entry.sourceIdentifier
        )?.summary, !reviewed.isEmpty {
            return reviewed
        }
        if let id = entry.sourceIdentifier,
           let native = Self.nativeNorwegianInstructions[id] {
            return native.first
        }
        guard let original = entry.summary else { return nil }
        if entry.source == .repDB {
            return NorwegianExerciseAutoTranslation.shared.translated(original)
                ?? original
        }
        return original
    }

    func localizedExerciseTips(_ entry: ExerciseLibraryEntry) -> [String] {
        guard ATHLTHLocalization.isNorwegian, entry.source == .repDB else {
            return entry.tips
        }
        if let reviewed = NorwegianExerciseText.record(
            for: entry.sourceIdentifier
        )?.tips, !reviewed.isEmpty {
            return reviewed
        }
        return entry.tips.map {
            NorwegianExerciseAutoTranslation.shared.translated($0) ?? $0
        }
    }

    func localizedEquipmentTitle(_ value: String) -> String {
        NorwegianExerciseText.equipment(value)
    }

    func localizedDifficultyTitle(_ value: String) -> String {
        NorwegianExerciseText.difficulty(value)
    }

    func localizedCategoryTitle(_ value: String) -> String {
        NorwegianExerciseText.category(value)
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
        if let sourceIdentifier {
            if let localized = norwegianExerciseNames[sourceIdentifier] {
                words.append(localized)
            }
            if let localized = nativeNorwegianNames[sourceIdentifier] {
                words.append(localized)
            }
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
            .filter { entry in
                // Retire the old original-core batch. Keep legacy cached
                // entries for references from previously recorded workouts.
                entry.source != .athlthCatalog ||
                    !Self.isRetiredOriginalCoreSlug(entry.sourceIdentifier)
            }
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

    /// The athlete sees only familiar major groups. Detailed RepDB names
    /// remain unchanged in exercise records, muscle maps, saved plans, etc.
    static let commonMuscleFilters: [String] = [
        "Chest", "Back", "Shoulders", "Biceps", "Triceps",
        "Core", "Glutes", "Legs", "Calves"
    ]

    /// Collapse technical muscle and body-part names into the simple library
    /// filters. This is presentation/search mapping, not a metadata rewrite.
    static func canonicalMuscleFilter(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()

        if key == "all" { return "All" }
        if ["chest", "pecs", "pectoral"].contains(key) ||
            key.contains("pectoralis") {
            return "Chest"
        }
        if ["back", "lower back", "upper back", "lats",
            "traps", "rhomboids", "erector spinae",
            "spinal erectors"].contains(key) ||
            key.contains("latissimus") || key.contains("rhomboid") ||
            key.contains("trapezius") || key.contains("spinae") {
            return "Back"
        }
        if ["shoulders", "shoulder", "rotator cuff"].contains(key) ||
            key.contains("deltoid") || key.contains("supraspinatus") ||
            key.contains("infraspinatus") {
            return "Shoulders"
        }
        if key.contains("tricep") || key.contains("anconeus") {
            return "Triceps"
        }
        if ["biceps", "brachialis", "brachioradialis",
            "forearms", "forearm", "lower arms", "lower arm"].contains(key) ||
            key.contains("bicep") || key.contains("brachialis") ||
            key.contains("brachioradialis") {
            return "Biceps"
        }
        if ["core", "waist", "abs", "abdominals",
            "abdominal", "obliques", "oblique"].contains(key) ||
            key.contains("abdomin") || key.contains("oblique") {
            return "Core"
        }
        if ["glutes", "glute", "buttocks", "hips",
            "hip abductors", "abductors", "outer thigh",
            "piriformis"].contains(key) ||
            key.contains("gluteus") || key.contains("abductor") {
            return "Glutes"
        }
        if ["calves", "calf", "lower legs", "lower leg",
            "gastrocnemius", "soleus", "tibialis anterior"].contains(key) ||
            key.contains("gastrocnemius") || key.contains("soleus") ||
            key.contains("tibialis") {
            return "Calves"
        }
        if ["legs", "leg", "upper legs", "upper leg",
            "thighs", "thigh", "quads", "quadriceps", "hamstrings",
            "adductors", "adductor", "inner thigh", "hip flexors",
            "hip flexor", "rectus femoris", "sartorius",
            "iliopsoas", "gracilis"].contains(key) ||
            key.contains("quadricep") || key.contains("hamstring") ||
            key.contains("adductor") || key.contains("vastus") {
            return "Legs"
        }
        return raw
    }

    var bodyParts: [String] {
        Self.commonMuscleFilters
    }

    var equipmentOptions: [String] {
        if let cachedEquipmentOptions {
            return cachedEquipmentOptions
        }

        let resolved =
            Array(
                Set(
                    selectableExercises.flatMap {
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
        cachedSearchText = [:]
        lastSearchRequest = nil
        lastSearchTranslationRevision = -1
        lastSearchResults = []
    }

    /// Fetch only when needed. An existing on-device RepDB snapshot is never
    /// replaced by an error, a failed download or an implausibly small catalog.
    /// Manual refresh works even when the last successful sync is recent.
    func refresh(force: Bool = false) async {
        if !force, !repDBExercises.isEmpty, let lastUpdated,
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
            request.cachePolicy = force
                ? .reloadIgnoringLocalCacheData
                : .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw ExerciseLibraryError.httpStatus(http.statusCode)
            }

            let dataset = try JSONDecoder().decode(RepDBDataset.self, from: data)
            let mapped = dataset.exercises.map(mapRepDB)
            guard mapped.count >= max(400, repDBExercises.count),
                  Set(mapped.map(\.id)).count == mapped.count else {
                throw ExerciseLibraryError.invalidDataset
            }

            // Only switch the visible library after a complete validated decode.
            repDBExercises = mapped
            repDBExpectedCount = dataset.count ?? mapped.count
            lastUpdated = Date()
            invalidateDerivedCaches()
            persistRepDBCache(data)
        } catch {
            errorMessage = error.localizedDescription
            if repDBExercises.isEmpty { loadCachedRepDB() }
        }
    }

    /// Keep historical native exercise IDs available for old workout logs,
    /// but offer RepDB (and personal exercises) as the primary choices.
    var selectableExercises: [ExerciseLibraryEntry] {
        guard !repDBExercises.isEmpty else { return allExercises }
        return allExercises.filter { $0.source == .repDB || $0.source == .custom }
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

        let request = SearchRequest(query: cleanQuery, bodyPart: bodyPart, equipment: equipment)
        let translationRevision = NorwegianExerciseAutoTranslation.shared.revision
        if lastSearchRequest == request &&
           lastSearchTranslationRevision == translationRevision {
            return lastSearchResults
        }
        let queryTokens = cleanQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        let selectedBodyPart = bodyPart.flatMap { $0 == "All" ? nil : Self.canonicalMuscleFilter($0) }
        let matches = selectableExercises.filter { entry in
            let matchesBodyPart: Bool
            if let selected = selectedBodyPart {
                matchesBodyPart =
                    (entry.bodyPart.map {
                        Self.canonicalMuscleFilter($0)
                            .localizedCaseInsensitiveCompare(selected) == .orderedSame
                    } ?? false) ||
                    entry.exercise.primaryMuscles.contains {
                        Self.canonicalMuscleFilter($0)
                            .localizedCaseInsensitiveCompare(selected) == .orderedSame
                    }
            } else {
                matchesBodyPart = true
            }

            let matchesEquipment = equipment.map {
                $0 == "All" ||
                entry.exercise.equipment.contains($0)
            } ?? true


            guard matchesBodyPart && matchesEquipment else { return false }
            let matchesText: Bool
            if cleanQuery.isEmpty {
                matchesText = true
            } else {
                let haystack: String
                if let cached = cachedSearchText[entry.id] {
                    haystack = cached
                } else {
                    haystack = [
                        entry.exercise.searchNames.joined(separator: " "),
                        entry.summary ?? "",
                        entry.bodyPart ?? "",
                        entry.exercise.primaryMuscles.joined(separator: " "),
                        entry.exercise.secondaryMuscles.joined(separator: " "),
                        entry.exercise.equipment.joined(separator: " "),
                        ATHLTHExerciseNameLocalization.norwegianName(for: entry.name),
                        entry.exercise.equipment
                            .map(NorwegianExerciseText.equipment)
                            .joined(separator: " "),
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
                    cachedSearchText[entry.id] = haystack
                }

                let liveNorwegianName = (
                    NorwegianExerciseAutoTranslation.shared.translated(entry.name) ?? ""
                )
                .folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "nb_NO")
                )
                .lowercased()
                matchesText = queryTokens.allSatisfy {
                    haystack.contains($0) || liveNorwegianName.contains($0)
                }
            }

            return matchesText
        }
        lastSearchRequest = request
        lastSearchTranslationRevision = translationRevision
        lastSearchResults = matches
        return matches
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

    /// Import only when an athlete explicitly taps "Add to my exercises".
    /// The receiving account owns its private copy; local media and remote
    /// access tokens from the sender never cross the account boundary.
    @discardableResult
    func importSharedExercise(
        _ source: ExerciseSnapshot,
        ownerID: UUID,
        sourceExerciseID: UUID? = nil
    ) -> ExerciseLibraryEntry? {
        guard accountID == ownerID,
              let safe = ATHLTHExerciseReferenceResolver.safeImportedSnapshot(
                source, fallbackTitle: source.name
              ) else { return nil }

        if let sourceExerciseID,
           let existing = customExercises.first(where: {
               $0.exercise.sharedSourceExerciseID == sourceExerciseID
           }) {
            return existing
        }

        // Names do not prove two personal exercises are identical. Never
        // overwrite the receiver's exercise; give the imported copy a unique
        // name if a different local record already uses that title.
        var localName = safe.name
        let used = Set(customExercises.map {
            ATHLTHExerciseReferenceResolver.key($0.canonicalName)
        })
        if used.contains(ATHLTHExerciseReferenceResolver.key(localName)) {
            let suffix = ATHLTHLocalization.choose(
                english: " (shared copy)", norwegian: " (delt kopi)"
            )
            localName = safe.name + suffix
            var counter = 2
            while used.contains(ATHLTHExerciseReferenceResolver.key(localName)) {
                localName = safe.name + suffix + " \(counter)"
                counter += 1
            }
        }

        let imported = createCustomExercise(
            ownerID: ownerID, name: localName,
            instructions: safe.instructions,
            primaryMuscles: safe.primaryMuscles,
            secondaryMuscles: safe.secondaryMuscles ?? [],
            equipment: safe.equipment,
            isVisibleOutsideOwnerLibrary: false
        )
        guard let sourceExerciseID else { return imported }
        var owned = imported.exercise
        owned.sharedSourceExerciseID = sourceExerciseID
        updateCustomExercise(owned)
        return customExercises.first(where: { $0.id == owned.id }) ?? imported
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

        let videoURL = customExercises.first(where: { $0.id == id })?.exercise.videoURL
        customExercises.removeAll { $0.id == id }
        ExerciseStudioVideoStorage.discardOwnedVideo(videoURL)
        invalidateDerivedCaches()
        persistCustomExercises()
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
            imageStartURL:
                bundledRepDBImageURL(source.images?.flat?.start)
                ?? bundledRepDBImageURL(source.images?.flat?.main)
                ?? startURL ?? mainURL,
            imagePeakURL:
                bundledRepDBImageURL(source.images?.flat?.peak)
                ?? peakURL
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
            // An upper-arm exercise does not train both muscles equally.
            // Avoid labeling a triceps movement as a biceps exercise.
            let name = source.nameEnglish.lowercased()
            if name.contains("tricep") || name.contains("pushdown") ||
                name.contains("push-down") || name.contains("extension") {
                return ["Triceps"]
            }
            if name.contains("bicep") || name.contains("curl") ||
                name.contains("preacher") || name.contains("hammer") {
                return ["Biceps"]
            }
            return ["Upper Arms"]
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

    /// Preserve a custom exercise's UUID when replacing its artwork.
    func updateCustomImageData(_ data: Data, for exerciseID: UUID) throws -> URL {
        guard customExercises.contains(where: { $0.id == exerciseID }) else {
            throw ExerciseLibraryError.storageUnavailable
        }
        return try saveCustomImageData(data, exerciseID: exerciseID)
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

    private func bundledRepDBImageURL(_ relativePath: String?) -> URL? {
        guard let relativePath,
              relativePath.hasPrefix("images/flat/"),
              relativePath.hasSuffix(".webp"),
              !relativePath.split(separator: "/").contains(".."),
              let root = Self.bundledRepDBRoot else { return nil }
        let url = root.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadBundledRepDB() {
        guard let root = Self.bundledRepDBRoot,
              let data = try? Data(contentsOf: root.appendingPathComponent("exercises.json")),
              let dataset = try? JSONDecoder().decode(RepDBDataset.self, from: data) else {
            return
        }
        let bundled = dataset.exercises.map(mapRepDB)
        guard bundled.count >= 400,
              Set(bundled.map(\.id)).count == bundled.count else { return }
        repDBExercises = bundled
        repDBExpectedCount = dataset.count ?? bundled.count
        lastUpdated = Date()
        invalidateDerivedCaches()
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

        let restored = dataset.exercises.map(mapRepDB)
        // Do not promote an old broken/partial cache to a usable catalog.
        guard restored.count >= max(400, repDBExercises.count),
              Set(restored.map(\.id)).count == restored.count else { return }
        repDBExercises = restored
        repDBExpectedCount = dataset.count ?? restored.count
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



    /// Curated ATHLTH exercises are bundled with the app and always work offline.
    /// Stable identifiers must never change: plans and workout history refer to them.
    private struct NativeExerciseSeed {
        let slug: String
        let name: String
        let norwegianName: String
        let primary: String
        let secondary: [String]
        let equipment: [String]
        let englishInstruction: String
        let norwegianInstruction: String
    }

    private static let nativeSeeds: [NativeExerciseSeed] = [
            .init(slug: "bench-press", name: "Bench Press", norwegianName: "Benkpress",
                  primary: "Chest", secondary: ["Triceps", "Shoulders"], equipment: ["Barbell", "Bench"],
                  englishInstruction: "Lower the bar under control to your chest and press up with steady feet.",
                  norwegianInstruction: "Senk stangen kontrollert mot brystet og press opp med føttene stabilt i gulvet."),
            .init(slug: "incline-bench-press", name: "Incline Bench Press", norwegianName: "Skråbenk med stang",
                  primary: "Chest", secondary: ["Shoulders", "Triceps"], equipment: ["Barbell", "Bench"],
                  englishInstruction: "Set the bench on an incline, lower the bar toward the upper chest and press up.",
                  norwegianInstruction: "Still benken på skrå, senk stangen mot øvre del av brystet og press opp."),
            .init(slug: "dumbbell-bench-press", name: "Dumbbell Bench Press", norwegianName: "Benkpress med manualer",
                  primary: "Chest", secondary: ["Triceps", "Shoulders"], equipment: ["Dumbbells", "Bench"],
                  englishInstruction: "Lower both dumbbells beside the chest and press vertically without bouncing.",
                  norwegianInstruction: "Senk manualene ved siden av brystet og press kontrollert opp uten å sprette."),
            .init(slug: "dumbbell-fly", name: "Dumbbell Fly", norwegianName: "Flyes med manualer",
                  primary: "Chest", secondary: ["Shoulders"], equipment: ["Dumbbells", "Bench"],
                  englishInstruction: "Open the arms with slightly bent elbows and bring them back above the chest.",
                  norwegianInstruction: "Åpne armene med lett bøy i albuene, og før manualene sammen over brystet."),
            .init(slug: "push-up", name: "Push-Up", norwegianName: "Armheving",
                  primary: "Chest", secondary: ["Triceps", "Core"], equipment: ["Bodyweight"],
                  englishInstruction: "Keep a straight body, lower your chest between the hands and push back up.",
                  norwegianInstruction: "Hold kroppen strak, senk brystet mellom hendene og press deg opp igjen."),
            .init(slug: "chest-press-machine", name: "Chest Press Machine", norwegianName: "Brystpress i apparat",
                  primary: "Chest", secondary: ["Triceps", "Shoulders"], equipment: ["Machine"],
                  englishInstruction: "Adjust the seat and press the handles forward while keeping shoulders stable.",
                  norwegianInstruction: "Juster setet og press håndtakene frem med skuldrene stabilt mot ryggstøtten."),
            .init(slug: "cable-fly", name: "Cable Fly", norwegianName: "Kabel-flyes",
                  primary: "Chest", secondary: ["Shoulders"], equipment: ["Cable"],
                  englishInstruction: "Bring the handles together in front of the chest with steady elbows.",
                  norwegianInstruction: "Før håndtakene sammen foran brystet med rolig tempo og stabile albuer."),
            .init(slug: "pull-up", name: "Pull-Up", norwegianName: "Pull-ups",
                  primary: "Back", secondary: ["Biceps", "Core"], equipment: ["Pull-up Bar"],
                  englishInstruction: "Pull your chest toward the bar without swinging and lower with control.",
                  norwegianInstruction: "Trekk brystet opp mot stangen uten å svinge, og senk deg kontrollert."),
            .init(slug: "lat-pulldown", name: "Lat Pulldown", norwegianName: "Nedtrekk",
                  primary: "Back", secondary: ["Biceps"], equipment: ["Cable"],
                  englishInstruction: "Pull the bar toward the upper chest while keeping the torso mostly upright.",
                  norwegianInstruction: "Trekk stangen mot øvre bryst mens du holder overkroppen mest mulig oppreist."),
            .init(slug: "seated-cable-row", name: "Seated Cable Row", norwegianName: "Sittende kabelroing",
                  primary: "Back", secondary: ["Biceps"], equipment: ["Cable"],
                  englishInstruction: "Row toward the lower ribs while keeping the back neutral and shoulders low.",
                  norwegianInstruction: "Trekk håndtaket mot nedre ribbein med nøytral rygg og lave skuldre."),
            .init(slug: "barbell-row", name: "Barbell Bent-Over Row", norwegianName: "Foroverbøyd stangroing",
                  primary: "Back", secondary: ["Biceps", "Core"], equipment: ["Barbell"],
                  englishInstruction: "Hinge at the hips, brace the trunk and pull the bar toward the abdomen.",
                  norwegianInstruction: "Bøy i hoften, stram kjernen og trekk stangen inn mot magen."),
            .init(slug: "one-arm-dumbbell-row", name: "One-Arm Dumbbell Row", norwegianName: "Enarms roing med manual",
                  primary: "Back", secondary: ["Biceps"], equipment: ["Dumbbells", "Bench"],
                  englishInstruction: "Support your body, pull the dumbbell toward the hip and lower slowly.",
                  norwegianInstruction: "Støtt kroppen, trekk manualen mot hoften og senk rolig."),
            .init(slug: "chest-supported-row", name: "Chest-Supported Row", norwegianName: "Bryststøttet roing",
                  primary: "Back", secondary: ["Biceps"], equipment: ["Dumbbells", "Bench"],
                  englishInstruction: "Keep your chest on the bench and row the weights without lifting the torso.",
                  norwegianInstruction: "Hold brystet mot benken og ro manualene uten å løfte overkroppen."),
            .init(slug: "back-extension", name: "Back Extension", norwegianName: "Rygghev",
                  primary: "Back", secondary: ["Glutes", "Hamstrings"], equipment: ["Back Extension Bench"],
                  englishInstruction: "Hinge at the hips and raise the torso until the body is straight.",
                  norwegianInstruction: "Bøy i hoften og løft overkroppen til kroppen danner en rett linje."),
            .init(slug: "overhead-press", name: "Barbell Overhead Press", norwegianName: "Skulderpress med stang",
                  primary: "Shoulders", secondary: ["Triceps", "Core"], equipment: ["Barbell"],
                  englishInstruction: "Press the bar straight overhead while keeping your ribs down.",
                  norwegianInstruction: "Press stangen rett over hodet mens du holder ribbeina nede."),
            .init(slug: "dumbbell-shoulder-press", name: "Dumbbell Shoulder Press", norwegianName: "Skulderpress med manualer",
                  primary: "Shoulders", secondary: ["Triceps"], equipment: ["Dumbbells"],
                  englishInstruction: "Press the dumbbells overhead with control and avoid arching the back.",
                  norwegianInstruction: "Press manualene kontrollert over hodet uten å svaie i ryggen."),
            .init(slug: "lateral-raise", name: "Dumbbell Lateral Raise", norwegianName: "Sidehev med manualer",
                  primary: "Shoulders", secondary: [], equipment: ["Dumbbells"],
                  englishInstruction: "Raise the arms to about shoulder height with a soft bend in the elbows.",
                  norwegianInstruction: "Løft armene til omtrent skulderhøyde med lett bøy i albuene."),
            .init(slug: "rear-delt-fly", name: "Rear Delt Fly", norwegianName: "Omvendt flyes",
                  primary: "Shoulders", secondary: ["Back"], equipment: ["Dumbbells"],
                  englishInstruction: "Hinge forward and open the arms sideways without shrugging.",
                  norwegianInstruction: "Len deg frem og før armene ut til siden uten å trekke skuldrene opp."),
            .init(slug: "face-pull", name: "Face Pull", norwegianName: "Face pull",
                  primary: "Shoulders", secondary: ["Back"], equipment: ["Cable"],
                  englishInstruction: "Pull the rope toward face height with elbows high and shoulders relaxed.",
                  norwegianInstruction: "Trekk tauet mot ansiktshøyde med høye albuer og avslappede skuldre."),
            .init(slug: "dumbbell-curl", name: "Dumbbell Biceps Curl", norwegianName: "Bicepscurl med manualer",
                  primary: "Biceps", secondary: ["Forearms"], equipment: ["Dumbbells"],
                  englishInstruction: "Curl the weights without swinging the torso, then lower slowly.",
                  norwegianInstruction: "Bøy albuene uten å svinge overkroppen, og senk manualene rolig."),
            .init(slug: "hammer-curl", name: "Hammer Curl", norwegianName: "Hammercurl",
                  primary: "Biceps", secondary: ["Forearms"], equipment: ["Dumbbells"],
                  englishInstruction: "Keep palms facing inward while curling and lowering the dumbbells.",
                  norwegianInstruction: "Hold håndflatene vendt innover mens du løfter og senker manualene."),
            .init(slug: "barbell-curl", name: "Barbell Curl", norwegianName: "Bicepscurl med stang",
                  primary: "Biceps", secondary: ["Forearms"], equipment: ["Barbell"],
                  englishInstruction: "Curl the bar with elbows near your sides and control the descent.",
                  norwegianInstruction: "Løft stangen med albuene nær kroppen og senk kontrollert."),
            .init(slug: "triceps-pushdown", name: "Triceps Pushdown", norwegianName: "Triceps nedpress",
                  primary: "Triceps", secondary: [], equipment: ["Cable"],
                  englishInstruction: "Keep elbows beside the torso and extend the arms downward.",
                  norwegianInstruction: "Hold albuene inntil kroppen og strekk armene nedover."),
            .init(slug: "overhead-triceps-extension", name: "Overhead Triceps Extension", norwegianName: "Triceps over hodet",
                  primary: "Triceps", secondary: [], equipment: ["Dumbbells"],
                  englishInstruction: "Lower the weight behind the head by bending the elbows, then extend.",
                  norwegianInstruction: "Senk vekten bak hodet ved å bøye albuene, og strekk armene opp."),
            .init(slug: "back-squat", name: "Barbell Back Squat", norwegianName: "Knebøy med stang",
                  primary: "Quads", secondary: ["Glutes", "Core"], equipment: ["Barbell", "Rack"],
                  englishInstruction: "Squat between your hips and knees with steady feet, then stand tall.",
                  norwegianInstruction: "Sett deg ned i knebøy med stabile føtter og reis deg kontrollert opp."),
            .init(slug: "front-squat", name: "Front Squat", norwegianName: "Frontbøy",
                  primary: "Quads", secondary: ["Glutes", "Core"], equipment: ["Barbell", "Rack"],
                  englishInstruction: "Keep the bar in front of the shoulders and chest high throughout the squat.",
                  norwegianInstruction: "Hold stangen foran skuldrene og brystet høyt gjennom knebøyen."),
            .init(slug: "goblet-squat", name: "Goblet Squat", norwegianName: "Goblet squat",
                  primary: "Quads", secondary: ["Glutes", "Core"], equipment: ["Dumbbells"],
                  englishInstruction: "Hold a weight at the chest and squat down between the knees.",
                  norwegianInstruction: "Hold en vekt foran brystet og sett deg ned mellom knærne."),
            .init(slug: "leg-press", name: "Leg Press", norwegianName: "Beinpress",
                  primary: "Quads", secondary: ["Glutes"], equipment: ["Machine"],
                  englishInstruction: "Press the platform through the feet without locking the knees.",
                  norwegianInstruction: "Press platen fra deg gjennom føttene uten å låse knærne."),
            .init(slug: "leg-extension", name: "Leg Extension", norwegianName: "Beinstrekk",
                  primary: "Quads", secondary: [], equipment: ["Machine"],
                  englishInstruction: "Extend the knees against the pad and lower the weight slowly.",
                  norwegianInstruction: "Strekk knærne mot puten og senk vekten kontrollert."),
            .init(slug: "bulgarian-split-squat", name: "Bulgarian Split Squat", norwegianName: "Bulgarsk utfall",
                  primary: "Quads", secondary: ["Glutes"], equipment: ["Bench", "Dumbbells"],
                  englishInstruction: "Keep the rear foot supported and lower the front knee with control.",
                  norwegianInstruction: "Ha bakre fot på benken og senk kroppen kontrollert over fremre bein."),
            .init(slug: "walking-lunge", name: "Walking Lunge", norwegianName: "Gående utfall",
                  primary: "Quads", secondary: ["Glutes", "Hamstrings"], equipment: ["Bodyweight", "Dumbbells"],
                  englishInstruction: "Step forward into a lunge and push through the front foot to continue.",
                  norwegianInstruction: "Ta et steg frem i utfall og press gjennom fremre fot til neste steg."),
            .init(slug: "romanian-deadlift", name: "Romanian Deadlift", norwegianName: "Rumensk markløft",
                  primary: "Hamstrings", secondary: ["Glutes", "Back"], equipment: ["Barbell"],
                  englishInstruction: "Hinge backward at the hips with soft knees and keep the bar near the legs.",
                  norwegianInstruction: "Skyv hoften bakover med lett bøy i knærne, og hold stangen nær bena."),
            .init(slug: "deadlift", name: "Conventional Deadlift", norwegianName: "Markløft",
                  primary: "Glutes", secondary: ["Hamstrings", "Back", "Core"], equipment: ["Barbell"],
                  englishInstruction: "Brace, push through the floor and lift the bar close to your body.",
                  norwegianInstruction: "Spenn kjernen, press gjennom gulvet og løft stangen tett inntil kroppen."),
            .init(slug: "lying-leg-curl", name: "Lying Leg Curl", norwegianName: "Liggende lårcurl",
                  primary: "Hamstrings", secondary: [], equipment: ["Machine"],
                  englishInstruction: "Curl the ankles toward the glutes without lifting the hips off the pad.",
                  norwegianInstruction: "Bøy knærne mot setet uten å løfte hoftene fra benken."),
            .init(slug: "seated-leg-curl", name: "Seated Leg Curl", norwegianName: "Sittende lårcurl",
                  primary: "Hamstrings", secondary: [], equipment: ["Machine"],
                  englishInstruction: "Pull the lower legs under the seat and return slowly.",
                  norwegianInstruction: "Trekk leggene bakover under setet og før dem rolig tilbake."),
            .init(slug: "hip-thrust", name: "Barbell Hip Thrust", norwegianName: "Hip thrust med stang",
                  primary: "Glutes", secondary: ["Hamstrings"], equipment: ["Barbell", "Bench"],
                  englishInstruction: "Drive the hips upward with shoulders on the bench and pause at the top.",
                  norwegianInstruction: "Press hoften opp med skuldrene mot benken, og stopp kort på toppen."),
            .init(slug: "glute-bridge", name: "Glute Bridge", norwegianName: "Seteløft",
                  primary: "Glutes", secondary: ["Hamstrings", "Core"], equipment: ["Bodyweight"],
                  englishInstruction: "Press through the heels and lift the hips without overextending the back.",
                  norwegianInstruction: "Press gjennom hælene og løft hoften uten å overstrekk ryggen."),
            .init(slug: "standing-calf-raise", name: "Standing Calf Raise", norwegianName: "Stående tåhev",
                  primary: "Calves", secondary: [], equipment: ["Machine"],
                  englishInstruction: "Rise onto the toes and lower the heels under control.",
                  norwegianInstruction: "Hev deg opp på tærne og senk hælene kontrollert."),
            .init(slug: "seated-calf-raise", name: "Seated Calf Raise", norwegianName: "Sittende tåhev",
                  primary: "Calves", secondary: [], equipment: ["Machine"],
                  englishInstruction: "Lift the heels with knees bent and lower steadily.",
                  norwegianInstruction: "Løft hælene med bøyde knær og senk rolig."),
            .init(slug: "plank", name: "Plank", norwegianName: "Planke",
                  primary: "Core", secondary: ["Shoulders"], equipment: ["Bodyweight"],
                  englishInstruction: "Brace your abdomen and hold a straight line from head to heel.",
                  norwegianInstruction: "Stram magen og hold en rett linje fra hode til hæl."),
            .init(slug: "side-plank", name: "Side Plank", norwegianName: "Sideplanke",
                  primary: "Core", secondary: ["Shoulders"], equipment: ["Bodyweight"],
                  englishInstruction: "Support yourself on one forearm and keep the hips lifted in a straight line.",
                  norwegianInstruction: "Støtt deg på én underarm og hold hoften løftet i en rett linje."),
            .init(slug: "dead-bug", name: "Dead Bug", norwegianName: "Dead bug",
                  primary: "Core", secondary: [], equipment: ["Bodyweight"],
                  englishInstruction: "Extend opposite arm and leg while keeping the lower back steady.",
                  norwegianInstruction: "Strekk motsatt arm og bein mens du holder korsryggen stabil."),
            .init(slug: "hanging-knee-raise", name: "Hanging Knee Raise", norwegianName: "Hengende kneløft",
                  primary: "Core", secondary: ["Forearms"], equipment: ["Pull-up Bar"],
                  englishInstruction: "Raise the knees while hanging and avoid swinging.",
                  norwegianInstruction: "Løft knærne mens du henger og unngå å svinge."),
            .init(slug: "cable-crunch", name: "Cable Crunch", norwegianName: "Magecrunch i kabel",
                  primary: "Core", secondary: [], equipment: ["Cable"],
                  englishInstruction: "Curl the ribcage toward the pelvis without pulling with the arms.",
                  norwegianInstruction: "Trekk ribbeina mot bekkenet uten å dra med armene."),
            .init(slug: "pallof-press", name: "Pallof Press", norwegianName: "Pallof press",
                  primary: "Core", secondary: ["Shoulders"], equipment: ["Cable"],
                  englishInstruction: "Press the handle away from the chest and resist rotation.",
                  norwegianInstruction: "Press håndtaket ut fra brystet og motstå rotasjon."),
            .init(slug: "russian-twist", name: "Russian Twist", norwegianName: "Russisk rotasjon",
                  primary: "Core", secondary: [], equipment: ["Bodyweight"],
                  englishInstruction: "Rotate the torso steadily side to side without jerking.",
                  norwegianInstruction: "Roter overkroppen rolig fra side til side uten å rykke."),
            .init(slug: "kettlebell-swing", name: "Kettlebell Swing", norwegianName: "Kettlebell-sving",
                  primary: "Glutes", secondary: ["Hamstrings", "Core"], equipment: ["Kettlebell"],
                  englishInstruction: "Drive the kettlebell with a hip hinge, not by lifting with the arms.",
                  norwegianInstruction: "Sving kettlebellen med hoftekraft fremfor å løfte med armene."),
            .init(slug: "step-up", name: "Box Step-Up", norwegianName: "Step-up på kasse",
                  primary: "Quads", secondary: ["Glutes"], equipment: ["Box", "Dumbbells"],
                  englishInstruction: "Step onto the box through the leading foot and lower carefully.",
                  norwegianInstruction: "Gå opp på kassen ved å presse gjennom fremre fot og gå rolig ned."),
            .init(slug: "burpee", name: "Burpee", norwegianName: "Burpee",
                  primary: "Quads", secondary: ["Chest", "Core"], equipment: ["Bodyweight"],
                  englishInstruction: "Move to the floor and back to standing while keeping the movement controlled.",
                  norwegianInstruction: "Gå eller hopp ned til gulvet og tilbake opp med kontroll."),
            .init(slug: "mountain-climber", name: "Mountain Climber", norwegianName: "Mountain climber",
                  primary: "Core", secondary: ["Shoulders", "Quads"], equipment: ["Bodyweight"],
                  englishInstruction: "Bring the knees forward alternately from a steady plank.",
                  norwegianInstruction: "Trekk knærne vekselvis frem fra en stabil plankeposisjon."),
            .init(slug: "single-leg-romanian-deadlift", name: "Single-Leg Romanian Deadlift", norwegianName: "Ettbeins rumensk markløft",
                  primary: "Hamstrings", secondary: ["Glutes", "Core"], equipment: ["Dumbbells"],
                  englishInstruction: "Hinge on one leg while keeping hips level and the back neutral.",
                  norwegianInstruction: "Bøy i hoften på ett bein med hoftene rette og ryggen nøytral."),
            .init(slug: "seated-dumbbell-press", name: "Seated Dumbbell Press", norwegianName: "Sittende skulderpress",
                  primary: "Shoulders", secondary: ["Triceps"], equipment: ["Dumbbells", "Bench"],
                  englishInstruction: "Sit upright and press dumbbells overhead without excessive back arch.",
                  norwegianInstruction: "Sitt oppreist og press manualene over hodet uten stor svai i ryggen.")
    ]

    private static let nativeNorwegianNames: [String: String] =
        Dictionary(uniqueKeysWithValues: nativeSeeds.map {
            ("athlth-native-" + $0.slug, $0.norwegianName)
        })

    private static let nativeNorwegianInstructions: [String: [String]] =
        Dictionary(uniqueKeysWithValues: nativeSeeds.map {
            ("athlth-native-" + $0.slug, [$0.norwegianInstruction])
        })

    private static var nativeATHLTHExercises: [ExerciseLibraryEntry] {
        nativeSeeds.map { seed in
            let id = stableUUID(for: "athlth-native:" + seed.slug)
            let exercise = Exercise(
                id: id,
                origin: .publicCatalog,
                ownerID: nil,
                name: seed.name,
                instructions: [seed.englishInstruction],
                primaryMuscles: [seed.primary],
                secondaryMuscles: seed.secondary,
                equipment: seed.equipment,
                imageURL: nil,
                isVisibleOutsideOwnerLibrary: true
            )
            return ExerciseLibraryEntry(
                id: id,
                exercise: exercise,
                source: .athlthCatalog,
                sourceIdentifier: "athlth-native-" + seed.slug,
                summary: seed.englishInstruction,
                tips: [],
                category: "strength",
                difficulty: "All levels",
                bodyPart: seed.primary,
                imageStartURL: nil,
                imagePeakURL: nil
            )
        }
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
    case invalidDataset
    case httpStatus(Int)
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidDataset:
            return "RepDB sent an incomplete exercise catalog. Your saved catalog is unchanged."
        case .httpStatus(let status):
            return "RepDB exercise library returned HTTP \(status)."
        case .storageUnavailable:
            return "ATHLTH could not store the custom exercise media."
        }
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
