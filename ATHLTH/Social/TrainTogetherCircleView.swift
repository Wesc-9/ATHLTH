import Foundation
import PhotosUI
import Supabase
import SwiftUI
import UIKit

struct TrainTogetherCircleMessage: Codable, Identifiable {
    let id: UUID
    let postID: UUID
    let senderID: UUID
    let senderDisplayName: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case senderID = "sender_id"
        case senderDisplayName = "sender_display_name"
        case body
        case createdAt = "created_at"
    }
}

struct TrainTogetherCircleRecap: Codable {
    let postID: UUID
    let authorID: UUID
    let note: String
    let actualMinutes: Int?
    let actualKilometers: Double?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case authorID = "author_id"
        case note
        case actualMinutes = "actual_minutes"
        case actualKilometers = "actual_kilometers"
    }
}

struct TrainTogetherCirclePhoto: Codable, Identifiable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let storagePath: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
}

private struct CircleMessageInsert: Encodable {
    let postID: UUID
    let senderID: UUID
    let senderDisplayName: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case senderID = "sender_id"
        case senderDisplayName = "sender_display_name"
        case body
    }
}

private struct CircleRecapWrite: Encodable {
    let postID: UUID
    let authorID: UUID
    let note: String
    let actualMinutes: Int?
    let actualKilometers: Double?

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case authorID = "author_id"
        case note
        case actualMinutes = "actual_minutes"
        case actualKilometers = "actual_kilometers"
    }
}

private struct CirclePhotoInsert: Encodable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case storagePath = "storage_path"
    }
}

/// Access is verified by Supabase RLS, not by the UI permission check.
@MainActor
final class TrainTogetherCircleStore: ObservableObject {
    @Published private(set) var messages: [TrainTogetherCircleMessage] = []
    @Published private(set) var recap: TrainTogetherCircleRecap?
    @Published private(set) var photos: [TrainTogetherCirclePhoto] = []
    @Published private(set) var photoURLs: [UUID: URL] = [:]
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private let client = SupabaseEnvironment.client
    private let bucket = "train-together-recaps"

    func refresh(postID: UUID) async {
        do {
            async let chat: [TrainTogetherCircleMessage] = client
                .from("train_together_post_messages")
                .select()
                .eq("post_id", value: postID)
                .order("created_at", ascending: true)
                .limit(100)
                .execute().value

            async let recaps: [TrainTogetherCircleRecap] = client
                .from("train_together_recaps")
                .select()
                .eq("post_id", value: postID)
                .limit(1)
                .execute().value

            async let gallery: [TrainTogetherCirclePhoto] = client
                .from("train_together_recap_photos")
                .select()
                .eq("post_id", value: postID)
                .order("created_at", ascending: true)
                .limit(24)
                .execute().value

            let (m, r, p) = try await (chat, recaps, gallery)
            messages = m
            recap = r.first
            photos = p

            let existingIDs = Set(p.map(\.id))
            photoURLs = photoURLs.filter { existingIDs.contains($0.key) }

            for photo in p where photoURLs[photo.id] == nil {
                do {
                    photoURLs[photo.id] = try await client.storage
                        .from(bucket)
                        .createSignedURL(path: photo.storagePath, expiresIn: 1800)
                } catch {
                    // Gallery stays usable if an individual signed URL expires.
                    continue
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(
        postID: UUID,
        userID: UUID,
        name: String,
        text: String
    ) async -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSending else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try await client.from("train_together_post_messages")
                .insert(
                    CircleMessageInsert(
                        postID: postID,
                        senderID: userID,
                        senderDisplayName: String(name.prefix(100)),
                        body: String(clean.prefix(800))
                    )
                )
                .execute()
            await refresh(postID: postID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveRecap(
        postID: UUID,
        authorID: UUID,
        note: String,
        minutes: Int?,
        kilometers: Double?
    ) async -> Bool {
        guard !isSending else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try await client.from("train_together_recaps")
                .upsert(
                    CircleRecapWrite(
                        postID: postID,
                        authorID: authorID,
                        note: String(note.prefix(1200)),
                        actualMinutes: minutes,
                        actualKilometers: kilometers
                    ),
                    onConflict: "post_id"
                )
                .execute()
            await refresh(postID: postID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func uploadPhoto(
        postID: UUID,
        authorID: UUID,
        data: Data
    ) async -> Bool {
        guard !isSending else { return false }
        isSending = true
        defer { isSending = false }

        // Explicit photo selection only. Downsize before uploading private
        // social media; never include health, GPS or EXIF metadata.
        guard let photo = UIImage(data: data) else {
            errorMessage = "Could not open image."
            return false
        }
        let longest = max(photo.size.width, photo.size.height)
        let scale = min(1, 1500 / max(longest, 1))
        let dimensions = CGSize(
            width: max(1, photo.size.width * scale),
            height: max(1, photo.size.height * scale)
        )
        let resized = UIGraphicsImageRenderer(size: dimensions)
            .image { _ in
                photo.draw(in: CGRect(origin: .zero, size: dimensions))
            }
        guard let jpeg = resized.jpegData(compressionQuality: 0.77),
              jpeg.count <= 3_145_728 else {
            errorMessage = "Image must be smaller than 3 MB."
            return false
        }

        let id = UUID()
        let path = "\(postID.uuidString.lowercased())/" +
            "\(authorID.uuidString.lowercased())/\(id.uuidString.lowercased()).jpg"

        do {
            try await client.storage.from(bucket).upload(
                path: path,
                file: jpeg,
                options: FileOptions(contentType: "image/jpeg")
            )
            do {
                try await client.from("train_together_recap_photos")
                    .insert(
                        CirclePhotoInsert(
                            id: id, postID: postID,
                            authorID: authorID, storagePath: path
                        )
                    )
                    .execute()
            } catch {
                _ = try? await client.storage.from(bucket).remove(paths: [path])
                throw error
            }
            await refresh(postID: postID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// Shown only for host/approved athletes; backend policies also enforce access.
/// Chat is available before training. Recap and gallery open after scheduled start.
struct TrainTogetherCircleView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var marketplace: TrainTogetherMarketplaceStore
    @StateObject private var circle = TrainTogetherCircleStore()

    let post: TrainTogetherPost
    let isHost: Bool

    @State private var messageDraft = ""
    @State private var recapNote = ""
    @State private var recapMinutes = ""
    @State private var recapKilometers = ""
    @State private var recapLoaded = false
    @State private var showingRepeatWorkout = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false

    private var recapAvailable: Bool {
        post.scheduledStart <= Date() && post.status != .cancelled
    }

    var body: some View {
        VStack(spacing: 14) {
            chatCard

            if recapAvailable {
                recapCard
            }
        }
        .task(id: post.id) {
            // Refresh only while a participant has the detail view open.
            // No background tracking, polling from Home, or notification spam.
            while !Task.isCancelled {
                await circle.refresh(postID: post.id)
                loadRecapOnce()
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .sheet(isPresented: $showingRepeatWorkout) {
            NavigationStack {
                TrainTogetherPostCreateView(
                    initialParticipationMode: post.resolvedParticipationMode,
                    repeating: post
                )
                .environmentObject(marketplace)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                isLoadingPhoto = true
                defer {
                    isLoadingPhoto = false
                    selectedPhoto = nil
                }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    circle.errorMessage = ATHLTHLocalization.choose(
                        english: "Couldn't load that photo.",
                        norwegian: "Kunne ikke laste inn bildet."
                    )
                    return
                }
                _ = await circle.uploadPhoto(
                    postID: post.id,
                    authorID: session.profile.userID,
                    data: data
                )
            }
        }
        .alert(
            ATHLTHLocalization.choose(
                english: "Train Together",
                norwegian: "Tren sammen"
            ),
            isPresented: Binding(
                get: { circle.errorMessage != nil },
                set: { if !$0 { circle.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(circle.errorMessage ?? "")
        }
    }

    private var chatCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Workout group chat",
                        norwegian: "Øktchat"
                    ),
                    systemImage: "bubble.left.and.bubble.right.fill"
                )
                .font(.headline)

                Text(
                    ATHLTHLocalization.choose(
                        english: "Only the organizer and approved participants can see these messages.",
                        norwegian: "Kun arrangøren og godkjente deltakere kan lese meldingene."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if circle.messages.isEmpty {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Say hello or arrange the details before training.",
                            norwegian: "Si hei eller avtal detaljer før dere trener."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                } else {
                    ForEach(circle.messages.suffix(30)) { message in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(message.senderDisplayName)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(message.createdAt.formatted(
                                    date: .omitted, time: .shortened
                                ))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            Text(message.body)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(
                            message.senderID == session.profile.userID
                                ? ATHLTHTheme.vitalitySoft
                                : Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                }

                HStack(spacing: 8) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "Message participants…",
                            norwegian: "Melding til deltakerne…"
                        ),
                        text: $messageDraft,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)

                    Button {
                        let draft = messageDraft
                        Task {
                            if await circle.send(
                                postID: post.id,
                                userID: session.profile.userID,
                                name: session.profile.displayName,
                                text: draft
                            ) {
                                messageDraft = ""
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(
                        post.status == .cancelled ||
                        circle.isSending ||
                        messageDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }

    private var recapCard: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Together after the workout",
                        norwegian: "Sammen etter økten"
                    ),
                    systemImage: "person.3.fill"
                )
                .font(.headline)

                Label(
                    ATHLTHLocalization.format(
                        english: "%d participants",
                        norwegian: "%d deltakere",
                        post.acceptedGuests + 1
                    ),
                    systemImage: "person.2"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let recap = circle.recap {
                    if let minutes = recap.actualMinutes {
                        Label(
                            "\(minutes) min " +
                                ATHLTHLocalization.choose(
                                    english: "completed", norwegian: "gjennomført"
                                ),
                            systemImage: "clock"
                        )
                    }
                    if let km = recap.actualKilometers {
                        Label(
                            String(format: "%.1f km", km),
                            systemImage: "figure.run"
                        )
                    }
                    if !recap.note.isEmpty {
                        Text(recap.note)
                            .font(.subheadline)
                    }
                } else {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "No confirmed results yet. Planned distance and duration are not treated as completed.",
                            norwegian: "Ingen bekreftede resultater ennå. Planlagt distanse og varighet regnes ikke som gjennomført."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if isHost {
                    Divider()
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "How did it go?",
                            norwegian: "Hvordan gikk økten?"
                        ),
                        text: $recapNote,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    HStack(spacing: 10) {
                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Actual minutes",
                                norwegian: "Faktiske minutter"
                            ),
                            text: $recapMinutes
                        )
                        .keyboardType(.numberPad)

                        TextField(
                            ATHLTHLocalization.choose(
                                english: "Actual km",
                                norwegian: "Faktiske km"
                            ),
                            text: $recapKilometers
                        )
                        .keyboardType(.decimalPad)
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        let minutes = Int(recapMinutes)
                        let distance = Double(
                            recapKilometers.replacingOccurrences(of: ",", with: ".")
                        )
                        Task {
                            _ = await circle.saveRecap(
                                postID: post.id,
                                authorID: session.profile.userID,
                                note: recapNote,
                                minutes: minutes,
                                kilometers: distance
                            )
                        }
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Save shared recap",
                                norwegian: "Lagre felles oppsummering"
                            ),
                            systemImage: "checkmark.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.vitality)
                    .disabled(
                        circle.isSending ||
                        (!recapMinutes.isEmpty &&
                            (Int(recapMinutes) ?? 0) <= 0) ||
                        (!recapKilometers.isEmpty &&
                            (Double(
                                recapKilometers.replacingOccurrences(
                                    of: ",", with: "."
                                )
                            ) ?? 0) <= 0)
                    )
                }

                Divider()

                Text(
                    ATHLTHLocalization.choose(
                        english: "Train together again",
                        norwegian: "Tren sammen igjen"
                    )
                )
                .font(.subheadline.weight(.semibold))

                ForEach(followableAthletes, id: \.userID) { profile in
                    HStack(spacing: 10) {
                        SocialAvatar(profile: profile, size: 34)
                        Text(profile.resolvedName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()

                        if social.isFollowing(profile.userID) {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Following", norwegian: "Følger"
                                )
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.vitality)
                        } else if social.relationshipState(
                            with: profile.userID
                        ) == .outgoingPending {
                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Requested", norwegian: "Forespurt"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task {
                                    if profile.isPrivateProfile {
                                        await social.sendFollowRequest(to: profile)
                                    } else {
                                        await social.follow(profile)
                                    }
                                }
                            } label: {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Follow", norwegian: "Følg"
                                    )
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHTheme.vitality)
                        }
                    }
                }

                Button {
                    showingRepeatWorkout = true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Plan a similar workout",
                            norwegian: "Planlegg en lignende økt"
                        ),
                        systemImage: "calendar.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHTheme.vitality)

                Divider()

                HStack {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Shared photos",
                            norwegian: "Felles bilder"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Add photo",
                                norwegian: "Legg til bilde"
                            ),
                            systemImage: "photo.badge.plus"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .disabled(isLoadingPhoto || circle.isSending)
                }

                if !circle.photos.isEmpty {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 7
                    ) {
                        ForEach(circle.photos) { photo in
                            if let url = circle.photoURLs[photo.id] {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        Color.primary.opacity(0.05)
                                            .overlay {
                                                Image(systemName: "photo")
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .frame(height: 92)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                } else {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Photos are private to approved workout participants.",
                            norwegian: "Bildene er private for godkjente deltakere."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(
                    ATHLTHLocalization.choose(
                        english: "Share only photos you have permission to share. No location or health data is attached automatically.",
                        norwegian: "Del bare bilder du har tillatelse til å dele. Posisjon eller helsedata legges ikke ved automatisk."
                    )
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var followableAthletes: [SocialProfileCard] {
        var people: [SocialProfileCard] = []
        if post.creatorID != session.profile.userID,
           let creator = social.profile(for: post.creatorID) {
            people.append(creator)
        }
        if isHost {
            for request in marketplace.requests where
                request.postID == post.id && request.state == .accepted {
                // Only use an actual loaded profile with its privacy setting,
                // not the public-visibility snapshot in an old RSVP.
                if let profile = social.profile(for: request.requesterID) {
                    people.append(profile)
                }
            }
        }
        var seen = Set<UUID>()
        return people.filter {
            $0.userID != session.profile.userID &&
            social.relationshipState(with: $0.userID) != .blocked &&
            seen.insert($0.userID).inserted
        }
    }

    private func loadRecapOnce() {
        guard !recapLoaded, let recap = circle.recap else { return }
        recapLoaded = true
        recapNote = recap.note
        recapMinutes = recap.actualMinutes.map(String.init) ?? ""
        recapKilometers = recap.actualKilometers.map {
            String(format: "%.1f", $0)
        } ?? ""
    }
}
