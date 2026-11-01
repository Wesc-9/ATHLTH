import Foundation
import Supabase
import SwiftUI

/// Custom names may repeat across athletes; only shipped ATHLTH/RepDB
/// library titles are reserved. All matching is case/whitespace/diacritic
/// insensitive, including the Norwegian localized name where available.
enum ATHLTHExerciseNamePolicy {
    static func key(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }

    @MainActor
    static func collidesWithCatalog(
        _ name: String,
        library: ExerciseLibraryStore
    ) -> Bool {
        let proposed = key(name)
        guard !proposed.isEmpty else { return false }
        return library.allExercises.contains { item in
            guard item.source != .custom else { return false }
            return key(item.canonicalName) == proposed ||
                key(library.localizedExerciseName(item)) == proposed
        }
    }
}

/// A marketplace record is always original-creator-owned. Private copies
/// stay inside the recipient's local exercise library.
struct ATHLTHMarketplaceExercise: Codable, Identifiable, Hashable {
    let id: UUID
    let creatorID: UUID
    let creatorUsername: String
    let exerciseName: String
    let instructions: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case creatorUsername = "creator_username"
        case exerciseName = "exercise_name"
        case instructions
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case equipment
        case createdAt = "created_at"
    }

    var snapshot: ExerciseSnapshot {
        ExerciseSnapshot(
            name: exerciseName, instructions: instructions,
            primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles,
            equipment: equipment, imageURL: nil
        )
    }

    var authorLabel: String {
        ATHLTHLocalization.choose(
            english: "Created by @\(creatorUsername)",
            norwegian: "Laget av @\(creatorUsername)"
        )
    }
}

private struct ATHLTHMarketplaceExerciseWrite: Encodable {
    let id: UUID
    let creatorID: UUID
    let creatorUsername: String
    let exerciseName: String
    let instructions: [String]
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case creatorID = "creator_id"
        case creatorUsername = "creator_username"
        case exerciseName = "exercise_name"
        case instructions
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case equipment
    }
}

@MainActor
final class ATHLTHExerciseMarketplaceStore: ObservableObject {
    @Published private(set) var listings: [ATHLTHMarketplaceExercise] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let client = SupabaseEnvironment.client

    func isPublished(_ id: UUID) -> Bool {
        listings.contains(where: { $0.id == id })
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: [ATHLTHMarketplaceExercise] = try await client
                .from("exercise_marketplace")
                .select()
                .order("created_at", ascending: false)
                .limit(300)
                .execute()
                .value
            guard !Task.isCancelled else { return }
            listings = fetched
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            // Do not clear a previously loaded marketplace on network loss.
            errorMessage = error.localizedDescription
        }
    }

    /// Publication is separate from the private "share in plans" permission.
    /// Only the actual original author may publish this exercise record.
    @discardableResult
    func publish(
        _ entry: ExerciseLibraryEntry,
        library: ExerciseLibraryStore,
        ownerID: UUID,
        username: String
    ) async -> Bool {
        guard !isWorking else { return false }
        guard ATHLTHPersonalExerciseSharing.isEligible(
            entry, ownerID: ownerID
        ), entry.exercise.sharedSourceExerciseID == nil,
           entry.exercise.originalCreatorID == nil ||
                entry.exercise.originalCreatorID == ownerID else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Only the original creator can publish this exercise.",
                norwegian: "Bare den opprinnelige skaperen kan publisere øvelsen."
            )
            return false
        }
        guard !ATHLTHExerciseNamePolicy.collidesWithCatalog(
            entry.canonicalName, library: library
        ) else {
            errorMessage = ATHLTHLocalization.choose(
                english: "This name already belongs to a library exercise. Choose another name.",
                norwegian: "Navnet finnes allerede i øvelsesbiblioteket. Velg et annet navn."
            )
            return false
        }
        let cleanUsername = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !cleanUsername.isEmpty else {
            errorMessage = ATHLTHLocalization.choose(
                english: "Create a username before publishing.",
                norwegian: "Du må ha et brukernavn før du publiserer."
            )
            return false
        }
        // Never upload local pictures, video paths or private metadata.
        let safe = ATHLTHExerciseReferenceResolver.safeImportedSnapshot(
            ExerciseSnapshot(
                name: entry.canonicalName,
                instructions: entry.exercise.instructions,
                primaryMuscles: entry.exercise.primaryMuscles,
                secondaryMuscles: entry.exercise.secondaryMuscles,
                equipment: entry.exercise.equipment,
                imageURL: nil
            ),
            fallbackTitle: entry.canonicalName
        )
        guard let safe else { return false }
        let payload = ATHLTHMarketplaceExerciseWrite(
            id: entry.id,
            creatorID: ownerID,
            creatorUsername: cleanUsername,
            exerciseName: safe.name,
            instructions: safe.instructions,
            primaryMuscles: safe.primaryMuscles,
            secondaryMuscles: safe.secondaryMuscles ?? [],
            equipment: safe.equipment
        )
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.from("exercise_marketplace")
                .insert(payload)
                .execute()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func remove(_ id: UUID, ownerID: UUID) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.from("exercise_marketplace")
                .delete()
                .eq("id", value: id.uuidString)
                .eq("creator_id", value: ownerID.uuidString)
                .execute()
            listings.removeAll { $0.id == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct ATHLTHExerciseMarketplaceView: View {
    @EnvironmentObject private var library: ExerciseLibraryStore
    @EnvironmentObject private var session: AppSessionStore
    @StateObject private var market = ATHLTHExerciseMarketplaceStore()
    @State private var search = ""
    @State private var savedIDs: Set<UUID> = []
    @State private var feedback: String?

    private var visibleListings: [ATHLTHMarketplaceExercise] {
        let key = ATHLTHExerciseNamePolicy.key(search)
        return market.listings.filter { item in
            item.creatorID != session.profile.userID &&
            (key.isEmpty || ATHLTHExerciseNamePolicy.key(
                item.exerciseName + " " + item.creatorUsername + " " +
                item.primaryMuscles.joined(separator: " ")
            ).contains(key))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ATHLTHLocalization.choose(
                        english: "Exercise Marketplace",
                        norwegian: "Øvelsesmarked"
                    ))
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    Text(ATHLTHLocalization.choose(
                        english: "Original exercises shared publicly by other athletes.",
                        norwegian: "Egendefinerte øvelser som andre utøvere har publisert."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 5)

                if let error = market.errorMessage {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(ATHLTHLocalization.choose(
                        english: "Try again", norwegian: "Prøv igjen"
                    )) {
                        Task { await market.refresh() }
                    }
                    .font(.caption.weight(.semibold))
                }

                if market.isLoading && !market.hasLoaded {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                } else if visibleListings.isEmpty && market.hasLoaded {
                    ContentUnavailableView(
                        ATHLTHLocalization.choose(
                            english: "No public exercises found",
                            norwegian: "Ingen offentlige øvelser funnet"
                        ),
                        systemImage: "figure.strengthtraining.traditional"
                    )
                }

                ForEach(visibleListings) { item in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title3)
                                .foregroundStyle(ATHLTHTheme.premiumGold)
                                .frame(width: 42, height: 42)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 13)
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)
                                Text(item.authorLabel)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(item.primaryMuscles.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }

                        if let first = item.instructions.first, !first.isEmpty {
                            Text(first)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        Button {
                            let imported = library.importSharedExercise(
                                item.snapshot,
                                ownerID: session.profile.userID,
                                sourceExerciseID: item.id,
                                originalCreatorID: item.creatorID,
                                originalCreatorUsername: item.creatorUsername,
                                originalExerciseID: item.id
                            )
                            if imported != nil {
                                savedIDs.insert(item.id)
                                feedback = ATHLTHLocalization.choose(
                                    english: "Added to My Exercises.",
                                    norwegian: "Lagt til i Mine øvelser."
                                )
                            }
                        } label: {
                            Label(
                                savedIDs.contains(item.id)
                                    ? ATHLTHLocalization.choose(
                                        english: "Added", norwegian: "Lagt til"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Add to My Exercises",
                                        norwegian: "Legg til i Mine øvelser"
                                    ),
                                systemImage: savedIDs.contains(item.id)
                                    ? "checkmark.circle.fill" : "plus.circle"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(ATHLTHPlanDesign.accentInk)
                        .disabled(savedIDs.contains(item.id))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .athlthBrandedCard(radius: 20)
                }
            }
            .padding(17)
        }
        .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
        .tint(ATHLTHPlanDesign.accentInk)
        .navigationTitle(ATHLTHLocalization.choose(
            english: "Marketplace", norwegian: "Marked"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: ATHLTHLocalization.choose(
            english: "Search exercises or creators",
            norwegian: "Søk øvelser eller skapere"
        ))
        .refreshable { await market.refresh() }
        .task { await market.refresh() }
        .alert(
            ATHLTHLocalization.choose(
                english: "My Exercises", norwegian: "Mine øvelser"
            ),
            isPresented: Binding(
                get: { feedback != nil },
                set: { if !$0 { feedback = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedback ?? "")
        }
    }
}
