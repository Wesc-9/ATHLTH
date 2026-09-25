import Foundation
import PhotosUI
import Supabase
import SwiftUI
import UIKit

enum ProfileGearCategory: String, CaseIterable, Identifiable, Codable {
    case watch
    case shoes
    case headphones
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watch: return "Training watch"
        case .shoes: return "Shoes"
        case .headphones: return "Headphones"
        case .other: return "Other"
        }
    }

    var shortTitle: String {
        switch self {
        case .watch: return "Watch"
        case .shoes: return "Shoes"
        case .headphones: return "Headphones"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .watch: return "applewatch"
        case .shoes: return "shoeprints.fill"
        case .headphones: return "headphones"
        case .other: return "square.grid.2x2.fill"
        }
    }
}

struct ProfileGearItem: Codable, Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    let category: ProfileGearCategory
    var name: String
    var imageURL: String?
    var isFeatured: Bool
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case category
        case name
        case imageURL = "image_url"
        case isFeatured = "is_featured"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum ProfileGearStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case retired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .retired: return "Retired"
        }
    }
}

enum ShoeUseType: String, Codable, CaseIterable, Identifiable {
    case daily
    case tempo
    case race
    case trail
    case treadmill
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .tempo: return "Tempo"
        case .race: return "Race"
        case .trail: return "Trail"
        case .treadmill: return "Treadmill"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max.fill"
        case .tempo: return "speedometer"
        case .race: return "flag.checkered"
        case .trail: return "mountain.2.fill"
        case .treadmill: return "figure.run.treadmill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

struct ProfileGearDetailRecord: Codable, Hashable {
    let gearID: UUID
    let userID: UUID
    var brand: String?
    var model: String?
    var colorName: String?
    var purchasedAt: String?
    var firstUsedAt: String?
    var sizeLabel: String?
    var shoeUseType: ShoeUseType?
    var gearTypeLabel: String?
    var status: ProfileGearStatus
    var retiredAt: Date?
    var replacementTargetKM: Double?
    var isDefaultForRunning: Bool
    var notes: String?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case gearID = "gear_id"
        case userID = "user_id"
        case brand
        case model
        case colorName = "color_name"
        case purchasedAt = "purchased_at"
        case firstUsedAt = "first_used_at"
        case sizeLabel = "size_label"
        case shoeUseType = "shoe_use_type"
        case gearTypeLabel = "gear_type_label"
        case status
        case retiredAt = "retired_at"
        case replacementTargetKM = "replacement_target_km"
        case isDefaultForRunning = "is_default_for_running"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var purchasedDate: Date? {
        GearDateCodec.date(from: purchasedAt)
    }

    var firstUsedDate: Date? {
        GearDateCodec.date(from: firstUsedAt)
    }
}

struct ProfileGearDetailDraft: Hashable {
    var brand = ""
    var model = ""
    var colorName = ""
    var purchasedAt: Date?
    var firstUsedAt: Date?
    var sizeLabel = ""
    var shoeUseType: ShoeUseType = .daily
    var gearTypeLabel = ""
    var status: ProfileGearStatus = .active
    var replacementTargetKM: Double?
    var isDefaultForRunning = false
    var notes = ""

    init(
        record: ProfileGearDetailRecord? = nil,
        category: ProfileGearCategory
    ) {
        guard let record else {
            shoeUseType = .daily
            return
        }

        brand = record.brand ?? ""
        model = record.model ?? ""
        colorName = record.colorName ?? ""
        purchasedAt = record.purchasedDate
        firstUsedAt = record.firstUsedDate
        sizeLabel = record.sizeLabel ?? ""
        shoeUseType = record.shoeUseType ?? .daily
        gearTypeLabel = record.gearTypeLabel ?? ""
        status = record.status
        replacementTargetKM = record.replacementTargetKM
        isDefaultForRunning =
            category == .shoes && record.isDefaultForRunning
        notes = record.notes ?? ""
    }
}

private struct ProfileGearDetailWrite: Encodable {
    let gearID: UUID
    let userID: UUID
    let brand: String?
    let model: String?
    let colorName: String?
    let purchasedAt: String?
    let firstUsedAt: String?
    let sizeLabel: String?
    let shoeUseType: ShoeUseType?
    let gearTypeLabel: String?
    let status: ProfileGearStatus
    let retiredAt: Date?
    let replacementTargetKM: Double?
    let isDefaultForRunning: Bool
    let notes: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case gearID = "gear_id"
        case userID = "user_id"
        case brand
        case model
        case colorName = "color_name"
        case purchasedAt = "purchased_at"
        case firstUsedAt = "first_used_at"
        case sizeLabel = "size_label"
        case shoeUseType = "shoe_use_type"
        case gearTypeLabel = "gear_type_label"
        case status
        case retiredAt = "retired_at"
        case replacementTargetKM = "replacement_target_km"
        case isDefaultForRunning = "is_default_for_running"
        case notes
        case updatedAt = "updated_at"
    }
}

struct WorkoutGearUsageRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    let workoutID: UUID
    let gearID: UUID
    let workoutTitle: String
    let activityType: String
    let source: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let distanceMeters: Double?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case workoutID = "workout_id"
        case gearID = "gear_id"
        case workoutTitle = "workout_title"
        case activityType = "activity_type"
        case source
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct WorkoutGearUsageWrite: Encodable {
    let userID: UUID
    let workoutID: UUID
    let gearID: UUID
    let workoutTitle: String
    let activityType: String
    let source: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Double
    let distanceMeters: Double?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case workoutID = "workout_id"
        case gearID = "gear_id"
        case workoutTitle = "workout_title"
        case activityType = "activity_type"
        case source
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case updatedAt = "updated_at"
    }
}

struct ProfileGearUsageStats: Hashable {
    let workoutCount: Int
    let totalDuration: TimeInterval
    let totalDistanceMeters: Double
    let firstUsedAt: Date?
    let lastUsedAt: Date?

    static let empty = ProfileGearUsageStats(
        workoutCount: 0,
        totalDuration: 0,
        totalDistanceMeters: 0,
        firstUsedAt: nil,
        lastUsedAt: nil
    )
}

private enum GearDateCodec {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        return formatter.string(from: date)
    }

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return formatter.date(from: value)
    }
}

private extension String {
    var gearNilIfEmpty: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

private struct ProfileGearInsert: Encodable {
    let id: UUID
    let userID: UUID
    let category: ProfileGearCategory
    let name: String
    let imageURL: String?
    let isFeatured: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case category
        case name
        case imageURL = "image_url"
        case isFeatured = "is_featured"
    }
}

private struct ProfileGearUpdate: Encodable {
    let name: String
    let imageURL: String?
    let isFeatured: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case imageURL = "image_url"
        case isFeatured = "is_featured"
    }
}

@MainActor
final class ProfileGearStore: ObservableObject {
    @Published private(set) var items: [ProfileGearItem] = []
    @Published private(set) var detailRecords: [UUID: ProfileGearDetailRecord] = [:]
    @Published private(set) var usageRecords: [WorkoutGearUsageRecord] = []
    @Published private(set) var preparedWorkoutGearIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var hasPreparedWorkoutGearSelection = false

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    func items(in category: ProfileGearCategory) -> [ProfileGearItem] {
        items
            .filter { $0.category == category }
            .sorted {
                if isActive($0) != isActive($1) {
                    return isActive($0) && !isActive($1)
                }
                if $0.isFeatured != $1.isFeatured {
                    return $0.isFeatured && !$1.isFeatured
                }
                return ($0.createdAt ?? .distantPast) >
                    ($1.createdAt ?? .distantPast)
            }
    }

    func featuredItem(in category: ProfileGearCategory) -> ProfileGearItem? {
        items.first {
            $0.category == category &&
            $0.isFeatured &&
            isActive($0)
        } ?? items(in: category).first(where: isActive)
    }

    func details(for item: ProfileGearItem) -> ProfileGearDetailRecord? {
        detailRecords[item.id]
    }

    func isActive(_ item: ProfileGearItem) -> Bool {
        detailRecords[item.id]?.status != .retired
    }

    var defaultRunningShoe: ProfileGearItem? {
        items(in: .shoes).first {
            isActive($0) &&
            detailRecords[$0.id]?.isDefaultForRunning == true
        }
    }

    func activeItems(
        for activity: WorkoutActivity
    ) -> [ProfileGearItem] {
        items.filter { item in
            guard isActive(item) else { return false }

            if item.category == .shoes {
                return activity == .running || activity == .walking
            }

            return true
        }
        .sorted {
            if $0.category == .shoes &&
                detailRecords[$0.id]?.isDefaultForRunning == true {
                return true
            }
            if $1.category == .shoes &&
                detailRecords[$1.id]?.isDefaultForRunning == true {
                return false
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    func usage(for item: ProfileGearItem) -> [WorkoutGearUsageRecord] {
        usageRecords
            .filter { $0.gearID == item.id }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func usageStats(for item: ProfileGearItem) -> ProfileGearUsageStats {
        let rows = usage(for: item)
        guard !rows.isEmpty else { return .empty }

        return ProfileGearUsageStats(
            workoutCount: rows.count,
            totalDuration: rows.reduce(0) { $0 + $1.durationSeconds },
            totalDistanceMeters: rows.reduce(0) {
                $0 + ($1.distanceMeters ?? 0)
            },
            firstUsedAt: rows.map(\.startedAt).min(),
            lastUsedAt: rows.map(\.startedAt).max()
        )
    }

    func gearIDs(for workoutID: UUID) -> Set<UUID> {
        Set(
            usageRecords
                .filter { $0.workoutID == workoutID }
                .map(\.gearID)
        )
    }

    func initialGearSelection(
        for activity: WorkoutActivity
    ) -> Set<UUID> {
        guard activity == .running,
              let defaultRunningShoe
        else {
            return []
        }

        return [defaultRunningShoe.id]
    }

    func prepareNextWorkoutGear(_ gearIDs: Set<UUID>) {
        preparedWorkoutGearIDs = gearIDs
        hasPreparedWorkoutGearSelection = true
    }

    func clearPreparedWorkoutGear() {
        preparedWorkoutGearIDs = []
        hasPreparedWorkoutGearSelection = false
    }

    func savePreparedGearUsage(
        for workout: SocialPublishableWorkout
    ) async {
        let selected: Set<UUID>

        if hasPreparedWorkoutGearSelection {
            selected = preparedWorkoutGearIDs
        } else if workout.activity == .running,
                  let defaultRunningShoe {
            selected = [defaultRunningShoe.id]
        } else {
            selected = []
        }

        _ = await saveGearUsage(
            for: workout,
            gearIDs: selected
        )
        clearPreparedWorkoutGear()
    }

    func refresh() async {
        guard let userID = currentUserID else {
            items = []
            detailRecords = [:]
            usageRecords = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows: [ProfileGearItem] = try await client
                .from("profile_gear")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            let details: [ProfileGearDetailRecord] = try await client
                .from("profile_gear_details")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            let usage: [WorkoutGearUsageRecord] = try await client
                .from("workout_gear_usage")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            items = rows
            detailRecords = Dictionary(
                uniqueKeysWithValues: details.map { ($0.gearID, $0) }
            )
            usageRecords = usage.sorted { $0.startedAt > $1.startedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(
        name: String,
        category: ProfileGearCategory,
        jpegData: Data?,
        showOnProfile: Bool,
        detailDraft: ProfileGearDetailDraft = .init(
            category: .other
        )
    ) async -> Bool {
        guard let userID = currentUserID else {
            errorMessage = "You need to be signed in to add gear."
            return false
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMessage = "Give this item a name."
            return false
        }

        errorMessage = nil
        let itemID = UUID()

        do {
            let imageURL = try await uploadImageIfNeeded(
                jpegData,
                userID: userID,
                itemID: itemID
            )

            let shouldFeature =
                detailDraft.status == .active &&
                (showOnProfile || featuredItem(in: category) == nil)

            if shouldFeature {
                try await clearFeatured(category)
            }

            let payload = ProfileGearInsert(
                id: itemID,
                userID: userID,
                category: category,
                name: cleanName,
                imageURL: imageURL?.absoluteString,
                isFeatured: shouldFeature
            )

            try await client
                .from("profile_gear")
                .insert(payload)
                .execute()

            do {
                try await saveDetails(
                    gearID: itemID,
                    category: category,
                    draft: detailDraft
                )
            } catch {
                try? await client
                    .from("profile_gear")
                    .delete()
                    .eq("id", value: itemID)
                    .eq("user_id", value: userID)
                    .execute()
                throw error
            }

            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func update(
        _ item: ProfileGearItem,
        name: String,
        jpegData: Data?,
        showOnProfile: Bool,
        detailDraft: ProfileGearDetailDraft? = nil
    ) async -> Bool {
        guard let userID = currentUserID,
              userID == item.userID
        else {
            errorMessage = "You can only edit your own gear."
            return false
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMessage = "Give this item a name."
            return false
        }

        errorMessage = nil

        do {
            let uploaded = try await uploadImageIfNeeded(
                jpegData,
                userID: userID,
                itemID: item.id
            )
            let resolvedImage = uploaded?.absoluteString ?? item.imageURL
            let categoryItems = items(in: item.category)
            let status = detailDraft?.status ??
                detailRecords[item.id]?.status ??
                .active
            let shouldFeature =
                status == .active &&
                (
                    showOnProfile ||
                    (item.isFeatured && categoryItems.count == 1)
                )

            if shouldFeature {
                try await clearFeatured(item.category)
            }

            let payload = ProfileGearUpdate(
                name: cleanName,
                imageURL: resolvedImage,
                isFeatured: shouldFeature
            )

            try await client
                .from("profile_gear")
                .update(payload)
                .eq("id", value: item.id)
                .eq("user_id", value: userID)
                .execute()

            if let detailDraft {
                try await saveDetails(
                    gearID: item.id,
                    category: item.category,
                    draft: detailDraft
                )
            }

            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setFeatured(_ item: ProfileGearItem) async {
        guard let userID = currentUserID,
              userID == item.userID,
              isActive(item)
        else {
            return
        }

        errorMessage = nil

        do {
            try await clearFeatured(item.category)
            try await client
                .from("profile_gear")
                .update(["is_featured": true])
                .eq("id", value: item.id)
                .eq("user_id", value: userID)
                .execute()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDefaultRunningShoe(
        _ item: ProfileGearItem
    ) async {
        guard item.category == .shoes,
              isActive(item),
              let detail = detailRecords[item.id]
        else {
            return
        }

        var draft = ProfileGearDetailDraft(
            record: detail,
            category: .shoes
        )
        draft.isDefaultForRunning = true

        do {
            try await saveDetails(
                gearID: item.id,
                category: .shoes,
                draft: draft
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveGearUsage(
        for workout: SocialPublishableWorkout,
        gearIDs: Set<UUID>
    ) async -> Bool {
        guard let userID = currentUserID else {
            errorMessage = "Sign in to save workout gear."
            return false
        }

        let ownedIDs = Set(
            items
                .filter { $0.userID == userID }
                .map(\.id)
        )
        let selected = gearIDs.intersection(ownedIDs)
        let existing = usageRecords.filter {
            $0.workoutID == workout.id
        }

        do {
            if !selected.isEmpty {
                let writes = selected.map { gearID in
                    WorkoutGearUsageWrite(
                        userID: userID,
                        workoutID: workout.id,
                        gearID: gearID,
                        workoutTitle: String(
                            workout.title.prefix(160)
                        ),
                        activityType: workout.activity.rawValue,
                        source: String(workout.source.prefix(80)),
                        startedAt: workout.startDate,
                        endedAt: workout.endDate,
                        durationSeconds: max(workout.duration, 0),
                        distanceMeters:
                            workout.distanceMeters.map { max($0, 0) },
                        updatedAt: Date()
                    )
                }

                try await client
                    .from("workout_gear_usage")
                    .upsert(
                        writes,
                        onConflict: "user_id,workout_id,gear_id"
                    )
                    .execute()
            }

            for record in existing
            where !selected.contains(record.gearID) {
                try await client
                    .from("workout_gear_usage")
                    .delete()
                    .eq("id", value: record.id)
                    .eq("user_id", value: userID)
                    .execute()
            }

            await refreshUsage()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ item: ProfileGearItem) async {
        guard let userID = currentUserID,
              userID == item.userID
        else {
            return
        }

        errorMessage = nil

        do {
            try await client
                .from("profile_gear")
                .delete()
                .eq("id", value: item.id)
                .eq("user_id", value: userID)
                .execute()

            if item.imageURL != nil {
                let path = imagePath(userID: userID, itemID: item.id)
                try? await client.storage
                    .from("profile-gear")
                    .remove(paths: [path])
            }

            await refresh()

            if !items.contains(where: {
                $0.category == item.category && $0.isFeatured
            }),
            let replacement = items(in: item.category).first(
                where: isActive
            ) {
                await setFeatured(replacement)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveDetails(
        gearID: UUID,
        category: ProfileGearCategory,
        draft: ProfileGearDetailDraft
    ) async throws {
        guard let userID = currentUserID else {
            throw ProfileGearError.notAuthenticated
        }

        let isActiveStatus = draft.status == .active
        var shouldDefault =
            category == .shoes &&
            isActiveStatus &&
            draft.isDefaultForRunning

        if category == .shoes,
           isActiveStatus,
           defaultRunningShoe == nil {
            shouldDefault = true
        }

        if shouldDefault {
            try await client
                .from("profile_gear_details")
                .update(["is_default_for_running": false])
                .eq("user_id", value: userID)
                .execute()
        }

        let payload = ProfileGearDetailWrite(
            gearID: gearID,
            userID: userID,
            brand: draft.brand.gearNilIfEmpty,
            model: draft.model.gearNilIfEmpty,
            colorName: draft.colorName.gearNilIfEmpty,
            purchasedAt: GearDateCodec.string(from: draft.purchasedAt),
            firstUsedAt: GearDateCodec.string(from: draft.firstUsedAt),
            sizeLabel:
                category == .shoes
                    ? draft.sizeLabel.gearNilIfEmpty
                    : nil,
            shoeUseType:
                category == .shoes
                    ? draft.shoeUseType
                    : nil,
            gearTypeLabel:
                category == .other
                    ? draft.gearTypeLabel.gearNilIfEmpty
                    : nil,
            status: draft.status,
            retiredAt:
                draft.status == .retired
                    ? detailRecords[gearID]?.retiredAt ?? Date()
                    : nil,
            replacementTargetKM:
                category == .shoes
                    ? draft.replacementTargetKM
                    : nil,
            isDefaultForRunning: shouldDefault,
            notes: draft.notes.gearNilIfEmpty,
            updatedAt: Date()
        )

        try await client
            .from("profile_gear_details")
            .upsert(payload)
            .execute()
    }

    private func refreshUsage() async {
        guard let userID = currentUserID else {
            usageRecords = []
            return
        }

        do {
            let rows: [WorkoutGearUsageRecord] = try await client
                .from("workout_gear_usage")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value

            usageRecords = rows.sorted { $0.startedAt > $1.startedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearFeatured(
        _ category: ProfileGearCategory
    ) async throws {
        guard let userID = currentUserID else { return }

        try await client
            .from("profile_gear")
            .update(["is_featured": false])
            .eq("user_id", value: userID)
            .eq("category", value: category.rawValue)
            .execute()
    }

    private func uploadImageIfNeeded(
        _ jpegData: Data?,
        userID: UUID,
        itemID: UUID
    ) async throws -> URL? {
        guard let jpegData else { return nil }

        guard jpegData.count <= 5_242_880 else {
            throw ProfileGearError.imageTooLarge
        }

        let path = imagePath(userID: userID, itemID: itemID)

        try await client.storage
            .from("profile-gear")
            .upload(
                path: path,
                file: jpegData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        let publicURL = try client.storage
            .from("profile-gear")
            .getPublicURL(path: path)

        var components = URLComponents(
            url: publicURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "v",
                value: String(Int(Date().timeIntervalSince1970))
            )
        ]
        return components?.url ?? publicURL
    }

    private func imagePath(
        userID: UUID,
        itemID: UUID
    ) -> String {
        "\(userID.uuidString.lowercased())/\(itemID.uuidString.lowercased()).jpg"
    }
}

enum ProfileGearError: LocalizedError {
    case imageTooLarge
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            return "Gear photos must be smaller than 5 MB."
        case .notAuthenticated:
            return "You need to be signed in to update gear."
        }
    }
}

struct ProfileGearSummaryView: View {
    @EnvironmentObject private var gear: ProfileGearStore

    var body: some View {
        NavigationLink {
            ProfileGearManagerView()
        } label: {
            ATHLTHCard {
                HStack {
                    Text("My Gear")
                        .font(.title3.weight(.bold))

                    Spacer()

                    Text("Edit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .top, spacing: 6) {
                    ForEach(ProfileGearCategory.allCases) { category in
                        gearSlot(category)
                    }
                }
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gearSlot(_ category: ProfileGearCategory) -> some View {
        let item = gear.featuredItem(in: category)

        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        item == nil
                            ? Color.primary.opacity(0.028)
                            : ATHLTHTheme.surfaceSage.opacity(0.58)
                    )

                if let item,
                   let value = item.imageURL,
                   let url = URL(string: value) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(5)
                        default:
                            gearIcon(category)
                        }
                    }
                } else {
                    gearIcon(category)
                }

                if item == nil {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .background(Color.white, in: Circle())
                        .offset(x: 19, y: -19)
                }
            }
            .frame(height: 48)

            Text(item?.name ?? category.shortTitle)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(
                    item == nil
                        ? ATHLTHTheme.mutedText
                        : ATHLTHTheme.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity)

            if category == .shoes,
               let item {
                let stats = gear.usageStats(for: item)

                Text(
                    stats.totalDistanceMeters > 0
                        ? String(
                            format: "%.0f km",
                            stats.totalDistanceMeters / 1_000
                        )
                        : "Ready"
                )
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func gearIcon(_ category: ProfileGearCategory) -> some View {
        ProfileGearCategoryIcon(
            category: category,
            size: 20
        )
    }
}

struct ProfileGearManagerView: View {
    @EnvironmentObject private var gear: ProfileGearStore

    @State private var addingCategory: ProfileGearCategory?

    var body: some View {
        List {
            ForEach(ProfileGearCategory.allCases) { category in
                Section {
                    let categoryItems = gear.items(in: category)

                    if categoryItems.isEmpty {
                        Button {
                            addingCategory = category
                        } label: {
                            Label(
                                "Add \(category.shortTitle.lowercased())",
                                systemImage: "plus.circle.fill"
                            )
                        }
                    } else {
                        ForEach(categoryItems) { item in
                            NavigationLink {
                                ProfileGearDetailView(item: item)
                            } label: {
                                gearRow(item)
                            }
                        }
                        .onDelete { offsets in
                            let rows = categoryItems
                            for index in offsets {
                                guard rows.indices.contains(index)
                                else { continue }

                                Task {
                                    await gear.delete(rows[index])
                                }
                            }
                        }

                        Button {
                            addingCategory = category
                        } label: {
                            Label("Add another", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        ProfileGearCategoryIcon(
                            category: category,
                            size: 15,
                            color: .secondary
                        )

                        Text(category.title)

                        Spacer()

                        if let featured =
                            gear.featuredItem(in: category) {
                            Text("Profile: \(featured.name)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if let error = gear.errorMessage {
                Section {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("My Gear")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await gear.refresh()
        }
        .refreshable {
            await gear.refresh()
        }
        .sheet(item: $addingCategory) { category in
            NavigationStack {
                ProfileGearEditorView(category: category)
            }
            .environmentObject(gear)
        }
    }

    private func gearRow(
        _ item: ProfileGearItem
    ) -> some View {
        let details = gear.details(for: item)
        let stats = gear.usageStats(for: item)

        return HStack(spacing: 12) {
            ProfileGearThumb(item: item)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))

                    if details?.status == .retired {
                        Text("RETIRED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else if details?.isDefaultForRunning == true {
                        Text("DEFAULT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                    }
                }

                Text(
                    rowSubtitle(
                        item,
                        details: details,
                        stats: stats
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if item.isFeatured {
                Image(systemName: "star.fill")
                    .foregroundStyle(ATHLTHTheme.accent)
            }
        }
        .padding(.vertical, 3)
    }

    private func rowSubtitle(
        _ item: ProfileGearItem,
        details: ProfileGearDetailRecord?,
        stats: ProfileGearUsageStats
    ) -> String {
        var parts: [String] = []

        if let brand = details?.brand {
            parts.append(brand)
        }

        if item.category == .shoes {
            if let use = details?.shoeUseType {
                parts.append(use.title)
            }

            if stats.totalDistanceMeters > 0 {
                parts.append(
                    String(
                        format: "%.0f km",
                        stats.totalDistanceMeters / 1_000
                    )
                )
            }
        } else if stats.workoutCount > 0 {
            parts.append(
                "\(stats.workoutCount) workout\(stats.workoutCount == 1 ? "" : "s")"
            )
        }

        if parts.isEmpty {
            parts.append(
                item.isFeatured
                    ? "Shown on profile"
                    : "Saved gear"
            )
        }

        return parts.joined(separator: " · ")
    }
}

struct ProfileGearThumb: View {
    let item: ProfileGearItem

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 11,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.045))

            if let value = item.imageURL,
               let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 52, height: 52)
    }

    private var fallback: some View {
        ProfileGearCategoryIcon(
            category: item.category,
            size: 21
        )
    }
}

struct ProfileGearEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gear: ProfileGearStore

    let category: ProfileGearCategory
    let existing: ProfileGearItem?

    @State private var name: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showOnProfile: Bool
    @State private var detailDraft: ProfileGearDetailDraft
    @State private var hasPurchasedDate = false
    @State private var hasFirstUsedDate = false
    @State private var replacementTargetText = ""
    @State private var saving = false
    @State private var localError: String?
    @State private var didLoadDetails = false

    init(
        category: ProfileGearCategory,
        existing: ProfileGearItem? = nil
    ) {
        self.category = category
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _showOnProfile = State(
            initialValue: existing?.isFeatured ?? true
        )
        _detailDraft = State(
            initialValue: ProfileGearDetailDraft(
                category: category
            )
        )
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField(
                    category == .shoes
                        ? "Display name, e.g. Pegasus 42"
                        : "Name",
                    text: $name
                )

                Picker(
                    "Status",
                    selection: $detailDraft.status
                ) {
                    ForEach(ProfileGearStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }

                Toggle(
                    "Show on profile",
                    isOn: $showOnProfile
                )
                .disabled(detailDraft.status == .retired)

                Text(
                    "Only one \(category.shortTitle.lowercased()) is featured on your profile. Retired gear stays in history but is removed from new workout choices."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if category == .shoes {
                shoeDetailsSection
            } else {
                generalDetailsSection
            }

            if let existing {
                usageSection(existing)
            }

            Section("Notes") {
                TextField(
                    "Optional notes",
                    text: $detailDraft.notes,
                    axis: .vertical
                )
                .lineLimit(2...5)
            }

            Section("Photo") {
                HStack(spacing: 14) {
                    preview

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            imageData == nil
                                ? "Choose photo"
                                : "Change photo",
                            systemImage: "photo"
                        )
                    }
                }

                Text(
                    "No photo is required. ATHLTH uses the built-in \(category.shortTitle.lowercased()) icon when you do not upload one."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let displayedError =
                localError ?? gear.errorMessage {
                Section {
                    Label(
                        displayedError,
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(
            existing == nil
                ? "Add \(category.shortTitle)"
                : "Edit \(category.shortTitle)"
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(
                    name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    saving
                )
            }
        }
        .onChange(of: detailDraft.status) { _, status in
            if status == .retired {
                detailDraft.isDefaultForRunning = false
                showOnProfile = false
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }

            Task {
                do {
                    guard
                        let raw = try await newValue
                            .loadTransferable(type: Data.self),
                        let image = UIImage(data: raw),
                        let jpeg = image.jpegData(
                            compressionQuality: 0.82
                        )
                    else {
                        throw ProfileGearError.imageTooLarge
                    }

                    imageData = jpeg
                } catch {
                    localError = error.localizedDescription
                }
            }
        }
        .task {
            guard !didLoadDetails else { return }
            didLoadDetails = true

            if gear.items.isEmpty {
                await gear.refresh()
            }

            if let existing,
               let record = gear.details(for: existing) {
                detailDraft = ProfileGearDetailDraft(
                    record: record,
                    category: category
                )
                hasPurchasedDate =
                    detailDraft.purchasedAt != nil
                hasFirstUsedDate =
                    detailDraft.firstUsedAt != nil

                if let target =
                    detailDraft.replacementTargetKM {
                    replacementTargetText =
                        String(format: "%.0f", target)
                }
            } else if category == .shoes,
                      gear.defaultRunningShoe == nil {
                detailDraft.isDefaultForRunning = true
            }
        }
    }

    private var shoeDetailsSection: some View {
        Section("Shoe Details") {
            TextField("Brand", text: $detailDraft.brand)
            TextField("Model", text: $detailDraft.model)
            TextField("Color", text: $detailDraft.colorName)
            TextField("Size", text: $detailDraft.sizeLabel)

            Picker(
                "Rotation",
                selection: $detailDraft.shoeUseType
            ) {
                ForEach(ShoeUseType.allCases) { type in
                    Label(type.title, systemImage: type.icon)
                        .tag(type)
                }
            }

            Toggle(
                "Purchased date",
                isOn: $hasPurchasedDate
            )

            if hasPurchasedDate {
                DatePicker(
                    "Purchased",
                    selection: Binding(
                        get: {
                            detailDraft.purchasedAt ?? Date()
                        },
                        set: {
                            detailDraft.purchasedAt = $0
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
            }

            Toggle(
                "First used date",
                isOn: $hasFirstUsedDate
            )

            if hasFirstUsedDate {
                DatePicker(
                    "First used",
                    selection: Binding(
                        get: {
                            detailDraft.firstUsedAt ?? Date()
                        },
                        set: {
                            detailDraft.firstUsedAt = $0
                        }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
            }

            TextField(
                "Replacement target (km)",
                text: $replacementTargetText
            )
            .keyboardType(.decimalPad)

            Toggle(
                "Default running shoe",
                isOn: $detailDraft.isDefaultForRunning
            )
            .disabled(detailDraft.status == .retired)

            Text(
                "ATHLTH uses the actual completed workout distance. A 10 km planned run that finishes at 8.4 km adds 8.4 km to the selected shoes."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var generalDetailsSection: some View {
        Section("Details") {
            if category == .other {
                TextField(
                    "Type, e.g. chest strap or vest",
                    text: $detailDraft.gearTypeLabel
                )
            }

            TextField("Brand", text: $detailDraft.brand)
            TextField("Model", text: $detailDraft.model)
            TextField("Color", text: $detailDraft.colorName)

            Text(
                "Other gear tracks workout count, total time and last use. Distance is only emphasized for shoes."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func usageSection(
        _ item: ProfileGearItem
    ) -> some View {
        let stats = gear.usageStats(for: item)

        return Section("Usage") {
            LabeledContent(
                "Workouts",
                value: "\(stats.workoutCount)"
            )

            LabeledContent(
                "Time",
                value: compactDuration(
                    stats.totalDuration
                )
            )

            if category == .shoes {
                LabeledContent(
                    "Distance",
                    value: String(
                        format: "%.0f km",
                        stats.totalDistanceMeters / 1_000
                    )
                )
            }

            if let lastUsed = stats.lastUsedAt {
                LabeledContent(
                    "Last used",
                    value: lastUsed.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let imageData,
           let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 82)
                .padding(6)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(
                        cornerRadius: 16
                    )
                )
        } else if let existing,
                  let value = existing.imageURL,
                  let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                default:
                    defaultPreview
                }
            }
            .frame(width: 82, height: 82)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(
                    cornerRadius: 16
                )
            )
        } else {
            defaultPreview
        }
    }

    private var defaultPreview: some View {
        ProfileGearCategoryIcon(
            category: category,
            size: 34
        )
        .frame(width: 82, height: 82)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(
                cornerRadius: 16
            )
        )
    }

    private func save() async {
        saving = true
        localError = nil
        defer { saving = false }

        if hasPurchasedDate {
            detailDraft.purchasedAt =
                detailDraft.purchasedAt ?? Date()
        } else {
            detailDraft.purchasedAt = nil
        }

        if hasFirstUsedDate {
            detailDraft.firstUsedAt =
                detailDraft.firstUsedAt ?? Date()
        } else {
            detailDraft.firstUsedAt = nil
        }

        if let purchased = detailDraft.purchasedAt,
           let firstUsed = detailDraft.firstUsedAt,
           firstUsed < Calendar.current.startOfDay(
                for: purchased
           ) {
            localError =
                "First used date cannot be before the purchase date."
            return
        }

        if category == .shoes {
            let cleanTarget = replacementTargetText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            if cleanTarget.isEmpty {
                detailDraft.replacementTargetKM = nil
            } else if let target = Double(cleanTarget),
                      target > 0,
                      target <= 5_000 {
                detailDraft.replacementTargetKM = target
            } else {
                localError =
                    "Replacement target must be between 1 and 5000 km."
                return
            }
        } else {
            detailDraft.replacementTargetKM = nil
            detailDraft.isDefaultForRunning = false
        }

        let ok: Bool

        if let existing {
            ok = await gear.update(
                existing,
                name: name,
                jpegData: imageData,
                showOnProfile: showOnProfile,
                detailDraft: detailDraft
            )
        } else {
            ok = await gear.add(
                name: name,
                category: category,
                jpegData: imageData,
                showOnProfile: showOnProfile,
                detailDraft: detailDraft
            )
        }

        if ok {
            dismiss()
        }
    }

    private func compactDuration(
        _ seconds: TimeInterval
    ) -> String {
        let minutes = max(
            Int((seconds / 60).rounded()),
            0
        )

        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0
                ? "\(hours)h"
                : "\(hours)h \(remainder)m"
        }

        return "\(minutes)m"
    }
}
