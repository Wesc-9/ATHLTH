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
        case .sessions: return "Runs"
        case .minutes: return "Running time"
        case .streak: return "Running days"
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
            return "\(Int(target.rounded())) runs"
        case .minutes:
            return "\(Int(target.rounded())) min"
        case .streak:
            return "\(Int(target.rounded())) days"
        }
    }

    var targetLabel: String {
        switch self {
        case .distance: return "Target distance (km)"
        case .sessions: return "Number of runs"
        case .minutes: return "Running minutes"
        case .streak: return "Running days"
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
    var createdBy: UUID
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

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case joinedAt = "joined_at"
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

@MainActor
final class OfficialWeeklyChallengeStore: ObservableObject {
    @Published private(set) var challenges: [OfficialWeeklyChallenge] = []
    @Published private(set) var participants: [OfficialWeeklyChallengeParticipant] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isGeneratingAI = false
    @Published var errorMessage: String?

    private let client: SupabaseClient

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

    func refresh() async {
        guard client.auth.currentUser != nil else {
            challenges = []
            participants = []
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

    func participantIDs(for challengeID: UUID) -> [UUID] {
        participants
            .filter { $0.challengeID == challengeID }
            .sorted { $0.joinedAt < $1.joinedAt }
            .map(\.userID)
    }

    func isJoined(_ challengeID: UUID) -> Bool {
        guard let userID = client.auth.currentUser?.id else { return false }

        return participants.contains {
            $0.challengeID == challengeID &&
            $0.userID == userID
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

            await refresh()
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

            await refresh()
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
        let write = OfficialWeeklyChallengeWrite(
            id: existing?.id ?? UUID(),
            title: cleanTitle,
            subtitle: cleanSubtitle,
            kind: kind.rawValue,
            targetValue: targetValue,
            startsAt: startsAt,
            endsAt: endsAt,
            heroAsset: existing?.heroAsset ?? "CommunityHero",
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

            await refresh()
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

            await refresh()
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

            await refresh()
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
        let runs = workouts.filter {
            $0.activity == .running &&
            $0.startDate >= challenge.startsAt &&
            $0.startDate < challenge.endsAt
        }

        switch challenge.kind {
        case .distance:
            return runs
                .compactMap(\.distanceMeters)
                .reduce(0, +) / 1_000

        case .sessions:
            return Double(runs.count)

        case .minutes:
            return runs.reduce(0) {
                $0 + ($1.duration / 60)
            }

        case .streak:
            return Double(longestRunningStreak(runs))
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
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) runs"

        case .minutes:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) min"

        case .streak:
            return "\(Int(value.rounded(.down))) / \(Int(challenge.targetValue.rounded())) days"
        }
    }

    private static func longestRunningStreak(
        _ runs: [WorkoutSummary]
    ) -> Int {
        guard !runs.isEmpty else { return 0 }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current

        let days = Array(
            Set(runs.map { calendar.startOfDay(for: $0.startDate) })
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

struct OfficialWeeklyChallengeCard: View {
    @EnvironmentObject private var store: OfficialWeeklyChallengeStore
    @EnvironmentObject private var health: HealthKitManager

    let challenge: OfficialWeeklyChallenge
    let profiles: [SocialProfileCard]

    private var joined: Bool {
        store.isJoined(challenge.id)
    }

    private var progress: Double {
        OfficialWeeklyChallengeProgress.fraction(
            challenge: challenge,
            workouts: health.workouts
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(challenge.heroAsset)
                .resizable()
                .interpolation(.high)
                .scaledToFill()

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
                        .font(.system(size: 29, weight: .bold))
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
                        Button {
                            Task {
                                await store.join(challenge)
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
            .padding(16)

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    progressRing
                        .padding(.trailing, 16)
                        .padding(.bottom, 72)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 270)
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

    var body: some View {
        Group {
            if let challenge {
                ScrollView {
                    VStack(spacing: 18) {
                        Image(challenge.heroAsset)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipped()
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 24,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 10) {
                            Text(challenge.title)
                                .font(.largeTitle.bold())

                            Text(challenge.subtitle)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            Label(
                                challenge.kind.targetText(
                                    challenge.targetValue
                                ),
                                systemImage: challenge.kind.icon
                            )
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ATHLTHCard {
                            Text("Your progress")
                                .font(.headline)

                            ProgressView(
                                value: OfficialWeeklyChallengeProgress.fraction(
                                    challenge: challenge,
                                    workouts: health.workouts
                                )
                            )
                            .tint(ATHLTHTheme.vitality)

                            Text(
                                OfficialWeeklyChallengeProgress.valueText(
                                    challenge: challenge,
                                    workouts: health.workouts
                                )
                            )
                            .font(.title3.bold())

                            Text("\(store.participantCount(for: challenge.id)) people have joined")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task {
                                if store.isJoined(challenge.id) {
                                    await store.leave(challenge)
                                } else {
                                    await store.join(challenge)
                                }
                            }
                        } label: {
                            Text(
                                store.isJoined(challenge.id)
                                    ? "Leave Challenge"
                                    : "Join Challenge"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(
                            store.isJoined(challenge.id)
                                ? .secondary
                                : ATHLTHTheme.accent
                        )
                    }
                    .padding(16)
                }
                .navigationTitle("Weekly Challenge")
                .navigationBarTitleDisplayMode(.inline)
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
                    if isWorking || store.isGeneratingAI {
                        ZStack {
                            Color.black.opacity(0.08)
                                .ignoresSafeArea()

                            ProgressView(
                                store.isGeneratingAI
                                    ? "Generating challenge…"
                                    : "Updating schedule…"
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
            if await store.delete(challenge),
               let draft = await store.generateAI(
                    startsAt: challenge.startsAt,
                    endsAt: challenge.endsAt
               ) {
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
            } footer: {
                Text(
                    "AI only drafts the challenge. Nothing becomes public until you review and save it."
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
            if saving || store.isGeneratingAI {
                ProgressView(
                    store.isGeneratingAI
                        ? "Generating…"
                        : "Saving…"
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
