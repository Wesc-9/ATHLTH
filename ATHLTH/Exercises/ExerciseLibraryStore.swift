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
                norwegian: "Sete"
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
    @Published private(set) var customExercises: [ExerciseLibraryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?

    private let datasetURL = URL(string: "https://exercise-dataset.com/exercises.json")!
    private let imageBaseURL = URL(string: "https://exercise-dataset.com/")!
    private let client: SupabaseClient = SupabaseEnvironment.client

    private var accountID: UUID?

    init() {
        loadCachedRepDB()
    }

    func switchAccount(_ userID: UUID?) {
        guard accountID != userID else { return }
        accountID = userID
        customExercises = []
        guard userID != nil else { return }
        loadCustomExercises()
    }

    var allExercises: [ExerciseLibraryEntry] {
        (
            customExercises +
            athlthCatalogExercises +
            repDBExercises
        )
        .reduce(into: [UUID: ExerciseLibraryEntry]()) {
            result, entry in
            result[entry.id] = entry
        }
        .values
        .sorted {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    var bodyParts: [String] {
        Array(
            Set(
                allExercises.compactMap { $0.bodyPart }
            )
        )
        .sorted()
    }

    var equipmentOptions: [String] {
        Array(
            Set(
                allExercises.flatMap { $0.exercise.equipment }
            )
        )
        .sorted()
    }

    func refresh(force: Bool = false) async {
        await refreshATHLTHCatalog()

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
            repDBExercises = mapped
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
            .lowercased()

        return allExercises.filter { entry in
            let matchesText: Bool
            if cleanQuery.isEmpty {
                matchesText = true
            } else {
                let haystack = [
                    entry.name,
                    entry.summary ?? "",
                    entry.bodyPart ?? "",
                    entry.exercise.primaryMuscles.joined(separator: " "),
                    entry.exercise.secondaryMuscles.joined(separator: " "),
                    entry.exercise.equipment.joined(separator: " ")
                ]
                .joined(separator: " ")
                .lowercased()

                matchesText = haystack.contains(cleanQuery)
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
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        persistCustomExercises()
    }

    func deleteCustomExercise(_ id: UUID) {
        if let entry = customExercises.first(where: { $0.id == id }),
           let imageURL = entry.exercise.imageURL,
           imageURL.isFileURL {
            try? FileManager.default.removeItem(at: imageURL)
        }

        customExercises.removeAll { $0.id == id }
        persistCustomExercises()
    }


    private func refreshATHLTHCatalog() async {
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

            if !rows.isEmpty {
                athlthCatalogExercises =
                    rows.map(mapATHLTHCatalog)
            }
        } catch {
            if athlthCatalogExercises.isEmpty {
                athlthCatalogExercises =
                    Self.fallbackATHLTHExercises
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
