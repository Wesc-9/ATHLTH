import CryptoKit
import Foundation

@MainActor
final class ExerciseLibraryStore: ObservableObject {
    @Published private(set) var repDBExercises: [ExerciseLibraryEntry] = []
    @Published private(set) var customExercises: [ExerciseLibraryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?

    private let datasetURL = URL(string: "https://exercise-dataset.com/exercises.json")!
    private let imageBaseURL = URL(string: "https://exercise-dataset.com/")!

    init() {
        loadCustomExercises()
        loadCachedRepDB()
    }

    var allExercises: [ExerciseLibraryEntry] {
        (customExercises + repDBExercises).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var bodyParts: [String] {
        Array(
            Set(
                repDBExercises.compactMap { $0.bodyPart }
            )
        )
        .sorted()
    }

    var equipmentOptions: [String] {
        Array(
            Set(
                repDBExercises.flatMap { $0.exercise.equipment }
            )
        )
        .sorted()
    }

    func refresh(force: Bool = false) async {
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

            let matchesEquipment =
                equipment == nil ||
                equipment == "All" ||
                entry.exercise.equipment.contains(equipment!)

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
        guard exercise.origin == .custom else { return }

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

    private func mapRepDB(_ source: RepDBExercise) -> ExerciseLibraryEntry {
        let startURL = source.images?.flat?.start
            .flatMap { URL(string: $0, relativeTo: imageBaseURL)?.absoluteURL }
        let peakURL = source.images?.flat?.peak
            .flatMap { URL(string: $0, relativeTo: imageBaseURL)?.absoluteURL }
        let mainURL = source.images?.flat?.main
            .flatMap { URL(string: $0, relativeTo: imageBaseURL)?.absoluteURL }

        let imageURL = startURL ?? mainURL ?? peakURL
        let equipment = source.equipment.map { [$0.humanizedRepDB] } ?? []

        let exercise = Exercise(
            id: Self.stableUUID(for: "repdb:\(source.id)"),
            origin: .publicCatalog,
            ownerID: nil,
            name: source.nameEnglish,
            instructions: source.instructionsEnglish ?? [],
            primaryMuscles: (source.primaryMuscles ?? []).map(\.humanizedRepDB),
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
        guard let url = Self.customExercisesURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(
                  [Exercise].self,
                  from: data
              )
        else {
            return
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
        guard let url = Self.customExercisesURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let exercises = customExercises.map(\.exercise)
            let data = try JSONEncoder().encode(exercises)
            try data.write(to: url, options: .atomic)
        } catch {
            return
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
