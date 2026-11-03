import Foundation
import Supabase
import SwiftUI

struct ATHLTHPet: Identifiable, Codable, Hashable {
    let id: UUID
    let userID: UUID
    var name: String
    var species: String
    var breed: String?
    var birthDate: String?
    var weightKG: Double?
    var photoPath: String?
    var showOnProfile: Bool
    var isPublic: Bool
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, species, breed
        case userID = "user_id"
        case birthDate = "birth_date"
        case weightKG = "weight_kg"
        case photoPath = "photo_path"
        case showOnProfile = "show_on_profile"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var speciesName: String {
        switch species {
        case "dog": return ATHLTHLocalization.choose(english: "Dog", norwegian: "Hund")
        case "cat": return ATHLTHLocalization.choose(english: "Cat", norwegian: "Katt")
        case "horse": return ATHLTHLocalization.choose(english: "Horse", norwegian: "Hest")
        default: return ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")
        }
    }
}

struct ATHLTHPetDraft {
    var name = ""
    var species = "dog"
    var breed = ""
    var birthDate: Date?
    var weightKG: Double?
    var showOnProfile = true
    var isPublic = false

    init(pet: ATHLTHPet? = nil) {
        guard let pet else { return }
        name = pet.name
        species = pet.species
        breed = pet.breed ?? ""
        birthDate = pet.birthDate.flatMap(ATHLTHPetDate.date(from:))
        weightKG = pet.weightKG
        showOnProfile = pet.showOnProfile
        isPublic = pet.isPublic
    }
}

enum ATHLTHPetDate {
    private static let formatter: DateFormatter = {
        let value = DateFormatter()
        value.calendar = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()
    static func string(from date: Date?) -> String? {
        date.map { formatter.string(from: $0) }
    }
    static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }
}

private struct ATHLTHPetWrite: Encodable {
    let id: UUID
    let userID: UUID
    let name: String
    let species: String
    let breed: String?
    let birthDate: String?
    let weightKG: Double?
    let photoPath: String?
    let showOnProfile: Bool
    let isPublic: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, species, breed
        case userID = "user_id"
        case birthDate = "birth_date"
        case weightKG = "weight_kg"
        case photoPath = "photo_path"
        case showOnProfile = "show_on_profile"
        case isPublic = "is_public"
        case updatedAt = "updated_at"
    }
}

struct ATHLTHPetWorkoutUsage: Identifiable, Codable, Hashable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID
    let petID: UUID
    let workoutTitle: String
    let activityType: String
    let source: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let distanceMeters: Double?
    let participationStartedAt: Date?
    let participationEndedAt: Date?
    let distanceIsEstimated: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case workoutID = "workout_id"
        case petID = "pet_id"
        case workoutTitle = "workout_title"
        case activityType = "activity_type"
        case source, startedAt = "started_at", endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case participationStartedAt = "participation_started_at"
        case participationEndedAt = "participation_ended_at"
        case distanceIsEstimated = "distance_is_estimated"
    }
}

private struct ATHLTHPetUsageWrite: Encodable {
    let userID: UUID
    let workoutID: UUID
    let petID: UUID
    let workoutTitle: String
    let activityType: String
    let source: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let distanceMeters: Double?
    let participationStartedAt: Date?
    let participationEndedAt: Date?
    let distanceIsEstimated: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case workoutID = "workout_id"
        case petID = "pet_id"
        case workoutTitle = "workout_title"
        case activityType = "activity_type"
        case source, startedAt = "started_at", endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case participationStartedAt = "participation_started_at"
        case participationEndedAt = "participation_ended_at"
        case distanceIsEstimated = "distance_is_estimated"
        case updatedAt = "updated_at"
    }
}

struct ATHLTHPetActivityStats {
    let outings: Int
    let seconds: TimeInterval
    let meters: Double
    let longestMeters: Double
    let lastOuting: Date?
}

private struct ATHLTHPetSegment: Codable {
    let petID: UUID
    let enteredAt: Date?
    var exitedAt: Date?
    let enteredMeters: Double?
    var exitedMeters: Double?
}

private struct ATHLTHPreparedPetWorkout: Codable {
    let userID: UUID
    let preparedAt: Date
    var segments: [ATHLTHPetSegment]
}

@MainActor
final class ATHLTHPetStore: ObservableObject {
    static let shared = ATHLTHPetStore()

    @Published private(set) var pets: [ATHLTHPet] = []
    @Published private(set) var usage: [ATHLTHPetWorkoutUsage] = []
    @Published private(set) var photoURLs: [UUID: URL] = [:]
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private let client: SupabaseClient
    private var prepared: ATHLTHPreparedPetWorkout?
    private let preparedKey = "athlth.pets.prepared-workout.v1"

    var currentUserID: UUID? { client.auth.currentUser?.id }
    var visiblePets: [ATHLTHPet] { pets.filter(\.showOnProfile) }
    var activePetIDs: Set<UUID> {
        Set(prepared?.segments.filter { $0.exitedAt == nil }.map(\.petID) ?? [])
    }

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
        restorePrepared()
    }

    func refresh() async {
        guard let userID = currentUserID else {
            pets = []
            usage = []
            photoURLs = [:]
            prepared = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let rows: [ATHLTHPet] = try await client.from("profile_pets")
                .select().eq("user_id", value: userID).execute().value
            let records: [ATHLTHPetWorkoutUsage] = try await client
                .from("workout_pet_usage")
                .select().eq("user_id", value: userID).execute().value
            guard currentUserID == userID else { return }
            pets = rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            usage = records.sorted { $0.startedAt > $1.startedAt }
            var urls: [UUID: URL] = [:]
            for pet in rows {
                guard let path = pet.photoPath else { continue }
                if let url = try? await client.storage.from("pet-photos")
                    .createSignedURL(path: path, expiresIn: 3600) {
                    urls[pet.id] = url
                }
            }
            if currentUserID == userID { photoURLs = urls }
        } catch {
            if currentUserID == userID { errorMessage = error.localizedDescription }
        }
    }

    func save(
        draft: ATHLTHPetDraft,
        editing: ATHLTHPet? = nil,
        jpegData: Data? = nil,
        removePhoto: Bool = false
    ) async -> Bool {
        guard let userID = currentUserID else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Sign in to manage pets.", norwegian: "Logg inn for å administrere kjæledyr.")
            return false
        }
        let cleanName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 80,
              draft.weightKG.map({ $0 > 0 && $0 <= 1000 }) ?? true else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Check the name and weight.", norwegian: "Kontroller navn og vekt.")
            return false
        }
        guard jpegData.map({ $0.count <= 5_242_880 }) ?? true else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Photo must be under 5 MB.", norwegian: "Bildet må være under 5 MB.")
            return false
        }
        let petID = editing?.id ?? UUID()
        let oldPath = editing?.photoPath
        var photoPath = removePhoto ? nil : oldPath
        var uploaded: String?
        errorMessage = nil
        do {
            if let jpegData {
                let path = "\(userID.uuidString.lowercased())/\(petID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                try await client.storage.from("pet-photos").upload(
                    path: path, file: jpegData,
                    options: FileOptions(contentType: "image/jpeg", upsert: false))
                photoPath = path
                uploaded = path
            }
            let payload = ATHLTHPetWrite(
                id: petID, userID: userID, name: cleanName, species: draft.species,
                breed: draft.breed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : String(draft.breed.prefix(100)),
                birthDate: ATHLTHPetDate.string(from: draft.birthDate),
                weightKG: draft.weightKG, photoPath: photoPath,
                showOnProfile: draft.showOnProfile, isPublic: draft.isPublic,
                updatedAt: Date())
            try await client.from("profile_pets")
                .upsert(payload, onConflict: "id").execute()
            if let oldPath, oldPath != photoPath {
                try? await client.storage.from("pet-photos").remove(paths: [oldPath])
            }
            await refresh()
            return true
        } catch {
            if let uploaded {
                try? await client.storage.from("pet-photos").remove(paths: [uploaded])
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ pet: ATHLTHPet) async -> Bool {
        guard let userID = currentUserID, userID == pet.userID else { return false }
        do {
            try await client.from("profile_pets").delete()
                .eq("id", value: pet.id).eq("user_id", value: userID).execute()
            if let path = pet.photoPath {
                try? await client.storage.from("pet-photos").remove(paths: [path])
            }
            prepared?.segments.removeAll { $0.petID == pet.id }
            persistPrepared()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func usage(for pet: ATHLTHPet) -> [ATHLTHPetWorkoutUsage] {
        usage.filter { $0.petID == pet.id }.sorted { $0.startedAt > $1.startedAt }
    }

    func stats(for pet: ATHLTHPet) -> ATHLTHPetActivityStats {
        let rows = usage(for: pet)
        return ATHLTHPetActivityStats(
            outings: rows.count,
            seconds: rows.reduce(0) { $0 + $1.durationSeconds },
            meters: rows.reduce(0) { $0 + ($1.distanceMeters ?? 0) },
            longestMeters: rows.compactMap(\.distanceMeters).max() ?? 0,
            lastOuting: rows.first?.startedAt)
    }

    func petIDs(for workoutID: UUID) -> Set<UUID> {
        Set(usage.filter { $0.workoutID == workoutID }.map(\.petID))
    }

    func prepareNextWorkoutPets(_ ids: Set<UUID>) {
        guard let userID = currentUserID else { return }
        let owned = Set(pets.filter { $0.userID == userID }.map(\.id))
        let selected = ids.intersection(owned)
        prepared = ATHLTHPreparedPetWorkout(
            userID: userID, preparedAt: Date(),
            segments: selected.map { ATHLTHPetSegment(
                petID: $0, enteredAt: nil, exitedAt: nil,
                enteredMeters: nil, exitedMeters: nil) })
        persistPrepared()
    }

    func updateActiveWorkoutPets(_ ids: Set<UUID>, distanceMeters: Double? = nil) {
        guard let userID = currentUserID else { return }
        let selected = ids.intersection(Set(pets.map(\.id)))
        guard var entry = prepared, entry.userID == userID,
              abs(entry.preparedAt.timeIntervalSinceNow) < 36 * 3600 else {
            prepareNextWorkoutPets(selected)
            return
        }
        let current = Set(entry.segments.filter { $0.exitedAt == nil }.map(\.petID))
        for index in entry.segments.indices where
            entry.segments[index].exitedAt == nil &&
            !selected.contains(entry.segments[index].petID) {
            entry.segments[index].exitedAt = Date()
            entry.segments[index].exitedMeters = distanceMeters
        }
        for id in selected.subtracting(current) {
            entry.segments.append(ATHLTHPetSegment(
                petID: id, enteredAt: Date(), exitedAt: nil,
                enteredMeters: distanceMeters, exitedMeters: nil))
        }
        prepared = entry
        persistPrepared()
    }

    func savePreparedPetUsage(for workout: SocialPublishableWorkout) async {
        guard let userID = currentUserID,
              let prepared, prepared.userID == userID,
              abs(prepared.preparedAt.timeIntervalSinceNow) < 36 * 3600 else { return }
        let ids = Set(prepared.segments.map(\.petID))
        let success = await persistUsage(for: workout, selected: ids, segments: prepared.segments)
        if success {
            self.prepared = nil
            UserDefaults.standard.removeObject(forKey: preparedKey)
        }
    }

    @discardableResult
    func savePetUsage(for workout: SocialPublishableWorkout, petIDs: Set<UUID>) async -> Bool {
        // Editing a review must not overwrite partial participation already saved.
        return await persistUsage(for: workout, selected: petIDs, segments: nil)
    }

    private func persistUsage(
        for workout: SocialPublishableWorkout,
        selected requested: Set<UUID>,
        segments: [ATHLTHPetSegment]?
    ) async -> Bool {
        guard let userID = currentUserID else { return false }
        let selected = requested.intersection(Set(pets.filter { $0.userID == userID }.map(\.id)))
        let existing = usage.filter { $0.workoutID == workout.id }
        do {
            let writes: [ATHLTHPetUsageWrite] = selected.compactMap { petID in
                let prior = existing.first { $0.petID == petID }
                if segments == nil && prior != nil { return nil }
                let group = segments?.filter { $0.petID == petID } ?? []
                let totalDuration = max(workout.duration, 0)
                let wallDuration = max(workout.endDate.timeIntervalSince(workout.startDate), 1)
                let totalDistance = workout.distanceMeters.map { max($0, 0) }
                var activeWallSeconds = 0.0
                var distance = 0.0
                var estimated = false
                for segment in group {
                    let from = min(max(segment.enteredAt ?? workout.startDate, workout.startDate), workout.endDate)
                    let to = min(max(segment.exitedAt ?? workout.endDate, from), workout.endDate)
                    let span = max(to.timeIntervalSince(from), 0)
                    activeWallSeconds += span
                    if let final = totalDistance {
                        let first = segment.enteredMeters ?? (segment.enteredAt == nil ? 0 : nil)
                        let last = segment.exitedMeters ?? (segment.exitedAt == nil ? final : nil)
                        if let first, let last, last >= first {
                            distance += last - first
                        } else {
                            distance += final * span / wallDuration
                            estimated = true
                        }
                    }
                }
                let fraction = group.isEmpty ? 1 : min(activeWallSeconds / wallDuration, 1)
                let duration = totalDuration * fraction
                let meters = totalDistance.map { group.isEmpty ? $0 : min(distance, $0) }
                let starts = group.compactMap(\.enteredAt).min() ?? workout.startDate
                let ends = group.compactMap(\.exitedAt).max() ?? workout.endDate
                return ATHLTHPetUsageWrite(
                    userID: userID, workoutID: workout.id, petID: petID,
                    workoutTitle: String(workout.title.prefix(160)),
                    activityType: workout.activity.rawValue,
                    source: String(workout.source.prefix(80)),
                    startedAt: workout.startDate, endedAt: workout.endDate,
                    durationSeconds: duration, distanceMeters: meters,
                    participationStartedAt: starts,
                    participationEndedAt: ends,
                    distanceIsEstimated: estimated, updatedAt: Date())
            }
            if !writes.isEmpty {
                try await client.from("workout_pet_usage").upsert(
                    writes, onConflict: "user_id,workout_id,pet_id").execute()
            }
            for row in existing where !selected.contains(row.petID) {
                try await client.from("workout_pet_usage").delete()
                    .eq("id", value: row.id).eq("user_id", value: userID).execute()
            }
            let rows: [ATHLTHPetWorkoutUsage] = try await client.from("workout_pet_usage")
                .select().eq("user_id", value: userID).execute().value
            if currentUserID == userID { usage = rows.sorted { $0.startedAt > $1.startedAt } }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func restorePrepared() {
        guard let data = UserDefaults.standard.data(forKey: preparedKey),
              let restored = try? JSONDecoder().decode(ATHLTHPreparedPetWorkout.self, from: data),
              restored.userID == currentUserID,
              abs(restored.preparedAt.timeIntervalSinceNow) < 36 * 3600 else {
            UserDefaults.standard.removeObject(forKey: preparedKey)
            return
        }
        prepared = restored
    }

    private func persistPrepared() {
        guard let prepared,
              let data = try? JSONEncoder().encode(prepared) else {
            UserDefaults.standard.removeObject(forKey: preparedKey)
            return
        }
        UserDefaults.standard.set(data, forKey: preparedKey)
    }
}
