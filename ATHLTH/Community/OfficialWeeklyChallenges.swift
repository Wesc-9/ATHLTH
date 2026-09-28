import Foundation
import Supabase
import SwiftUI

enum OfficialRunningChallengeKind: String, Codable, CaseIterable, Identifiable {
    case distance
    case sessions
    case minutes
    case streak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return "Distance"
        case .sessions: return "Run / walk sessions"
        case .minutes: return "Run / walk time"
        case .streak: return "Run / walk days"
        }
    }

    var icon: String {
        switch self {
        case .distance: return "figure.run"
        case .sessions: return "checkmark.circle.fill"
        case .minutes: return "clock.fill"
        case .streak: return "flame.fill"
        }
    }

    func targetText(_ target: Double) -> String {
        switch self {
        case .distance:
            return target == target.rounded()
                ? "\(Int(target)) km"
                : String(format: "%.1f km", target)
        case .sessions:
            return "\(Int(target.rounded())) workouts"
        case .minutes:
            return "\(Int(target.rounded())) min"
        case .streak:
            return "\(Int(target.rounded())) days"
        }
    }

    var targetLabel: String {
        switch self {
        case .distance: return "Target distance (km)"
        case .sessions: return "Number of run / walk workouts"
        case .minutes: return "Run / walk minutes"
        case .streak: return "Run / walk days"
        }
    }
}

struct OfficialWeeklyChallenge: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var subtitle: String
    var kind: OfficialRunningChallengeKind
    var targetValue: Double
    var startsAt: Date
    var endsAt: Date
    var heroAsset: String
    var source: String
    var createdBy: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case kind
        case targetValue = "target_value"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case heroAsset = "hero_asset"
        case source
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isActive: Bool {
        startsAt <= Date() && endsAt > Date()
    }

    var isUpcoming: Bool {
        startsAt > Date()
    }
}

struct OfficialWeeklyChallengeParticipant: Codable, Hashable {
    let challengeID: UUID
    let userID: UUID
    let joinedAt: Date
    let completedAt: Date?
    let completionValue: Double?

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
        case completedAt = "completed_at"
        case completionValue = "completion_value"
    }
}

struct OfficialWeeklyChallengeAIDraft: Codable, Hashable {
    let title: String
    let subtitle: String
    let kind: OfficialRunningChallengeKind
    let targetValue: Double
}

private struct OfficialWeeklyChallengeAIRequest: Encodable {
    let startDate: String
    let endDate: String
    let previousTitles: [String]
    let notes: String
}

private struct OfficialWeeklyChallengeCoverRequest: Encodable {
    let challengeId: UUID
}

private struct OfficialWeeklyChallengeCoverResponse: Decodable {
    let generated: Bool
    let heroAsset: String?
    let reason: String?
}

private struct OfficialWeeklyChallengeWrite: Encodable {
    let id: UUID
    let title: String
    let subtitle: String
    let kind: String
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let heroAsset: String
    let source: String
    let createdBy: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case kind
        case targetValue = "target_value"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case heroAsset = "hero_asset"
        case source
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct OfficialWeeklyChallengeParticipantWrite: Encodable {
    let challengeID: UUID
    let userID: UUID
    let joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
    }
}

private struct OfficialWeeklyChallengeShiftParams: Encodable {
    let after: Date

    enum CodingKeys: String, CodingKey {
        case after = "p_after"
    }
}

private struct OfficialWeeklyChallengeCompletionUpdate: Encodable {
    let completedAt: Date
    let completionValue: Double

    enum CodingKeys: String, CodingKey {
        case completedAt = "completed_at"
        case completionValue = "completion_value"
    }
}

@MainActor
final class OfficialWeeklyChallengeStore: ObservableObject {
    @Published private(set) var challenges: [OfficialWeeklyChallenge] = []
    @Published private(set) var participants: [OfficialWeeklyChallengeParticipant] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isGeneratingAI = false
    @Published private(set) var isGeneratingCover = false
    @Published var errorMessage: String?

    private let client: SupabaseClient
    private var lastRefreshAt: Date?

    init(client: SupabaseClient = SupabaseEnvironment.client) {
        self.client = client
    }

    var activeChallenge: OfficialWeeklyChallenge? {
        challenges
            .filter(\.isActive)
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }

    var upcomingChallenges: [OfficialWeeklyChallenge] {
        challenges
            .filter(\.isUpcoming)
            .sorted { $0.startsAt < $1.startsAt }
    }

    var currentAndUpcoming: [OfficialWeeklyChallenge] {
        challenges
            .filter { $0.endsAt > Date() }
            .sorted { $0.startsAt < $1.startsAt }
    }

    func refresh(force: Bool = false) async {
        guard client.auth.currentUser != nil else {
            challenges = []
            participants = []
            return
        }

        if !force,
           let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < 180,
           !challenges.isEmpty {
            return
        }

        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            async let challengeQuery: [OfficialWeeklyChallenge] = client
                .from("official_weekly_challenges")
                .select()
                .order("starts_at", ascending: true)
                .execute()
                .value

            async let participantQuery: [OfficialWeeklyChallengeParticipant] = client
                .from("official_weekly_challenge_participants")
                .select()
                .execute()
                .value

            let loadedChallenges = try await challengeQuery
            let loadedParticipants = try await participantQuery

            guard !Task.isCancelled else { return }

            challenges = loadedChallenges
            participants = loadedParticipants
            lastRefreshAt = Date()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func participantCount(for challengeID: UUID) -> Int {
        participants.filter { $0.challengeID == challengeID }.count
    }

    func completedCount(for challengeID: UUID) -> Int {
        participants.filter {
            $0.challengeID == challengeID &&
            $0.completedAt != nil
        }.count
    }

    func participantIDs(for challengeID: UUID) -> [UUID] {
        participants
            .filter { $0.challengeID == challengeID }
            .sorted { $0.joinedAt < $1.joinedAt }
            .map(\.userID)
    }

    func rank(for challengeID: UUID) -> Int? {
        guard let userID = client.auth.currentUser?.id else { return nil }

        let ranked = participants
            .filter { $0.challengeID == challengeID }
            .sorted {
                ($0.completionValue ?? 0) >
                ($1.completionValue ?? 0)
            }

        guard let index = ranked.firstIndex(
            where: { $0.userID == userID }
        ) else {
            return nil
        }

        return index + 1
    }

    func leadingParticipants(
        for challengeID: UUID,
        limit: Int = 5
    ) -> [OfficialWeeklyChallengeParticipant] {
        Array(
            participants
                .filter { $0.challengeID == challengeID }
                .sorted {
                    ($0.completionValue ?? 0) >
                    ($1.completionValue ?? 0)
                }
                .prefix(max(limit, 0))
        )
    }

    func isJoined(_ challengeID: UUID) -> Bool {
        guard let userID = client.auth.currentUser?.id else { return false }

        return participants.contains {
            $0.challengeID == challengeID &&
            $0.userID == userID
        }
    }

    func isCompleted(_ challengeID: UUID) -> Bool {
        currentParticipant(for: challengeID)?.completedAt != nil
    }

    func completionValue(for challengeID: UUID) -> Double? {
        currentParticipant(for: challengeID)?.completionValue
    }

    func completionDate(for challengeID: UUID) -> Date? {
        currentParticipant(for: challengeID)?.completedAt
    }

    private func currentParticipant(
        for challengeID: UUID
    ) -> OfficialWeeklyChallengeParticipant? {
        guard let userID = client.auth.currentUser?.id else { return nil }

        return participants.first {
            $0.challengeID == challengeID &&
            $0.userID == userID
        }
    }

    func syncCompletionState(
        workouts: [WorkoutSummary]
    ) async {
        guard let userID = client.auth.currentUser?.id else { return }

        let joinedRows = participants.filter {
            $0.userID == userID &&
            $0.completedAt == nil
        }

        guard !joinedRows.isEmpty else { return }

        var didUpdate = false

        for row in joinedRows {
            guard let challenge = challenges.first(
                where: { $0.id == row.challengeID }
            ) else {
                continue
            }

            let value = OfficialWeeklyChallengeProgress.currentValue(
                challenge: challenge,
                workouts: workouts
            )

            guard value >= challenge.targetValue else { continue }

            do {
                try await client
                    .from("official_weekly_challenge_participants")
                    .update(
                        OfficialWeeklyChallengeCompletionUpdate(
                            completedAt: Date(),
                            completionValue: value
                        )
                    )
                    .eq("challenge_id", value: challenge.id)
                    .eq("user_id", value: userID)
                    .execute()

                didUpdate = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        if didUpdate {
            await refresh(force: true)
        }
    }

    func join(_ challenge: OfficialWeeklyChallenge) async {
        guard let userID = client.auth.currentUser?.id else { return }

        do {
            try await client
                .from("official_weekly_challenge_participants")
                .upsert(
                    OfficialWeeklyChallengeParticipantWrite(
                        challengeID: challenge.id,
                        userID: userID,
                        joinedAt: Date()
                    )
                )
                .execute()

            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leave(_ challenge: OfficialWeeklyChallenge) async {
        guard let userID = client.auth.currentUser?.id else { return }

        do {
            try await client
                .from("official_weekly_challenge_participants")
                .delete()
                .eq("challenge_id", value: challenge.id)
                .eq("user_id", value: userID)
                .execute()

            await refresh(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(
        existing: OfficialWeeklyChallenge?,
        title: String,
        subtitle: String,
        kind: OfficialRunningChallengeKind,
        targetValue: Double,
        startsAt: Date,
        endsAt: Date,
        source: String
    ) async -> Bool {
        guard let currentUserID = client.auth.currentUser?.id else {
            errorMessage = "Sign in again to manage challenges."
            return false
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else {
            errorMessage = "Add a challenge title."
            return false
        }

        guard targetValue > 0 else {
            errorMessage = "Target must be greater than zero."
            return false
        }

        guard endsAt > startsAt else {
            errorMessage = "Challenge end must be after its start."
            return false
        }

        let now = Date()
        let challengeID = existing?.id ?? UUID()
        let previousHeroAsset = {
            let asset = existing?.heroAsset ?? ""
            return ["CommunityHero", "TrainHero"].contains(asset)
                ? ""
                : asset
        }()
        let coverNeedsRefresh =
            existing == nil ||
            previousHeroAsset.isEmpty ||
            existing?.title != cleanTitle ||
            existing?.subtitle != cleanSubtitle ||
            existing?.kind != kind ||
            existing?.targetValue != targetValue

        let write = OfficialWeeklyChallengeWrite(
            id: challengeID,
            title: cleanTitle,
            subtitle: cleanSubtitle,
            kind: kind.rawValue,
            targetValue: targetValue,
            startsAt: startsAt,
            endsAt: endsAt,
            heroAsset: previousHeroAsset,
            source: source,
            createdBy: existing?.createdBy ?? currentUserID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        do {
            try await client
                .from("official_weekly_challenges")
                .upsert(write)
                .execute()

            await refresh(force: true)

            if coverNeedsRefresh {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.generateCover(
                        for: challengeID,
                        reportError: false
                    )
                }
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ challenge: OfficialWeeklyChallenge) async -> Bool {
        do {
            try await client
                .from("official_weekly_challenges")
                .delete()
                .eq("id", value: challenge.id)
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func shiftFutureChallengesForward(
        after challengeStart: Date
    ) async -> Bool {
        do {
            try await client
                .rpc(
                    "shift_official_weekly_challenges_forward",
                    params: OfficialWeeklyChallengeShiftParams(
                        after: challengeStart
                    )
                )
                .execute()

            await refresh(force: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func generateAI(
        startsAt: Date,
        endsAt: Date,
        notes: String = ""
    ) async -> OfficialWeeklyChallengeAIDraft? {
        isGeneratingAI = true
        defer { isGeneratingAI = false }

        let formatter = ISO8601DateFormatter()
        let request = OfficialWeeklyChallengeAIRequest(
            startDate: formatter.string(from: startsAt),
            endDate: formatter.string(from: endsAt),
            previousTitles: Array(
                challenges
                    .sorted { $0.startsAt > $1.startsAt }
                    .prefix(8)
                    .map(\.title)
            ),
            notes: notes
        )

        do {
            let draft: OfficialWeeklyChallengeAIDraft =
                try await client.functions.invoke(
                    "generate-weekly-running-challenge",
                    options: FunctionInvokeOptions(body: request)
                )

            errorMessage = nil
            return draft
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func generateCover(
        for challengeID: UUID,
        reportError: Bool = true
    ) async -> Bool {
        guard !isGeneratingCover else {
            return false
        }

        isGeneratingCover = true
        defer { isGeneratingCover = false }

        do {
            let response: OfficialWeeklyChallengeCoverResponse =
                try await client.functions.invoke(
                    "generate-weekly-challenge-cover",
                    options: FunctionInvokeOptions(
                        body: OfficialWeeklyChallengeCoverRequest(
                            challengeId: challengeID
                        )
                    )
                )

            if response.generated,
               response.heroAsset?.isEmpty == false {
                errorMessage = nil
                await refresh(force: true)
                return true
            }

            if reportError {
                errorMessage =
                    "The challenge was saved, but its Groq-directed cover could not be created."
            }

            return false
        } catch {
            if reportError {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func nextAvailableWindow() -> (Date, Date) {
        if let latestEnd = challenges.map(\.endsAt).max(),
           latestEnd > Date() {
            return (latestEnd, latestEnd.addingTimeInterval(7 * 86_400))
        }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current

        let start: Date
        if let interval = calendar.dateInterval(
            of: .weekOfYear,
            for: Date()
        ) {
            start = interval.end
        } else {
            start = calendar.startOfDay(
                for: Date().addingTimeInterval(86_400)
            )
        }

        return (start, start.addingTimeInterval(7 * 86_400))
    }
}

enum OfficialWeeklyChallengeProgress {
    static func currentValue(
        challenge: OfficialWeeklyChallenge,
        workouts: [WorkoutSummary]
    ) -> Double {
        let workouts = countedWorkouts(
            challenge: challenge,
            workouts: workouts
        )

        switch challenge.kind {
        case .distance:
            return workouts
                .compactMap(\.distanceMeters)
                .reduce(0, +) / 1_000

        case .sessions:
            return Double(workouts.count)

        case .minutes:
            return workouts.reduce(0) {
                $0 + ($1.duration / 60)
            }

        case .streak:
            return Double(longestActivityStreak(workouts))
        }
    }

    static func fraction(
        challenge: OfficialWeeklyChallenge,
        workouts: [WorkoutSummary]
    ) -> Double {
        guard challenge.targetValue > 0 else { return 0 }

        return min(
            max(
                currentValue(
                    challenge: challenge,
                    workouts: workouts
                ) / challenge.targetValue,
                0
            ),
            1
        )
    }

    static func valueText(
        challenge: OfficialWeeklyChallenge,
        workouts: [WorkoutSummary]
    ) -> String {
        let value = currentValue(
            challenge: challenge,
            workouts: workouts
        )

        switch challenge.kind {
        case .distance:
            return String(
                format: "%.1f / %.0f km",
                value,
                challenge.targetValue
            )

        case .sessions:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) workouts"

        case .minutes:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) min"

        case .streak:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) days"
        }
    }

    static func countedWorkouts(
        challenge: OfficialWeeklyChallenge,
        workouts: [WorkoutSummary]
    ) -> [WorkoutSummary] {
        workouts
            .filter {
                ($0.activity == .running || $0.activity == .walking) &&
                $0.startDate >= challenge.startsAt &&
                $0.startDate < challenge.endsAt
            }
            .sorted { $0.startDate > $1.startDate }
    }

    private static func longestActivityStreak(
        _ workouts: [WorkoutSummary]
    ) -> Int {
        guard !workouts.isEmpty else { return 0 }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current

        let days = Array(
            Set(workouts.map { calendar.startOfDay(for: $0.startDate) })
        )
        .sorted()

        var best = 1
        var current = 1

        for index in 1..<days.count {
            let previous = days[index - 1]
            let day = days[index]
            let delta = calendar.dateComponents(
                [.day],
                from: previous,
                to: day
            ).day ?? 0

            if delta == 1 {
                current += 1
                best = max(best, current)
            } else if delta > 1 {
                current = 1
            }
        }

        return best
    }
}

private struct OfficialWeeklyCoverRecipe {
    let palette: String
    let scene: String
    let light: String
    let motif: String
    let energy: String
    let variant: Int

    init?(asset: String) {
        guard
            let components = URLComponents(string: asset),
            components.scheme == "athlth-cover",
            components.host == "v1"
        else {
            return nil
        }

        let values = Dictionary(
            uniqueKeysWithValues:
                (components.queryItems ?? []).map {
                    ($0.name, $0.value ?? "")
                }
        )

        palette = values["palette"] ?? "sage"
        scene = values["scene"] ?? "mountain"
        light = values["light"] ?? "daylight"
        motif = values["motif"] ?? "route"
        energy = values["energy"] ?? "steady"
        variant = Int(values["variant"] ?? "1") ?? 1
    }
}

private struct OfficialWeeklyChallengeArtwork: View {
    let challenge: OfficialWeeklyChallenge

    private var recipe: OfficialWeeklyCoverRecipe? {
        OfficialWeeklyCoverRecipe(asset: challenge.heroAsset)
    }

    private var legacyGenericAssets: Set<String> {
        [
            "CommunityHero",
            "TrainHero"
        ]
    }

    var body: some View {
        Group {
            if let recipe {
                generatedArtwork(recipe)
            } else if let remoteURL = URL(string: challenge.heroAsset),
                      remoteURL.scheme == "https" ||
                      remoteURL.scheme == "http" {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    default:
                        fallbackArtwork
                    }
                }
            } else if !legacyGenericAssets.contains(
                        challenge.heroAsset
                      ),
                      !challenge.heroAsset.isEmpty,
                      UIImage(named: challenge.heroAsset) != nil {
                Image(challenge.heroAsset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                fallbackArtwork
            }
        }
    }

    private func generatedArtwork(
        _ recipe: OfficialWeeklyCoverRecipe
    ) -> some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                // Keep covers visually tied to what the challenge actually
                // asks the athlete to do. The AI recipe art-directs the
                // treatment, while a local run/walk photo provides the
                // semantic base. This is fast, cached with the app and avoids
                // generating or downloading large images at runtime.
                Image(
                    semanticBaseImageName(
                        variant: recipe.variant
                    )
                )
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(
                    width: size.width,
                    height: size.height
                )
                .clipped()

                LinearGradient(
                    colors:
                        paletteColors(recipe.palette)
                        .map { $0.opacity(0.26) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                lightOverlay(recipe.light)

                sceneLayer(
                    recipe.scene,
                    size: size,
                    variant: recipe.variant
                )
                .opacity(0.62)

                routeLayer(
                    size: size,
                    variant: recipe.variant,
                    energy: recipe.energy
                )

                motifLayer(recipe.motif)
                    .frame(
                        width: min(size.width * 0.30, 124),
                        height: min(size.width * 0.30, 124)
                    )
                    .offset(
                        x: size.width * 0.30,
                        y: size.height * 0.16
                    )
                    .opacity(0.72)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipped()
        }
    }

    private func semanticBaseImageName(
        variant: Int
    ) -> String {
        switch challenge.kind {
        case .distance:
            return variant.isMultiple(of: 2)
                ? "HomeHero"
                : "StrengthPostWorkoutHero"

        case .sessions:
            return "HomeHero"

        case .minutes:
            return "StrengthPostWorkoutHero"

        case .streak:
            return "ProfileHero"
        }
    }

    @ViewBuilder
    private func sceneLayer(
        _ scene: String,
        size: CGSize,
        variant: Int
    ) -> some View {
        switch scene {
        case "coast":
            VStack {
                Spacer()
                Image(systemName: "water.waves")
                    .font(.system(size: max(size.width * 0.28, 92)))
                    .foregroundStyle(Color.white.opacity(0.20))
                    .offset(x: variant.isMultiple(of: 2) ? 70 : 110)
            }
        case "forest":
            HStack(alignment: .bottom, spacing: -18) {
                ForEach(0..<4, id: \.self) { index in
                    Image(systemName: "tree.fill")
                        .font(
                            .system(
                                size:
                                    58 +
                                    CGFloat((index + variant) % 3) * 18
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(
                                0.10 + Double(index) * 0.025
                            )
                        )
                }
            }
            .offset(
                x: size.width * 0.18,
                y: size.height * 0.14
            )
        case "city":
            HStack(alignment: .bottom, spacing: 8) {
                Image(systemName: "building.fill")
                Image(systemName: "building.2.fill")
                Image(systemName: "building.fill")
            }
            .font(.system(size: max(size.width * 0.13, 48)))
            .foregroundStyle(Color.white.opacity(0.15))
            .offset(
                x: size.width * 0.22,
                y: size.height * 0.16
            )
        case "track":
            ZStack {
                RoundedRectangle(cornerRadius: 80)
                    .stroke(
                        Color.white.opacity(0.18),
                        lineWidth: 5
                    )
                    .frame(
                        width: size.width * 0.54,
                        height: size.height * 0.44
                    )

                RoundedRectangle(cornerRadius: 70)
                    .stroke(
                        Color.white.opacity(0.11),
                        lineWidth: 3
                    )
                    .frame(
                        width: size.width * 0.44,
                        height: size.height * 0.32
                    )
            }
            .rotationEffect(.degrees(-10))
            .offset(x: size.width * 0.22)
        case "studio":
            Image(systemName: "figure.run")
                .font(.system(size: max(size.width * 0.24, 88)))
                .foregroundStyle(Color.white.opacity(0.16))
                .offset(
                    x: size.width * 0.25,
                    y: size.height * 0.10
                )
        case "mountain":
            Image(systemName: "mountain.2.fill")
                .font(.system(size: max(size.width * 0.31, 112)))
                .foregroundStyle(Color.white.opacity(0.16))
                .offset(
                    x: size.width * 0.22,
                    y: size.height * 0.15
                )
        default:
            EmptyView()
        }
    }

    private func routeLayer(
        size: CGSize,
        variant: Int,
        energy: String
    ) -> some View {
        Canvas { context, canvasSize in
            var path = Path()

            let startY =
                canvasSize.height *
                (variant.isMultiple(of: 2) ? 0.72 : 0.66)

            path.move(
                to: CGPoint(
                    x: canvasSize.width * 0.43,
                    y: startY
                )
            )

            path.addCurve(
                to: CGPoint(
                    x: canvasSize.width * 1.05,
                    y: canvasSize.height *
                        (variant > 2 ? 0.22 : 0.35)
                ),
                control1: CGPoint(
                    x: canvasSize.width * 0.62,
                    y: canvasSize.height * 0.78
                ),
                control2: CGPoint(
                    x: canvasSize.width * 0.72,
                    y: canvasSize.height * 0.26
                )
            )

            let opacity: Double
            switch energy {
            case "energetic":
                opacity = 0.52
            case "calm":
                opacity = 0.28
            default:
                opacity = 0.40
            }

            context.stroke(
                path,
                with: .color(Color.white.opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: energy == "energetic" ? 4 : 3,
                    lineCap: .round,
                    dash: [10, 12]
                )
            )
        }
        .frame(width: size.width, height: size.height)
    }

    private func motifLayer(_ motif: String) -> some View {
        let symbol: String

        switch motif {
        case "waves":
            symbol = "wave.3.right"
        case "steps":
            symbol = "figure.walk.motion"
        case "pulse":
            symbol = "waveform.path.ecg"
        case "streak":
            symbol = "flame.fill"
        case "group":
            symbol = "person.3.fill"
        default:
            symbol = "figure.run"
        }

        return Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.white.opacity(0.13))
            .rotationEffect(.degrees(-8))
    }

    private func lightOverlay(_ light: String) -> some View {
        RadialGradient(
            colors: [
                lightColor(light).opacity(0.42),
                lightColor(light).opacity(0.08),
                Color.clear
            ],
            center: .topTrailing,
            startRadius: 10,
            endRadius: 270
        )
    }

    private func paletteColors(_ palette: String) -> [Color] {
        switch palette {
        case "ocean":
            return [
                Color(red: 0.12, green: 0.42, blue: 0.62),
                Color(red: 0.35, green: 0.68, blue: 0.75),
                Color(red: 0.86, green: 0.82, blue: 0.68)
            ]
        case "amber":
            return [
                Color(red: 0.64, green: 0.30, blue: 0.15),
                Color(red: 0.88, green: 0.55, blue: 0.26),
                Color(red: 0.94, green: 0.80, blue: 0.56)
            ]
        case "violet":
            return [
                Color(red: 0.32, green: 0.26, blue: 0.64),
                Color(red: 0.54, green: 0.43, blue: 0.78),
                Color(red: 0.88, green: 0.72, blue: 0.70)
            ]
        case "rose":
            return [
                Color(red: 0.64, green: 0.28, blue: 0.40),
                Color(red: 0.84, green: 0.50, blue: 0.56),
                Color(red: 0.93, green: 0.77, blue: 0.67)
            ]
        case "slate":
            return [
                Color(red: 0.22, green: 0.30, blue: 0.36),
                Color(red: 0.43, green: 0.55, blue: 0.59),
                Color(red: 0.82, green: 0.81, blue: 0.73)
            ]
        default:
            return [
                Color(red: 0.16, green: 0.53, blue: 0.42),
                Color(red: 0.50, green: 0.74, blue: 0.61),
                Color(red: 0.88, green: 0.83, blue: 0.66)
            ]
        }
    }

    private func lightColor(_ light: String) -> Color {
        switch light {
        case "sunrise":
            return Color(red: 1.0, green: 0.71, blue: 0.47)
        case "golden_hour":
            return Color(red: 1.0, green: 0.76, blue: 0.43)
        case "dusk":
            return Color(red: 0.52, green: 0.48, blue: 0.82)
        default:
            return .white
        }
    }

    private var fallbackArtwork: some View {
        GeometryReader { proxy in
            ZStack {
                Image(
                    semanticBaseImageName(
                        variant: 1
                    )
                )
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .clipped()

                LinearGradient(
                    colors:
                        fallbackColors
                        .map { $0.opacity(0.22) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Image(systemName: challenge.kind.icon)
                    .font(.system(size: 70, weight: .semibold))
                    .foregroundStyle(
                        Color.white.opacity(0.16)
                    )
                    .rotationEffect(.degrees(-8))
                    .offset(
                        x: proxy.size.width * 0.30,
                        y: proxy.size.height * 0.18
                    )
            }
            .clipped()
        }
    }

    private var fallbackColors: [Color] {
        switch challenge.kind {
        case .distance:
            return [
                Color(red: 0.16, green: 0.53, blue: 0.42),
                Color(red: 0.50, green: 0.74, blue: 0.61),
                Color(red: 0.88, green: 0.83, blue: 0.66)
            ]
        case .sessions:
            return [
                Color(red: 0.35, green: 0.30, blue: 0.68),
                Color(red: 0.55, green: 0.43, blue: 0.78),
                Color(red: 0.88, green: 0.72, blue: 0.61)
            ]
        case .minutes:
            return [
                Color(red: 0.16, green: 0.46, blue: 0.69),
                Color(red: 0.43, green: 0.69, blue: 0.80),
                Color(red: 0.88, green: 0.82, blue: 0.67)
            ]
        case .streak:
            return [
                Color(red: 0.70, green: 0.34, blue: 0.18),
                Color(red: 0.88, green: 0.55, blue: 0.28),
                Color(red: 0.92, green: 0.80, blue: 0.59)
            ]
        }
    }
}

struct OfficialWeeklyChallengeCard: View {
    @EnvironmentObject private var store: OfficialWeeklyChallengeStore
    @EnvironmentObject private var health: HealthKitManager

    let challenge: OfficialWeeklyChallenge
    let profiles: [SocialProfileCard]

    @State private var showingDetails = false

    private var joined: Bool {
        store.isJoined(challenge.id)
    }

    private var progress: Double {
        let localValue =
            OfficialWeeklyChallengeProgress.currentValue(
                challenge: challenge,
                workouts: health.workouts
            )
        let storedValue =
            store.completionValue(for: challenge.id) ?? 0

        return min(
            max(localValue, storedValue) /
                max(challenge.targetValue, 0.0001),
            1
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            challengeArtwork

            LinearGradient(
                colors: [
                    Color.white.opacity(0.88),
                    Color.white.opacity(0.22),
                    Color.black.opacity(0.44)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Label(
                        "WEEKLY CHALLENGE",
                        systemImage: "trophy.fill"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Color.orange.opacity(0.92))
                    .padding(.horizontal, 11)
                    .frame(height: 29)
                    .background(
                        ATHLTHTheme.champagneSoft.opacity(0.96),
                        in: Capsule()
                    )

                    Spacer()

                    Text(timeRemaining)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText.opacity(0.72))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(challenge.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.primaryText.opacity(0.70))
                        .lineLimit(2)
                }
                .frame(maxWidth: 245, alignment: .leading)

                Spacer(minLength: 12)

                HStack(alignment: .bottom, spacing: 12) {
                    HStack(spacing: -7) {
                        ForEach(
                            visibleParticipantProfiles.prefix(4)
                        ) { profile in
                            OfficialChallengeAvatar(
                                url: profile.avatarURL.flatMap(URL.init(string:)),
                                fallback: profile.resolvedName,
                                size: 31
                            )
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: 1.5)
                            }
                        }

                        Text("\(store.participantCount(for: challenge.id)) participating")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(
                                color: .black.opacity(0.28),
                                radius: 3,
                                y: 1
                            )
                            .padding(.leading, 14)
                    }

                    Spacer(minLength: 8)

                    if joined {
                        NavigationLink {
                            OfficialWeeklyChallengeDetailView(
                                challengeID: challenge.id
                            )
                        } label: {
                            Text("Continue")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .padding(.horizontal, 17)
                                .frame(height: 42)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 9) {
                            NavigationLink {
                                OfficialWeeklyChallengeDetailView(
                                    challengeID: challenge.id
                                )
                            } label: {
                                Text("Details")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 42)
                                    .background(
                                        Color.black.opacity(0.28),
                                        in: Capsule()
                                    )
                                    .overlay {
                                        Capsule()
                                            .stroke(
                                                Color.white.opacity(0.32),
                                                lineWidth: 0.8
                                            )
                                    }
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    await store.join(challenge)
                                    await store.syncCompletionState(
                                        workouts: health.workouts
                                    )
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Text("Join Challenge")
                                    Image(systemName: "arrow.right")
                                }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .padding(.horizontal, 17)
                                .frame(height: 42)
                                .background(.white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    progressRing
                        .padding(.trailing, 16)
                        .padding(.bottom, 48)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.08),
            radius: 14,
            y: 7
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .onTapGesture {
            showingDetails = true
        }
        .navigationDestination(isPresented: $showingDetails) {
            OfficialWeeklyChallengeDetailView(
                challengeID: challenge.id
            )
        }
        .task(id: health.workouts.map(\.id)) {
            guard joined else { return }
            await store.syncCompletionState(
                workouts: health.workouts
            )
        }
    }

    private var challengeArtwork: some View {
        OfficialWeeklyChallengeArtwork(
            challenge: challenge
        )
    }

    private var visibleParticipantProfiles: [SocialProfileCard] {
        let ids = Set(store.participantIDs(for: challenge.id))
        return profiles.filter { ids.contains($0.userID) }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.56))

            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 7)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: 7,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("complete")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 76, height: 76)
    }

    private var timeRemaining: String {
        if challenge.startsAt > Date() {
            return "Starts " + challenge.startsAt.formatted(
                .dateTime.month(.abbreviated).day()
            )
        }

        let days = max(
            Calendar.current.dateComponents(
                [.day],
                from: Date(),
                to: challenge.endsAt
            ).day ?? 0,
            0
        )

        return days == 0
            ? "Ends today"
            : "\(days) day\(days == 1 ? "" : "s") left"
    }
}

struct OfficialWeeklyChallengeDetailView: View {
    @EnvironmentObject private var store: OfficialWeeklyChallengeStore
    @EnvironmentObject private var health: HealthKitManager

    let challengeID: UUID

    private var challenge: OfficialWeeklyChallenge? {
        store.challenges.first { $0.id == challengeID }
    }

    private var countedWorkouts: [WorkoutSummary] {
        guard let challenge else { return [] }

        return OfficialWeeklyChallengeProgress.countedWorkouts(
            challenge: challenge,
            workouts: health.workouts
        )
    }

    var body: some View {
        Group {
            if let challenge {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            premiumHeroCard(
                                challenge,
                                scrollProxy: proxy
                            )
                            challengeOverviewSection(challenge)
                            progressSection(challenge)
                                .id("weekly-progress")
                            leaderboardSection(challenge)
                                .id("weekly-leaderboard")
                            countedWorkoutsSection
                            rulesSection(challenge)
                                .id("weekly-rules")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 32)
                    }
                    .background(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.canvasTop,
                            ATHLTHTheme.surfaceStone.opacity(0.70),
                            ATHLTHTheme.canvasBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
                .navigationTitle("Weekly Challenge")
                .navigationBarTitleDisplayMode(.inline)
                    .task(id: health.workouts.map(\.id)) {
                        guard store.isJoined(challenge.id) else { return }
                        await store.syncCompletionState(
                            workouts: health.workouts
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    "Challenge unavailable",
                    systemImage: "trophy",
                    description: Text(
                        "This challenge is no longer available."
                    )
                )
            }
        }
    }

    private func premiumHeroCard(
        _ challenge: OfficialWeeklyChallenge,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                OfficialWeeklyChallengeArtwork(
                    challenge: challenge
                )
                .frame(height: 238)
                .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.02),
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.74)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(
                            "WEEKLY CHALLENGE",
                            systemImage: "sparkles"
                        )
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            Color.black.opacity(0.20),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.white.opacity(0.24),
                                    lineWidth: 0.8
                                )
                        }

                        Spacer()

                        Text(timeRemaining(for: challenge))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(
                                Color.black.opacity(0.20),
                                in: Capsule()
                            )
                    }

                    Spacer()

                    Text(challenge.title)
                        .font(
                            .system(
                                size: 34,
                                weight: .semibold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(challenge.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(3)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    HStack(spacing: 8) {
                        Label(
                            challenge.kind.targetText(
                                challenge.targetValue
                            ),
                            systemImage: challenge.kind.icon
                        )

                        Text("•")

                        Text(
                            "\(store.participantCount(for: challenge.id)) participating"
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                }
                .padding(20)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            store.isJoined(challenge.id)
                                ? "YOUR WEEKLY TARGET"
                                : "RECOMMENDED TARGET"
                        )
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep.opacity(0.76)
                        )

                        Text(primaryProgressText(for: challenge))
                            .font(
                                .system(
                                    size: 32,
                                    weight: .semibold,
                                    design: .serif
                                )
                            )
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        Text(
                            store.isJoined(challenge.id)
                                ? progressStatusDescription(
                                    for: challenge
                                )
                                : challengeFocusDescription(
                                    for: challenge
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                        HStack(spacing: 7) {
                            Image(
                                systemName:
                                    store.isJoined(challenge.id)
                                        ? "checkmark.circle.fill"
                                        : "sparkles"
                            )

                            Text(
                                store.isJoined(challenge.id)
                                    ? progressStatus(for: challenge)
                                    : challengeFocusTitle(for: challenge)
                            )
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 29)
                        .background(
                            ATHLTHTheme.champagneSoft.opacity(0.72),
                            in: Capsule()
                        )
                    }

                    Spacer(minLength: 6)

                    ZStack {
                        Circle()
                            .stroke(
                                ATHLTHTheme.surfaceStone,
                                lineWidth: 7
                            )

                        Circle()
                            .trim(
                                from: 0,
                                to: resolvedProgress(
                                    for: challenge
                                )
                            )
                            .stroke(
                                ATHLTHTheme.vitality,
                                style: StrokeStyle(
                                    lineWidth: 7,
                                    lineCap: .round
                                )
                            )
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 0) {
                            Text(
                                progressPercentText(
                                    for: challenge
                                )
                            )
                            .font(.headline.bold())
                            .monospacedDigit()

                            Text("done")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 82, height: 82)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    OfficialWeeklyChallengeCompactStat(
                        icon: "scope",
                        title: "TARGET",
                        value: compactTargetText(
                            for: challenge
                        ),
                        detail:
                            challenge.kind == .distance
                                ? "Run or walk"
                                : "Weekly goal"
                    )

                    OfficialWeeklyChallengeCompactStat(
                        icon: "chart.bar.fill",
                        title: "PROGRESS",
                        value: progressPercentText(
                            for: challenge
                        ),
                        detail: resolvedProgressText(
                            for: challenge
                        )
                    )

                    OfficialWeeklyChallengeCompactStat(
                        icon: "calendar",
                        title: "TIME LEFT",
                        value: shortTimeRemaining(
                            for: challenge
                        ),
                        detail: dateRangeText(
                            for: challenge
                        )
                    )

                    OfficialWeeklyChallengeCompactStat(
                        icon: "trophy.fill",
                        title: "YOUR RANK",
                        value: rankText(
                            for: challenge
                        ),
                        detail:
                            "\(store.participantCount(for: challenge.id)) participants"
                    )
                }

                HStack(spacing: 8) {
                    Capsule()
                        .fill(ATHLTHTheme.accentDeep.opacity(0.18))
                        .frame(width: 28, height: 3)

                    Text("MAKE THIS WEEK COUNT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.72))

                    Spacer()
                }

                Button {
                    Task {
                        if store.isJoined(challenge.id) {
                            await store.syncCompletionState(
                                workouts: health.workouts
                            )

                            withAnimation(.easeInOut(duration: 0.32)) {
                                scrollProxy.scrollTo(
                                    "weekly-progress",
                                    anchor: .top
                                )
                            }
                        } else {
                            await store.join(challenge)
                            await store.syncCompletionState(
                                workouts: health.workouts
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(
                            systemName:
                                store.isJoined(challenge.id)
                                    ? "figure.run"
                                    : "plus"
                        )

                        Text(
                            store.isJoined(challenge.id)
                                ? "Continue Challenge"
                                : "Join Challenge"
                        )

                        Spacer()

                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [
                                ATHLTHTheme.accentDeep,
                                ATHLTHTheme.accentDeep.opacity(0.86)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.32)) {
                            scrollProxy.scrollTo(
                                "weekly-leaderboard",
                                anchor: .top
                            )
                        }
                    } label: {
                        Label(
                            "Leaderboard",
                            systemImage: "trophy"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            Color.white.opacity(0.78),
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .stroke(
                                ATHLTHTheme.accentDeep.opacity(0.10),
                                lineWidth: 0.8
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.32)) {
                            scrollProxy.scrollTo(
                                "weekly-rules",
                                anchor: .top
                            )
                        }
                    } label: {
                        Label(
                            "How it works",
                            systemImage: "info.circle"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            Color.white.opacity(0.78),
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                            .stroke(
                                ATHLTHTheme.accentDeep.opacity(0.10),
                                lineWidth: 0.8
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }

                if store.isJoined(challenge.id) {
                    HStack {
                        if store.isCompleted(challenge.id) {
                            Label(
                                "Challenge completed",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        } else {
                            Label(
                                progressStatus(
                                    for: challenge
                                ),
                                systemImage: "bolt.heart.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep
                            )
                        }

                        Spacer()

                        Button(role: .destructive) {
                            Task {
                                await store.leave(challenge)
                            }
                        } label: {
                            Text("Leave")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color.white,
                        ATHLTHTheme.champagneSoft.opacity(0.30),
                        ATHLTHTheme.surfaceStone.opacity(0.74)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 26,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 26,
                    style: .continuous
                )
            )
            .offset(y: -18)
            .padding(.bottom, -18)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 34,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 34,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.82),
                lineWidth: 0.9
            )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.09),
            radius: 26,
            x: 0,
            y: 14
        )
    }

    private func challengeOverviewSection(
        _ challenge: OfficialWeeklyChallenge
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THIS WEEK'S FOCUS")
                        .font(.caption.weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                    Text(challengeFocusTitle(for: challenge))
                        .font(
                            .system(
                                size: 25,
                                weight: .semibold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(ATHLTHTheme.primaryText)
                }

                Spacer()

                Image(systemName: challenge.kind.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 44, height: 44)
                    .background(
                        ATHLTHTheme.accent.opacity(0.10),
                        in: Circle()
                    )
            }

            Text(challengeFocusDescription(for: challenge))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                OfficialWeeklyChallengeInsightTile(
                    eyebrow: "GOAL",
                    value: compactTargetText(for: challenge),
                    detail: challenge.kind == .distance
                        ? "Run or walk"
                        : "This week"
                )

                OfficialWeeklyChallengeInsightTile(
                    eyebrow: "WINDOW",
                    value: shortTimeRemaining(for: challenge),
                    detail: dateRangeText(for: challenge)
                )

                OfficialWeeklyChallengeInsightTile(
                    eyebrow: "COMMUNITY",
                    value: "\(store.participantCount(for: challenge.id))",
                    detail:
                        "\(store.completedCount(for: challenge.id)) finished"
                )
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    ATHLTHTheme.champagneSoft.opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.70),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 14,
            y: 7
        )
    }

    private func progressSection(
        _ challenge: OfficialWeeklyChallenge
    ) -> some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your progress")
                        .font(.title3.bold())

                    Text(
                        store.isJoined(challenge.id)
                            ? progressStatusDescription(for: challenge)
                            : "Join to track your progress automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(progressPercentText(for: challenge))
                    .font(.title2.bold())
                    .monospacedDigit()
            }

            ProgressView(
                value: resolvedProgress(
                    for: challenge
                )
            )
            .tint(ATHLTHTheme.vitality)
            .scaleEffect(x: 1, y: 1.35)

            HStack {
                Text(resolvedProgressText(for: challenge))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(remainingText(for: challenge))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func leaderboardSection(
        _ challenge: OfficialWeeklyChallenge
    ) -> some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Leaderboard")
                        .font(.title3.bold())

                    Text(
                        "Community progress for this weekly challenge."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let rank = store.rank(for: challenge.id) {
                    Text("#\(rank)")
                        .font(.title2.bold())
                        .monospacedDigit()
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }

            let leaders = store.leadingParticipants(
                for: challenge.id,
                limit: 5
            )

            if leaders.isEmpty {
                ContentUnavailableView(
                    "No leaderboard yet",
                    systemImage: "trophy",
                    description: Text(
                        "Progress appears here as participants complete qualifying workouts."
                    )
                )
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        Array(leaders.enumerated()),
                        id: \.element.userID
                    ) { index, participant in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(
                                    index < 3
                                        ? ATHLTHTheme.accentDeep
                                        : .secondary
                                )
                                .frame(width: 24)

                            ZStack {
                                Circle()
                                    .fill(
                                        index == 0
                                            ? ATHLTHTheme.champagneSoft
                                            : ATHLTHTheme.surfaceStone
                                    )

                                Image(
                                    systemName:
                                        index == 0
                                            ? "trophy.fill"
                                            : "figure.run"
                                )
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                            }
                            .frame(width: 34, height: 34)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    participantLabel(
                                        participant,
                                        rank: index + 1,
                                        challenge: challenge
                                    )
                                )
                                .font(.subheadline.weight(.semibold))

                                Text(
                                    leaderboardProgressText(
                                        participant,
                                        challenge: challenge
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            let fraction = min(
                                max(
                                    (participant.completionValue ?? 0) /
                                    max(challenge.targetValue, 0.0001),
                                    0
                                ),
                                1
                            )

                            Text(
                                "\(Int((fraction * 100).rounded()))%"
                            )
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        }
                        .padding(.vertical, 9)

                        if index < leaders.count - 1 {
                            Divider()
                                .padding(.leading, 70)
                        }
                    }
                }
            }
        }
    }

    private var countedWorkoutsSection: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Counted workouts")
                        .font(.title3.bold())

                    Text(
                        "Qualifying activity during the challenge window."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(countedWorkouts.count)")
                    .font(.title3.bold())
                    .monospacedDigit()
            }

            if countedWorkouts.isEmpty {
                ContentUnavailableView(
                    "No qualifying workouts yet",
                    systemImage: "figure.walk.motion",
                    description: Text(
                        "Complete a qualifying workout and it will appear here after Health syncs."
                    )
                )
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(countedWorkouts) { workout in
                        OfficialWeeklyCountedWorkoutRow(
                            workout: workout
                        )

                        if workout.id != countedWorkouts.last?.id {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }

    private func rulesSection(
        _ challenge: OfficialWeeklyChallenge
    ) -> some View {
        ATHLTHCard {
            Text("How it works")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 13) {
                detailRuleRow(
                    icon: "calendar",
                    title: "Challenge window",
                    detail: dateRangeText(for: challenge)
                )

                detailRuleRow(
                    icon: challenge.kind.icon,
                    title: "Target",
                    detail: challenge.kind.targetText(
                        challenge.targetValue
                    )
                )

                detailRuleRow(
                    icon: "checkmark.shield",
                    title: "What counts",
                    detail: ruleDescription(for: challenge)
                )

                detailRuleRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Automatic tracking",
                    detail:
                        "ATHLTH checks synced workouts and updates your progress automatically while you participate."
                )
            }
        }
    }

    private func detailRuleRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accent.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func resolvedCurrentValue(
        for challenge: OfficialWeeklyChallenge
    ) -> Double {
        let localValue =
            OfficialWeeklyChallengeProgress.currentValue(
                challenge: challenge,
                workouts: health.workouts
            )

        return max(
            localValue,
            store.completionValue(for: challenge.id) ?? 0
        )
    }

    private func resolvedProgress(
        for challenge: OfficialWeeklyChallenge
    ) -> Double {
        min(
            resolvedCurrentValue(for: challenge) /
                max(challenge.targetValue, 0.0001),
            1
        )
    }

    private func progressPercentText(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        "\(Int((resolvedProgress(for: challenge) * 100).rounded()))%"
    }

    private func primaryProgressText(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        guard store.isJoined(challenge.id) else {
            return challenge.kind.targetText(
                challenge.targetValue
            )
        }

        return resolvedProgressText(for: challenge)
    }

    private func resolvedProgressText(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        let value = resolvedCurrentValue(for: challenge)

        switch challenge.kind {
        case .distance:
            return String(
                format: "%.1f / %.0f km",
                value,
                challenge.targetValue
            )
        case .sessions:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) workouts"
        case .minutes:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) min"
        case .streak:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) days"
        }
    }

    private func remainingText(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        let remaining = max(
            challenge.targetValue -
                resolvedCurrentValue(for: challenge),
            0
        )

        switch challenge.kind {
        case .distance:
            return String(format: "%.1f km", remaining)
        case .sessions:
            return "\(Int(remaining.rounded(.up)))"
        case .minutes:
            return "\(Int(remaining.rounded(.up))) min"
        case .streak:
            return "\(Int(remaining.rounded(.up))) days"
        }
    }

    private func remainingDetail(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        resolvedProgress(for: challenge) >= 1
            ? "Goal reached"
            : "to complete"
    }

    private func progressStatus(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        let progress = resolvedProgress(for: challenge)

        if progress >= 1 {
            return "Completed"
        }

        let elapsed = elapsedFraction(for: challenge)

        if progress + 0.08 >= elapsed {
            return "On track"
        }

        return "Keep going"
    }

    private func progressStatusDescription(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        switch progressStatus(for: challenge) {
        case "Completed":
            return "You reached this week's target."
        case "On track":
            return "Your progress is keeping pace with the challenge window."
        default:
            return "There is still time to move toward the weekly target."
        }
    }

    private func elapsedFraction(
        for challenge: OfficialWeeklyChallenge
    ) -> Double {
        let total = challenge.endsAt.timeIntervalSince(
            challenge.startsAt
        )

        guard total > 0 else { return 1 }

        let elapsed = Date().timeIntervalSince(
            challenge.startsAt
        )

        return min(
            max(elapsed / total, 0),
            1
        )
    }

    private func shortTimeRemaining(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        if challenge.startsAt > Date() {
            let days = max(
                Calendar.current.dateComponents(
                    [.day],
                    from: Date(),
                    to: challenge.startsAt
                ).day ?? 0,
                0
            )

            return days == 0 ? "Today" : "\(days)d"
        }

        let days = max(
            Calendar.current.dateComponents(
                [.day],
                from: Date(),
                to: challenge.endsAt
            ).day ?? 0,
            0
        )

        return days == 0 ? "Today" : "\(days)d"
    }

    private func timeRemaining(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        if challenge.startsAt > Date() {
            return "Starts " +
                challenge.startsAt.formatted(
                    .dateTime.month(.abbreviated).day()
                )
        }

        let days = max(
            Calendar.current.dateComponents(
                [.day],
                from: Date(),
                to: challenge.endsAt
            ).day ?? 0,
            0
        )

        return days == 0
            ? "Ends today"
            : "\(days) day\(days == 1 ? "" : "s") left"
    }

    private func dateRangeText(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        let start = challenge.startsAt.formatted(
            .dateTime.month(.abbreviated).day()
        )
        let end = challenge.endsAt.formatted(
            .dateTime.month(.abbreviated).day()
        )

        return "\(start) – \(end)"
    }

    private func compactTargetText(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        switch challenge.kind {
        case .distance:
            return String(format: "%.0f km", challenge.targetValue)
        case .sessions:
            return "\(Int(challenge.targetValue.rounded()))×"
        case .minutes:
            return "\(Int(challenge.targetValue.rounded())) min"
        case .streak:
            return "\(Int(challenge.targetValue.rounded())) days"
        }
    }

    private func rankText(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        guard store.isJoined(challenge.id) else {
            return "—"
        }

        guard let rank = store.rank(for: challenge.id) else {
            return "—"
        }

        return "#\(rank)"
    }

    private func participantLabel(
        _ participant: OfficialWeeklyChallengeParticipant,
        rank: Int,
        challenge: OfficialWeeklyChallenge
    ) -> String {
        if let currentRank = store.rank(for: challenge.id),
           currentRank == rank {
            return "You"
        }

        return "Participant \(rank)"
    }

    private func leaderboardProgressText(
        _ participant: OfficialWeeklyChallengeParticipant,
        challenge: OfficialWeeklyChallenge
    ) -> String {
        let value = participant.completionValue ?? 0

        switch challenge.kind {
        case .distance:
            return String(format: "%.1f km", value)
        case .sessions:
            return "\(Int(value.rounded(.down))) workouts"
        case .minutes:
            return "\(Int(value.rounded(.down))) min"
        case .streak:
            return "\(Int(value.rounded(.down))) days"
        }
    }

    private func challengeFocusTitle(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        switch challenge.kind {
        case .distance:
            return "Build distance, one session at a time"
        case .sessions:
            return "Consistency wins the week"
        case .minutes:
            return "Make time for movement"
        case .streak:
            return "Keep the streak alive"
        }
    }

    private func challengeFocusDescription(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        switch challenge.kind {
        case .distance:
            return "Every qualifying run and walk moves you toward the weekly target. Pace it your way and let ATHLTH track the total."
        case .sessions:
            return "Stack qualifying workouts across the challenge window and build a repeatable training rhythm."
        case .minutes:
            return "Your qualifying training minutes add up automatically throughout the week."
        case .streak:
            return "Complete qualifying activity on separate days and keep your momentum moving forward."
        }
    }

    private func ruleDescription(
        for challenge: OfficialWeeklyChallenge
    ) -> String {
        switch challenge.kind {
        case .distance:
            return "Registered running and walking distance inside the challenge window counts toward the target."
        case .sessions:
            return "Qualifying registered workouts inside the challenge window count toward the session target."
        case .minutes:
            return "Qualifying workout minutes inside the challenge window count toward the target."
        case .streak:
            return "Complete qualifying activity on separate days to build the required streak."
        }
    }
}

private struct OfficialWeeklyChallengeCompactStat: View {
    let icon: String
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
            }
            .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.70),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }
}

private struct OfficialWeeklyChallengeInsightTile: View {
    let eyebrow: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 24, alignment: .topLeading)
        }
        .padding(11)
        .frame(
            maxWidth: .infinity,
            minHeight: 92,
            alignment: .topLeading
        )
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.68), lineWidth: 0.7)
        }
    }
}

private struct OfficialWeeklyChallengeStatTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)
        }
        .padding(13)
        .frame(
            maxWidth: .infinity,
            minHeight: 126,
            alignment: .topLeading
        )
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.76),
                    ATHLTHTheme.surfaceStone.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.58),
                lineWidth: 0.7
            )
        }
    }
}

private struct OfficialWeeklyCountedWorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(
                systemName:
                    workout.activity == .walking
                        ? "figure.walk"
                        : "figure.run"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(
                workout.activity == .walking
                    ? Color.green
                    : ATHLTHTheme.accent
            )
            .frame(width: 34, height: 34)
            .background(
                (
                    workout.activity == .walking
                        ? Color.green
                        : ATHLTHTheme.accent
                )
                .opacity(0.09),
                in: RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    workout.activity == .walking
                        ? "Walk"
                        : "Run"
                )
                .font(.subheadline.weight(.semibold))

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let distance = workout.distanceMeters,
                   distance > 0 {
                    Text(
                        String(
                            format: "%.2f km",
                            distance / 1_000
                        )
                    )
                    .font(.subheadline.bold())
                }

                Text(durationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
    }

    private var durationText: String {
        let minutes = max(
            Int((workout.duration / 60).rounded()),
            0
        )

        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }

        return "\(minutes) min"
    }
}

struct OfficialWeeklyChallengeAdminListView: View {
    @EnvironmentObject private var store: OfficialWeeklyChallengeStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var editorSeed: OfficialWeeklyChallengeEditorSeed?
    @State private var challengeToDelete: OfficialWeeklyChallenge?
    @State private var isWorking = false

    var body: some View {
        Group {
            if session.currentRole.canAccessControlCenter {
                List {
                    if let active = store.activeChallenge {
                        Section("Current") {
                            adminRow(active)
                        }
                    }

                    Section("Upcoming") {
                        if store.upcomingChallenges.isEmpty {
                            ContentUnavailableView(
                                "Nothing scheduled",
                                systemImage: "calendar.badge.plus",
                                description: Text(
                                    "Create or generate the next weekly running challenge."
                                )
                            )
                        } else {
                            ForEach(store.upcomingChallenges) { challenge in
                                adminRow(challenge)
                            }
                        }
                    }
                }
                .navigationTitle("Weekly Challenges")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                editorSeed = .blank(window: store.nextAvailableWindow())
                            } label: {
                                Label(
                                    "Build from scratch",
                                    systemImage: "square.and.pencil"
                                )
                            }

                            Button {
                                generateNextChallenge()
                            } label: {
                                Label(
                                    "Generate with AI",
                                    systemImage: "sparkles"
                                )
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .overlay {
                    if isWorking || store.isGeneratingAI || store.isGeneratingCover {
                        ZStack {
                            Color.black.opacity(0.08)
                                .ignoresSafeArea()

                            ProgressView(
                                store.isGeneratingCover
                                    ? "Generating cover…"
                                    : (
                                        store.isGeneratingAI
                                            ? "Generating challenge…"
                                            : "Updating schedule…"
                                    )
                            )
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .sheet(item: $editorSeed) { seed in
                    NavigationStack {
                        OfficialWeeklyChallengeEditorView(seed: seed)
                    }
                }
                .confirmationDialog(
                    "Delete \(challengeToDelete?.title ?? "challenge")?",
                    isPresented: Binding(
                        get: { challengeToDelete != nil },
                        set: { shown in
                            if !shown { challengeToDelete = nil }
                        }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete & build replacement") {
                        deleteAndBuildReplacement()
                    }

                    Button("Delete & generate replacement with AI") {
                        deleteAndGenerateReplacement()
                    }

                    Button("Delete & move future challenges forward") {
                        deleteAndShiftForward()
                    }

                    Button("Delete and leave gap", role: .destructive) {
                        deleteOnly()
                    }

                    Button("Cancel", role: .cancel) {
                        challengeToDelete = nil
                    }
                } message: {
                    Text(
                        "Choose what should happen to this weekly slot after the challenge is deleted."
                    )
                }
                .task {
                    await store.refresh()
                }
            } else {
                ContentUnavailableView(
                    "Admin access required",
                    systemImage: "lock.shield",
                    description: Text(
                        "Only ATHLTH administrators can manage official weekly challenges."
                    )
                )
            }
        }
    }

    private func adminRow(
        _ challenge: OfficialWeeklyChallenge
    ) -> some View {
        Button {
            editorSeed = .existing(challenge)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: challenge.kind.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 40, height: 40)
                    .background(
                        Color.orange.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(challenge.title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        "\(challenge.kind.targetText(challenge.targetValue)) · " +
                        challenge.startsAt.formatted(
                            .dateTime.month(.abbreviated).day()
                        ) +
                        "–" +
                        challenge.endsAt.formatted(
                            .dateTime.month(.abbreviated).day()
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(challenge.source.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            challenge.source == "ai"
                                ? Color.purple
                                : ATHLTHTheme.mutedText
                        )

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button {
                Task {
                    _ = await store.generateCover(
                        for: challenge.id
                    )
                }
            } label: {
                Label("AI Cover", systemImage: "photo.badge.plus")
            }
            .tint(.purple)

            Button(role: .destructive) {
                challengeToDelete = challenge
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func generateNextChallenge() {
        let window = store.nextAvailableWindow()

        Task {
            if let draft = await store.generateAI(
                startsAt: window.0,
                endsAt: window.1
            ) {
                editorSeed = .ai(
                    draft: draft,
                    startsAt: window.0,
                    endsAt: window.1
                )
            }
        }
    }

    private func deleteOnly() {
        guard let challenge = challengeToDelete else { return }
        challengeToDelete = nil
        isWorking = true

        Task {
            _ = await store.delete(challenge)
            isWorking = false
        }
    }

    private func deleteAndBuildReplacement() {
        guard let challenge = challengeToDelete else { return }
        challengeToDelete = nil
        isWorking = true

        Task {
            if await store.delete(challenge) {
                editorSeed = .blank(
                    window: (
                        challenge.startsAt,
                        challenge.endsAt
                    )
                )
            }
            isWorking = false
        }
    }

    private func deleteAndGenerateReplacement() {
        guard let challenge = challengeToDelete else { return }
        challengeToDelete = nil
        isWorking = true

        Task {
            if let draft = await store.generateAI(
                startsAt: challenge.startsAt,
                endsAt: challenge.endsAt
            ),
            await store.delete(challenge) {
                editorSeed = .ai(
                    draft: draft,
                    startsAt: challenge.startsAt,
                    endsAt: challenge.endsAt
                )
            }
            isWorking = false
        }
    }

    private func deleteAndShiftForward() {
        guard let challenge = challengeToDelete else { return }
        challengeToDelete = nil
        isWorking = true

        Task {
            if await store.delete(challenge) {
                _ = await store.shiftFutureChallengesForward(
                    after: challenge.startsAt
                )
            }
            isWorking = false
        }
    }
}

struct OfficialWeeklyChallengeEditorSeed: Identifiable {
    let id = UUID()
    let existing: OfficialWeeklyChallenge?
    let title: String
    let subtitle: String
    let kind: OfficialRunningChallengeKind
    let targetValue: Double
    let startsAt: Date
    let endsAt: Date
    let source: String

    static func existing(
        _ challenge: OfficialWeeklyChallenge
    ) -> Self {
        Self(
            existing: challenge,
            title: challenge.title,
            subtitle: challenge.subtitle,
            kind: challenge.kind,
            targetValue: challenge.targetValue,
            startsAt: challenge.startsAt,
            endsAt: challenge.endsAt,
            source: challenge.source
        )
    }

    static func blank(
        window: (Date, Date)
    ) -> Self {
        Self(
            existing: nil,
            title: "",
            subtitle: "",
            kind: .distance,
            targetValue: 25,
            startsAt: window.0,
            endsAt: window.1,
            source: "manual"
        )
    }

    static func ai(
        draft: OfficialWeeklyChallengeAIDraft,
        startsAt: Date,
        endsAt: Date
    ) -> Self {
        Self(
            existing: nil,
            title: draft.title,
            subtitle: draft.subtitle,
            kind: draft.kind,
            targetValue: draft.targetValue,
            startsAt: startsAt,
            endsAt: endsAt,
            source: "ai"
        )
    }
}

struct OfficialWeeklyChallengeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: OfficialWeeklyChallengeStore

    let seed: OfficialWeeklyChallengeEditorSeed

    @State private var title: String
    @State private var subtitle: String
    @State private var kind: OfficialRunningChallengeKind
    @State private var targetValue: Double
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var source: String
    @State private var saving = false

    init(seed: OfficialWeeklyChallengeEditorSeed) {
        self.seed = seed
        _title = State(initialValue: seed.title)
        _subtitle = State(initialValue: seed.subtitle)
        _kind = State(initialValue: seed.kind)
        _targetValue = State(initialValue: seed.targetValue)
        _startsAt = State(initialValue: seed.startsAt)
        _endsAt = State(initialValue: seed.endsAt)
        _source = State(initialValue: seed.source)
    }

    var body: some View {
        Form {
            Section("Challenge") {
                TextField("Title", text: $title)

                TextField(
                    "Short description",
                    text: $subtitle,
                    axis: .vertical
                )
                .lineLimit(2...4)

                Picker("Challenge type", selection: $kind) {
                    ForEach(OfficialRunningChallengeKind.allCases) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                }

                LabeledContent(kind.targetLabel) {
                    TextField(
                        "Target",
                        value: $targetValue,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
            }

            Section("Schedule") {
                DatePicker(
                    "Starts",
                    selection: $startsAt
                )

                DatePicker(
                    "Ends",
                    selection: $endsAt
                )
            }

            Section {
                Button {
                    regenerateWithAI()
                } label: {
                    Label(
                        "Generate a new AI suggestion",
                        systemImage: "sparkles"
                    )
                }
                .disabled(store.isGeneratingAI)

                if let existing = seed.existing {
                    Button {
                        Task {
                            _ = await store.generateCover(
                                for: existing.id
                            )
                        }
                    } label: {
                        Label(
                            "Generate AI cover",
                            systemImage: "photo.badge.plus"
                        )
                    }
                    .disabled(store.isGeneratingCover)
                }
            } footer: {
                Text(
                    "AI can draft the challenge and create its cover image. The challenge text is not published until you review and save it."
                )
            }

            if let error = store.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(
            seed.existing == nil
                ? "New Weekly Challenge"
                : "Edit Challenge"
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
                    save()
                }
                .disabled(
                    saving ||
                    title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    targetValue <= 0 ||
                    endsAt <= startsAt
                )
            }
        }
        .overlay {
            if saving || store.isGeneratingAI || store.isGeneratingCover {
                ProgressView(
                    store.isGeneratingCover
                        ? "Generating cover…"
                        : (
                            store.isGeneratingAI
                                ? "Generating…"
                                : "Saving…"
                        )
                )
                .padding(18)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
            }
        }
    }

    private func save() {
        saving = true

        Task {
            let success = await store.save(
                existing: seed.existing,
                title: title,
                subtitle: subtitle,
                kind: kind,
                targetValue: targetValue,
                startsAt: startsAt,
                endsAt: endsAt,
                source: source
            )

            saving = false

            if success {
                dismiss()
            }
        }
    }

    private func regenerateWithAI() {
        Task {
            if let draft = await store.generateAI(
                startsAt: startsAt,
                endsAt: endsAt
            ) {
                title = draft.title
                subtitle = draft.subtitle
                kind = draft.kind
                targetValue = draft.targetValue
                source = "ai"
            }
        }
    }
}


private struct OfficialChallengeAvatar: View {
    let url: URL?
    let fallback: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(ATHLTHTheme.accentSoft)

            Text(initials)
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
        }
    }

    private var initials: String {
        let words = fallback
            .split(separator: " ")
            .prefix(2)

        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "A" : value.uppercased()
    }
}
