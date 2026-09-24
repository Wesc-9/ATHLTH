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
        case .shoes: return "figure.run"
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
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

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
                if $0.isFeatured != $1.isFeatured {
                    return $0.isFeatured && !$1.isFeatured
                }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    func featuredItem(in category: ProfileGearCategory) -> ProfileGearItem? {
        items.first { $0.category == category && $0.isFeatured }
            ?? items(in: category).first
    }

    func refresh() async {
        guard let userID = currentUserID else {
            items = []
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

            items = rows
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(
        name: String,
        category: ProfileGearCategory,
        jpegData: Data?,
        showOnProfile: Bool
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
                showOnProfile || featuredItem(in: category) == nil

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
        showOnProfile: Bool
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
            let shouldFeature =
                showOnProfile || (item.isFeatured && categoryItems.count == 1)

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

            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setFeatured(_ item: ProfileGearItem) async {
        guard let userID = currentUserID,
              userID == item.userID
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
            let replacement = items(in: item.category).first {
                await setFeatured(replacement)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearFeatured(_ category: ProfileGearCategory) async throws {
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

    private func imagePath(userID: UUID, itemID: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(itemID.uuidString.lowercased()).jpg"
    }
}

enum ProfileGearError: LocalizedError {
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            return "Gear photos must be smaller than 5 MB."
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

                HStack(alignment: .top, spacing: 8) {
                    ForEach(ProfileGearCategory.allCases) { category in
                        gearSlot(category)
                    }
                }
                .padding(.top, 12)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gearSlot(_ category: ProfileGearCategory) -> some View {
        let item = gear.featuredItem(in: category)

        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))

                if let item,
                   let value = item.imageURL,
                   let url = URL(string: value) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(7)
                        default:
                            gearIcon(category)
                        }
                    }
                } else {
                    gearIcon(category)
                }
            }
            .frame(height: 74)

            Text(item?.name ?? category.shortTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)

            if item == nil {
                Text("Add")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func gearIcon(_ category: ProfileGearCategory) -> some View {
        Image(systemName: category.systemImage)
            .font(.system(size: 27, weight: .medium))
            .foregroundStyle(ATHLTHTheme.accentDeep)
    }
}

struct ProfileGearManagerView: View {
    @EnvironmentObject private var gear: ProfileGearStore

    @State private var editingItem: ProfileGearItem?
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
                            gearRow(item)
                        }
                        .onDelete { offsets in
                            let rows = categoryItems
                            for index in offsets {
                                guard rows.indices.contains(index) else { continue }
                                Task { await gear.delete(rows[index]) }
                            }
                        }

                        Button {
                            addingCategory = category
                        } label: {
                            Label("Add another", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Label(category.title, systemImage: category.systemImage)
                        Spacer()
                        if let featured = gear.featuredItem(in: category) {
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
                    Label(error, systemImage: "exclamationmark.triangle.fill")
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
        .sheet(item: $addingCategory) { category in
            NavigationStack {
                ProfileGearEditorView(category: category)
            }
            .environmentObject(gear)
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                ProfileGearEditorView(category: item.category, existing: item)
            }
            .environmentObject(gear)
        }
    }

    private func gearRow(_ item: ProfileGearItem) -> some View {
        HStack(spacing: 12) {
            ProfileGearThumb(item: item)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))

                Text(item.isFeatured ? "Shown on profile" : "Saved gear")
                    .font(.caption)
                    .foregroundStyle(item.isFeatured ? ATHLTHTheme.accent : .secondary)
            }

            Spacer()

            if !item.isFeatured {
                Button {
                    Task { await gear.setFeatured(item) }
                } label: {
                    Image(systemName: "star")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show \(item.name) on profile")
            } else {
                Image(systemName: "star.fill")
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            Button {
                editingItem = item
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }
}

private struct ProfileGearThumb: View {
    let item: ProfileGearItem

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.045))

            if let value = item.imageURL,
               let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(5)
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
        Image(systemName: item.category.systemImage)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(ATHLTHTheme.accentDeep)
    }
}

private struct ProfileGearEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var gear: ProfileGearStore

    let category: ProfileGearCategory
    let existing: ProfileGearItem?

    @State private var name: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showOnProfile: Bool
    @State private var saving = false
    @State private var localError: String?

    init(
        category: ProfileGearCategory,
        existing: ProfileGearItem? = nil
    ) {
        self.category = category
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _showOnProfile = State(initialValue: existing?.isFeatured ?? true)
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $name)

                Toggle("Show on profile", isOn: $showOnProfile)

                Text(
                    "Only one \(category.shortTitle.lowercased()) is shown on your profile. You can keep several items saved here and switch the featured one anytime."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Photo") {
                HStack(spacing: 14) {
                    preview

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            imageData == nil ? "Choose photo" : "Change photo",
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

            if let displayedError = localError ?? gear.errorMessage {
                Section {
                    Label(
                        displayedError,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(existing == nil ? "Add \(category.shortTitle)" : "Edit \(category.shortTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                do {
                    guard let raw = try await newValue.loadTransferable(type: Data.self),
                          let image = UIImage(data: raw),
                          let jpeg = image.jpegData(compressionQuality: 0.82)
                    else {
                        throw ProfileGearError.imageTooLarge
                    }
                    imageData = jpeg
                } catch {
                    localError = error.localizedDescription
                }
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
                    in: RoundedRectangle(cornerRadius: 16)
                )
        } else if let existing,
                  let value = existing.imageURL,
                  let url = URL(string: value) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().padding(6)
                default:
                    defaultPreview
                }
            }
            .frame(width: 82, height: 82)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 16)
            )
        } else {
            defaultPreview
        }
    }

    private var defaultPreview: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .frame(width: 82, height: 82)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 16)
            )
    }

    private func save() async {
        saving = true
        localError = nil
        defer { saving = false }

        let ok: Bool
        if let existing {
            ok = await gear.update(
                existing,
                name: name,
                jpegData: imageData,
                showOnProfile: showOnProfile
            )
        } else {
            ok = await gear.add(
                name: name,
                category: category,
                jpegData: imageData,
                showOnProfile: showOnProfile
            )
        }

        if ok {
            dismiss()
        }
    }
}
