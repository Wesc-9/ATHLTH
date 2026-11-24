import SwiftUI
import Supabase

struct SocialWorkoutProgress: Codable, Hashable {
    let completed: Int
    let total: Int
    var fraction: Double { total > 0 ? Double(min(max(completed, 0), total)) / Double(total) : 0 }

    static func counted<ID: Hashable>(planned: [ID], completed: Set<ID>) -> Self? {
        let unique = Set(planned)
        guard !unique.isEmpty else { return nil }
        return Self(completed: unique.intersection(completed).count, total: unique.count)
    }

    static func strength(_ exercises: [SocialWorkoutLiveExerciseSnapshot]) -> Self? {
        guard !exercises.isEmpty else { return nil }
        return Self(completed: exercises.filter { !$0.sets.isEmpty && $0.sets.allSatisfy(\.completed) }.count,
                    total: exercises.count)
    }
}

struct TrainTogetherStatusStrip: View {
    @EnvironmentObject private var social: SocialStore
    @StateObject private var companion = SocialWorkoutCompanionStore()
    @State private var showingCompanion = false
    @State private var showingChat = false
    @State private var sharedSourceID: UUID?
    @State private var chatLookupComplete = false
    @State private var sharedRoomWithdrawn = false
    @Environment(\.scenePhase) private var scenePhase

    private var sessionID: UUID? { social.recordingWorkoutSessionID }
    private var participants: [SocialWorkoutParticipantRecord] {
        guard let sessionID else { return [] }
        return social.workoutParticipants.filter {
            $0.sessionID == sessionID && ($0.state == .creator || $0.state == .accepted)
        }.sorted { lhs, rhs in
            if lhs.userID == social.currentUserID { return rhs.userID != lhs.userID }
            if rhs.userID == social.currentUserID { return false }
            return lhs.displayNameSnapshot.localizedCaseInsensitiveCompare(rhs.displayNameSnapshot) == .orderedAscending
        }
    }
    private var partner: SocialWorkoutParticipantRecord? {
        participants.first { $0.userID != social.currentUserID }
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
    private func progress(_ person: SocialWorkoutParticipantRecord) -> SocialWorkoutProgress? {
        guard let state = companion.liveStates.first(where: { $0.userID == person.userID }) else { return nil }
        return state.payload.progress ?? state.payload.exercises.flatMap(SocialWorkoutProgress.strength)
    }
    private func avatar(_ person: SocialWorkoutParticipantRecord, size: CGFloat) -> some View {
        Group {
            if let profile = social.profile(for: person.userID), profile.avatarURL != nil {
                SocialAvatar(profile: profile, size: size)
            } else {
                Text(person.displayNameSnapshot.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased())
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: size, height: size)
                    .background(ATHLTHTrainTogetherDesign.accentSoft, in: Circle())
            }
        }
        .overlay { Circle().strokeBorder(person.userID == social.currentUserID ? ATHLTHTheme.accentDeep : Color.secondary.opacity(0.5), lineWidth: 1.5) }
        .accessibilityLabel(person.displayNameSnapshot)
    }

    var body: some View {
        if let sessionID, let partner, participants.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(tr("Training together", "Trener sammen"), systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(ATHLTHTheme.accentDeep)
                    Spacer()
                    Button { showingCompanion = true } label: {
                        Label(tr("Overview", "Oversikt"), systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.medium))
                    }.buttonStyle(.plain)
                    Button { showingChat = true } label: {
                        avatar(partner, size: 34)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "bubble.left.fill").font(.system(size: 9))
                                    .foregroundStyle(.white).padding(3)
                                    .background(ATHLTHTheme.accentDeep, in: Circle())
                            }
                    }.buttonStyle(.plain).accessibilityLabel(tr("Open chat", "Åpne chat"))
                }
                if let total = participants.compactMap({ progress($0)?.total }).max(), total > 0 {
                    GeometryReader { geometry in
                        let width = max(0, geometry.size.width - 32)
                        ZStack(alignment: .topLeading) {
                            Capsule().fill(Color.secondary.opacity(0.19))
                                .frame(width: width, height: 3).offset(x: 16, y: 12)
                            ForEach(0...min(total, 40), id: \.self) { i in
                                Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 1, height: 8)
                                    .offset(x: 16 + width * CGFloat(i) / CGFloat(min(total, 40)), y: 10)
                            }
                            ForEach(Array(participants.enumerated()), id: \.element.id) { index, person in
                                if let p = progress(person) {
                                    Button {
                                        if person.userID == social.currentUserID { showingCompanion = true }
                                        else { showingChat = true }
                                    } label: { avatar(person, size: 28) }
                                    .buttonStyle(.plain)
                                    .offset(x: 2 + width * CGFloat(p.fraction), y: CGFloat(index) * 25)
                                    .accessibilityLabel("\(person.displayNameSnapshot), \(p.completed)/\(p.total)")
                                }
                            }
                        }
                    }.frame(height: max(54, CGFloat(participants.count) * 25 + 4))
                    HStack {
                        Text(tr("Start", "Start"))
                        Spacer()
                        Text(tr("Finish", "Mål"))
                    }.font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(participants) { person in
                    HStack(spacing: 6) {
                        Text(person.userID == social.currentUserID ? tr("You", "Du") : person.displayNameSnapshot)
                            .font(.caption2.weight(.semibold)).lineLimit(1)
                        Spacer()
                        if let p = progress(person) {
                            Text("\(p.completed)/\(p.total) " + tr("completed", "fullført"))
                                .font(.caption2.monospacedDigit())
                        } else if let state = companion.liveStates.first(where: { $0.userID == person.userID }),
                                  let elapsed = state.payload.elapsedSeconds, elapsed.isFinite {
                            Text("\(Int(max(0, elapsed) / 60)) min" + (state.payload.distanceMeters.map { String(format: " · %.2f km", $0 / 1000) } ?? ""))
                                .font(.caption2.monospacedDigit())
                        } else { Text(statusText(person)).font(.caption2) }
                        if let state = companion.liveStates.first(where: { $0.userID == person.userID }),
                           Date().timeIntervalSince(state.updatedAt) > 20, person.workoutFinishedAt == nil {
                            Image(systemName: "clock.badge.exclamationmark").font(.caption2)
                                .accessibilityLabel(tr("Last known progress", "Sist kjente fremdrift"))
                        }
                    }.foregroundStyle(.secondary)
                }
            }
            .padding(11)
            .athlthTrainTogetherCard(radius: 16, subtle: true)
            .task(id: sessionID) {
                sharedSourceID = nil
                chatLookupComplete = false
                sharedRoomWithdrawn = false
                while !Task.isCancelled {
                    if scenePhase == .active {
                        try? await social.refreshWorkoutLobby(sessionID: sessionID)
                        await companion.refresh(sessionID: sessionID)
                        if !chatLookupComplete,
                           let active = social.workoutSessions.first(where: { $0.id == sessionID }) {
                            if let source = active.invitePayload?.workout.id {
                                let draft = TrainTogetherLiveDraftStore()
                                await draft.refresh(source)
                                if draft.isWithdrawn(source) {
                                    sharedRoomWithdrawn = true
                                    chatLookupComplete = true
                                } else if draft.errorMessage == nil {
                                    if draft.draft != nil { sharedSourceID = source }
                                    chatLookupComplete = true
                                }
                            } else { chatLookupComplete = true }
                        }
                    }
                    do { try await Task.sleep(for: .seconds(3)) } catch { break }
                }
            }
            .sheet(isPresented: $showingCompanion) {
                SocialWorkoutCompanionSheet(sessionID: sessionID, progressOnly: true)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingChat) {
                if let source = sharedSourceID, let userID = social.currentUserID {
                    ScrollView {
                        TrainTogetherRoomChat(sourceID: source, userID: userID,
                            partnerName: partner.displayNameSnapshot, canSend: true)
                            .padding(16)
                    }
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                } else if !chatLookupComplete || sharedRoomWithdrawn {
                    VStack(spacing: 12) {
                        if !chatLookupComplete { ProgressView() }
                        Text(sharedRoomWithdrawn ? tr("Shared chat is no longer available.", "Felleschatten er ikke lenger tilgjengelig.")
                             : tr("Finding the shared chat…", "Henter felleschatten…"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .presentationDetents([.medium]).presentationDragIndicator(.visible)
                } else {
                    SocialWorkoutCompanionSheet(sessionID: sessionID, chatOnly: true)
                        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func statusText(
        _ participant:
            SocialWorkoutParticipantRecord
    ) -> String {
        if participant.launchFailedAt != nil {
            return ATHLTHLocalization.choose(
                english: "Couldn’t start",
                norwegian: "Kunne ikke starte"
            )
        }

        if participant.workoutFinishedAt != nil {
            return ATHLTHLocalization.choose(
                english: "Finished",
                norwegian: "Ferdig"
            )
        }

        if participant.workoutStartedAt != nil {
            return ATHLTHLocalization.choose(
                english: "Training",
                norwegian: "Trener"
            )
        }

        if participant.readyAt != nil {
            return ATHLTHLocalization.choose(
                english: "Ready",
                norwegian: "Klar"
            )
        }

        if participant.state == .accepted {
            return ATHLTHLocalization.choose(
                english: "Accepted",
                norwegian: "Godtatt"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Invited",
            norwegian: "Invitert"
        )
    }

    private func statusColor(
        _ participant:
            SocialWorkoutParticipantRecord
    ) -> Color {
        if participant.launchFailedAt != nil {
            return .red
        }
        if participant.workoutFinishedAt != nil {
            return .secondary
        }
        if participant.workoutStartedAt != nil {
            return ATHLTHTheme.accent
        }
        if participant.readyAt != nil {
            return .green
        }
        return .orange
    }
}


struct SocialWorkoutLiveSetSnapshot:
    Codable,
    Hashable
{
    let number: Int
    let reps: Int?
    let weightKilograms: Double?
    let completed: Bool
}

struct SocialWorkoutLiveExerciseSnapshot:
    Codable,
    Hashable
{
    let name: String
    let exerciseIndex: Int
    let current: Bool
    let sets:
        [SocialWorkoutLiveSetSnapshot]
}

struct SocialWorkoutProgressItem: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let completed: Bool
    let current: Bool
}

struct SocialWorkoutLivePayload:
    Codable,
    Hashable
{
    var currentTitle: String?
    var progress: SocialWorkoutProgress? = nil
    var progressItems: [SocialWorkoutProgressItem]? = nil
    var exerciseIndex: Int?
    var exerciseCount: Int?
    var currentSetNumber: Int?
    var currentSetCount: Int?
    var isResting: Bool?
    var distanceMeters: Double?
    var elapsedSeconds: Double?
    var paceSecondsPerKilometer:
        Double?
    var exercises:
        [SocialWorkoutLiveExerciseSnapshot]?
}

struct SocialWorkoutLiveStateRecord:
    Codable,
    Hashable,
    Identifiable
{
    var id: String {
        sessionID.uuidString +
            ":" +
            userID.uuidString
    }

    let sessionID: UUID
    let userID: UUID
    let displayNameSnapshot: String
    let workoutKind: String
    let payload:
        SocialWorkoutLivePayload
    let updatedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case sessionID = "session_id"
        case userID = "user_id"
        case displayNameSnapshot =
            "display_name_snapshot"
        case workoutKind =
            "workout_kind"
        case payload
        case updatedAt =
            "updated_at"
    }
}

struct SocialWorkoutMessageRecord:
    Codable,
    Hashable,
    Identifiable
{
    let id: UUID
    let sessionID: UUID
    let senderID: UUID
    let senderDisplayName: String
    let kind: String
    let body: String?
    let createdAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case sessionID = "session_id"
        case senderID = "sender_id"
        case senderDisplayName =
            "sender_display_name"
        case kind
        case body
        case createdAt =
            "created_at"
    }
}

private struct SocialWorkoutLiveStateWrite:
    Encodable
{
    let sessionID: UUID
    let userID: UUID
    let displayNameSnapshot: String
    let workoutKind: String
    let payload:
        SocialWorkoutLivePayload
    let updatedAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case sessionID = "session_id"
        case userID = "user_id"
        case displayNameSnapshot =
            "display_name_snapshot"
        case workoutKind =
            "workout_kind"
        case payload
        case updatedAt =
            "updated_at"
    }
}

private struct SocialWorkoutMessageWrite:
    Encodable
{
    let id: UUID
    let sessionID: UUID
    let senderID: UUID
    let senderDisplayName: String
    let kind: String
    let body: String?
    let createdAt: Date

    enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case sessionID = "session_id"
        case senderID = "sender_id"
        case senderDisplayName =
            "sender_display_name"
        case kind
        case body
        case createdAt =
            "created_at"
    }
}

@MainActor
final class SocialWorkoutCompanionStore:
    ObservableObject
{
    @Published private(set) var liveStates:
        [SocialWorkoutLiveStateRecord] = []
    @Published private(set) var messages:
        [SocialWorkoutMessageRecord] = []
    @Published private(set) var isRefreshing =
        false
    @Published var errorMessage: String?

    private let client =
        SupabaseEnvironment.client

    func refresh(
        sessionID: UUID
    ) async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            async let states:
                [SocialWorkoutLiveStateRecord] =
                client
                    .from(
                        "social_workout_live_states"
                    )
                    .select()
                    .eq(
                        "session_id",
                        value:
                            sessionID
                    )
                    .order(
                        "updated_at",
                        ascending: false
                    )
                    .limit(12)
                    .execute()
                    .value

            async let chat:
                [SocialWorkoutMessageRecord] =
                client
                    .from(
                        "social_workout_messages"
                    )
                    .select()
                    .eq(
                        "session_id",
                        value:
                            sessionID
                    )
                    .order(
                        "created_at",
                        ascending: true
                    )
                    .limit(100)
                    .execute()
                    .value

            let loaded =
                try await (
                    states,
                    chat
                )
            liveStates = loaded.0
            messages = loaded.1
            errorMessage = nil
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    func publishStrength(
        sessionID: UUID,
        userID: UUID,
        displayName: String,
        workout: StrengthWorkoutLog,
        currentExerciseIndex: Int,
        currentSetIndex: Int,
        isResting: Bool
    ) async {
        let exercises =
            workout
                .exercises
                .enumerated()
                .map {
                    index,
                    exercise in

                    SocialWorkoutLiveExerciseSnapshot(
                        name:
                            exercise
                                .exercise
                                .name,
                        exerciseIndex:
                            index,
                        current:
                            index ==
                            currentExerciseIndex,
                        sets:
                            exercise
                                .sets
                                .map {
                                    set in
                                    SocialWorkoutLiveSetSnapshot(
                                        number:
                                            set.setNumber,
                                        reps:
                                            set.completedReps,
                                        weightKilograms:
                                            set.completedWeightKilograms,
                                        completed:
                                            set.isCompleted
                                    )
                                }
                    )
                }

        let currentExercise =
            workout.exercises.indices
                .contains(
                    currentExerciseIndex
                )
                ? workout.exercises[
                    currentExerciseIndex
                ]
                : nil
        let currentSet =
            currentExercise?
                .sets
                .indices
                .contains(
                    currentSetIndex
                ) == true
                ? currentExercise?
                    .sets[
                        currentSetIndex
                    ]
                : nil

        await upsert(
            sessionID:
                sessionID,
            userID:
                userID,
            displayName:
                displayName,
            workoutKind:
                WorkoutKind
                    .strength
                    .rawValue,
            payload:
                SocialWorkoutLivePayload(
                    currentTitle:
                        currentExercise?
                            .exercise
                            .name,
                    progress: SocialWorkoutProgress.strength(exercises),
                    exerciseIndex:
                        currentExerciseIndex,
                    exerciseCount:
                        workout
                            .exercises
                            .count,
                    currentSetNumber:
                        currentSet?
                            .setNumber,
                    currentSetCount:
                        currentExercise?
                            .sets
                            .count,
                    isResting:
                        isResting,
                    distanceMeters:
                        nil,
                    elapsedSeconds:
                        max(
                            Date()
                                .timeIntervalSince(
                                    workout
                                        .startedAt
                                ),
                            0
                        ),
                    paceSecondsPerKilometer:
                        nil,
                    exercises:
                        exercises
                )
        )
    }

    func publishCardio(
        sessionID: UUID,
        userID: UUID,
        displayName: String,
        walking: Bool,
        title: String?,
        distanceMeters: Double,
        elapsedSeconds:
            TimeInterval,
        paceSecondsPerKilometer:
            TimeInterval?,
        progress: SocialWorkoutProgress? = nil,
        progressItems: [SocialWorkoutProgressItem]? = nil
    ) async {
        await upsert(
            sessionID:
                sessionID,
            userID:
                userID,
            displayName:
                displayName,
            workoutKind:
                walking
                    ? WorkoutKind
                        .walking
                        .rawValue
                    : WorkoutKind
                        .running
                        .rawValue,
            payload:
                SocialWorkoutLivePayload(
                    currentTitle:
                        title ??
                        (
                            walking
                                ? WorkoutKind
                                    .walking
                                    .title
                                : WorkoutKind
                                    .running
                                    .title
                        ),
                    progress: progress,
                    progressItems: progressItems,
                    exerciseIndex:
                        nil,
                    exerciseCount:
                        nil,
                    currentSetNumber:
                        nil,
                    currentSetCount:
                        nil,
                    isResting: nil,
                    distanceMeters:
                        distanceMeters,
                    elapsedSeconds:
                        elapsedSeconds,
                    paceSecondsPerKilometer:
                        paceSecondsPerKilometer,
                    exercises: nil
                )
        )
    }

    func publishProgress(sessionID: UUID, userID: UUID, displayName: String,
                         kind: String, title: String?, progress: SocialWorkoutProgress?,
                         elapsed: TimeInterval, distance: Double? = nil,
                         exercises: [SocialWorkoutLiveExerciseSnapshot]? = nil,
                         progressItems: [SocialWorkoutProgressItem]? = nil) async {
        await upsert(sessionID: sessionID, userID: userID, displayName: displayName,
                     workoutKind: kind, payload: SocialWorkoutLivePayload(
                        currentTitle: title, progress: progress, progressItems: progressItems,
                        exerciseIndex: nil, exerciseCount: progress?.total,
                        currentSetNumber: nil, currentSetCount: nil, isResting: nil,
                        distanceMeters: distance, elapsedSeconds: elapsed, paceSecondsPerKilometer: nil,
                        exercises: exercises))
    }

    func sendText(
        _ text: String,
        sessionID: UUID,
        senderID: UUID,
        displayName: String
    ) async {
        let clean =
            text.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard !clean.isEmpty else {
            return
        }

        await send(
            kind: "text",
            body:
                String(
                    clean.prefix(800)
                ),
            sessionID:
                sessionID,
            senderID:
                senderID,
            displayName:
                displayName
        )
    }

    func sendReaction(
        _ reaction: String,
        sessionID: UUID,
        senderID: UUID,
        displayName: String
    ) async {
        await send(
            kind: "reaction",
            body:
                String(
                    reaction.prefix(20)
                ),
            sessionID:
                sessionID,
            senderID:
                senderID,
            displayName:
                displayName
        )
    }

    func requestLocation(
        sessionID: UUID,
        senderID: UUID,
        displayName: String
    ) async {
        await send(
            kind:
                "location_request",
            body:
                ATHLTHLocalization.choose(
                    english:
                        "Requests your location for this workout.",
                    norwegian:
                        "Ber om posisjonen din for denne økten."
                ),
            sessionID:
                sessionID,
            senderID:
                senderID,
            displayName:
                displayName
        )
    }

    private func send(
        kind: String,
        body: String?,
        sessionID: UUID,
        senderID: UUID,
        displayName: String
    ) async {
        do {
            let write =
                SocialWorkoutMessageWrite(
                    id: UUID(),
                    sessionID:
                        sessionID,
                    senderID:
                        senderID,
                    senderDisplayName:
                        displayName,
                    kind: kind,
                    body: body,
                    createdAt:
                        Date()
                )

            try await client
                .from(
                    "social_workout_messages"
                )
                .insert(write)
                .execute()

            await refresh(
                sessionID:
                    sessionID
            )
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }

    private func upsert(
        sessionID: UUID,
        userID: UUID,
        displayName: String,
        workoutKind: String,
        payload:
            SocialWorkoutLivePayload
    ) async {
        do {
            let write =
                SocialWorkoutLiveStateWrite(
                    sessionID:
                        sessionID,
                    userID:
                        userID,
                    displayNameSnapshot:
                        displayName,
                    workoutKind:
                        workoutKind,
                    payload:
                        payload,
                    updatedAt:
                        Date()
                )

            try await client
                .from(
                    "social_workout_live_states"
                )
                .upsert(
                    write,
                    onConflict:
                        "session_id,user_id"
                )
                .execute()
        } catch {
            // Live social state is additive to workout recording.
            // A sync failure must never interrupt the workout itself.
        }
    }
}

private struct SocialWorkoutCompanionSheet:
    View
{
    @EnvironmentObject private var social:
        SocialStore
    @Environment(\.dismiss)
    private var dismiss

    @StateObject private var companion =
        SocialWorkoutCompanionStore()
    @State private var messageText = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    let sessionID: UUID
    var progressOnly = false
    var chatOnly = false

    private var ownParticipant:
        SocialWorkoutParticipantRecord? {
        guard let currentUserID =
                social.currentUserID
        else {
            return nil
        }

        return social
            .workoutParticipants
            .first {
                $0.sessionID ==
                    sessionID &&
                $0.userID ==
                    currentUserID
            }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
                ScrollView {
                    Group {
                        if wide && !chatOnly && !progressOnly {
                            HStack(alignment: .top, spacing: 16) {
                                liveProgressSection(wide: false)
                                    .frame(maxWidth: .infinity, alignment: .top)
                                chatSection
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }
                        } else {
                            VStack(spacing: 16) {
                                if !chatOnly { liveProgressSection(wide: wide) }
                                if !progressOnly { chatSection }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .background(ATHLTHTrainTogetherDesign.canvas.ignoresSafeArea())
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Training together",
                    norwegian:
                        "Trener sammen"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
        .task(id: sessionID) {
            while !Task.isCancelled {
                if scenePhase == .active {
                    await companion.refresh(sessionID: sessionID)
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }

    private func liveProgressSection(wide: Bool) -> some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "LIVE PROGRESS",
                        norwegian:
                            "LIVE FREMDRIFT"
                    ),
                    systemImage:
                        "waveform.path.ecg"
                )
                .font(
                    .caption.weight(.bold)
                )
                .tracking(0.9)
                .foregroundStyle(
                    ATHLTHTheme
                        .vitality
                )

                if companion
                    .liveStates
                    .isEmpty {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Partner progress appears here as each workout starts.",
                            norwegian:
                                "Fremdriften til partnerne vises her når øktene starter."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                } else {
                    let ordered = companion.liveStates.sorted { lhs, rhs in
                        if lhs.userID == social.currentUserID { return rhs.userID != lhs.userID }
                        if rhs.userID == social.currentUserID { return false }
                        return lhs.displayNameSnapshot.localizedCaseInsensitiveCompare(rhs.displayNameSnapshot) == .orderedAscending
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: wide ? 2 : 1), spacing: 12) {
                        ForEach(ordered) { state in
                            liveStateCard(state)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
        }
    }

    private func liveStateCard(
        _ state:
            SocialWorkoutLiveStateRecord
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            HStack {
                Text(
                    state
                        .displayNameSnapshot
                )
                .font(
                    .subheadline
                        .weight(.bold)
                )

                Spacer()

                Text(
                    state.updatedAt,
                    style: .relative
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }

            if let p = state.payload.progress ?? state.payload.exercises.flatMap(SocialWorkoutProgress.strength) {
                ProgressView(value: p.fraction).tint(ATHLTHTheme.accentDeep)
                Text("\(p.completed)/\(p.total) " + ATHLTHLocalization.choose(english: "completed", norwegian: "fullført"))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let items = state.payload.progressItems, !items.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : item.current ? "play.circle.fill" : "circle")
                                .foregroundStyle(item.completed || item.current ? ATHLTHTheme.accentDeep : Color.secondary)
                            Text(item.title).font(.caption.weight(item.current ? .semibold : .regular))
                            Spacer()
                            if item.current && !item.completed {
                                Text(ATHLTHLocalization.choose(english: "Current", norwegian: "Pågår")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if state.payload.exercises != nil || state.workoutKind ==
                WorkoutKind
                    .strength
                    .rawValue {
                strengthStateContent(
                    state
                )
            } else {
                cardioStateContent(
                    state
                )
            }
        }
        .padding(12)
        .background(
            Color.primary
                .opacity(0.035),
            in:
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
        )
    }

    @ViewBuilder
    private func strengthStateContent(
        _ state:
            SocialWorkoutLiveStateRecord
    ) -> some View {
        if let title =
                state.payload
                    .currentTitle {
            Text(title)
                .font(
                    .headline
                )

            HStack(spacing: 8) {
                if let index =
                        state.payload
                            .exerciseIndex,
                   let count =
                        state.payload
                            .exerciseCount {
                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "Exercise %d/%d",
                            norwegian:
                                "Øvelse %d/%d",
                            index + 1,
                            count
                        )
                    )
                }

                if let set =
                        state.payload
                            .currentSetNumber,
                   let total =
                        state.payload
                            .currentSetCount {
                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "Set %d/%d",
                            norwegian:
                                "Sett %d/%d",
                            set,
                            total
                        )
                    )
                }

                if state.payload
                    .isResting ==
                    true {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Resting",
                            norwegian: "Hviler"
                        ),
                        systemImage:
                            "timer"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }

        if let exercises =
                state.payload
                    .exercises,
           !exercises.isEmpty {
            DisclosureGroup(
                ATHLTHLocalization.choose(
                    english:
                        "All exercises & sets",
                    norwegian:
                        "Alle øvelser og sett"
                )
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(
                        Array(
                            exercises
                                .enumerated()
                        ),
                        id:
                            \.offset
                    ) {
                        _,
                        exercise in
                        VStack(
                            alignment:
                                .leading,
                            spacing: 4
                        ) {
                            Text(
                                exercise.name
                            )
                            .font(
                                .caption
                                    .weight(
                                        exercise
                                            .current
                                            ? .bold
                                            : .semibold
                                    )
                            )
                            .foregroundStyle(
                                exercise.current
                                    ? ATHLTHTheme
                                        .vitality
                                    : ATHLTHTheme
                                        .primaryText
                            )

                            Text(
                                setSummary(
                                    exercise
                                        .sets
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(
                .caption
                    .weight(.semibold)
            )
        }
    }

    private func cardioStateContent(
        _ state:
            SocialWorkoutLiveStateRecord
    ) -> some View {
        HStack(spacing: 16) {
            compactMetric(
                title:
                    ATHLTHLocalization.choose(
                        english:
                            "DISTANCE",
                        norwegian:
                            "DISTANSE"
                    ),
                value:
                    state.payload
                        .distanceMeters
                        .map {
                            String(
                                format:
                                    "%.2f km",
                                $0 /
                                    1_000
                            )
                        } ??
                    "—"
            )

            compactMetric(
                title:
                    ATHLTHLocalization.choose(
                        english: "TIME",
                        norwegian: "TID"
                    ),
                value:
                    durationText(
                        state.payload
                            .elapsedSeconds
                    )
            )

            compactMetric(
                title:
                    ATHLTHLocalization.choose(
                        english: "PACE",
                        norwegian: "TEMPO"
                    ),
                value:
                    paceText(
                        state.payload
                            .paceSecondsPerKilometer
                    )
            )
        }
    }

    private func compactMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 2
        ) {
            Text(title)
                .font(
                    .system(
                        size: 9,
                        weight: .bold
                    )
                )
                .tracking(0.6)
                .foregroundStyle(
                    .secondary
                )

            Text(value)
                .font(
                    .caption
                        .weight(.bold)
                        .monospacedDigit()
                )
        }
        .frame(
            maxWidth:
                .infinity,
            alignment: .leading
        )
    }

    private var chatSection:
        some View {
        ATHLTHTrainTogetherSurface {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Workout chat",
                            norwegian: "Øktchat"
                        ),
                        systemImage:
                            "bubble.left.and.bubble.right.fill"
                    )
                    .font(
                        .headline
                    )

                    Spacer()

                    Menu {
                        ForEach(
                            [
                                "👊",
                                "🔥",
                                "👏",
                                "💪"
                            ],
                            id: \.self
                        ) { reaction in
                            Button(reaction) {
                                sendReaction(
                                    reaction
                                )
                            }
                        }
                    } label: {
                        Image(
                            systemName:
                                "face.smiling"
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )
                    }

                    Button {
                        requestLocation()
                    } label: {
                        Image(
                            systemName:
                                "location.circle.fill"
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )
                    }
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english:
                                "Request location",
                            norwegian:
                                "Be om posisjon"
                        )
                    )
                }

                if companion.messages.isEmpty {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Chat, quick reactions and location requests stay inside this workout.",
                            norwegian:
                                "Chat, hurtigreaksjoner og posisjonsforespørsler hører kun til denne økten."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(
                            companion.messages
                                .suffix(30)
                        ) { message in
                            messageRow(
                                message
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english:
                                "Message…",
                            norwegian:
                                "Melding…"
                        ),
                        text:
                            $messageText
                    )
                    .textFieldStyle(
                        .roundedBorder
                    )

                    Button {
                        sendMessage()
                    } label: {
                        Image(
                            systemName:
                                "arrow.up.circle.fill"
                        )
                        .font(.title2)
                    }
                    .disabled(
                        messageText
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
            }
        }
    }

    private func messageRow(
        _ message:
            SocialWorkoutMessageRecord
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 8
        ) {
            Image(
                systemName:
                    message.kind ==
                        "location_request"
                        ? "location.fill"
                        : message.kind ==
                            "reaction"
                            ? "sparkles"
                            : "bubble.left.fill"
            )
            .font(.caption)
            .foregroundStyle(
                message.kind ==
                    "location_request"
                    ? ATHLTHTheme
                        .premiumGold
                    : ATHLTHTheme
                        .vitality
            )
            .frame(
                width: 22
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                HStack {
                    Text(
                        message
                            .senderDisplayName
                    )
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )

                    Spacer()

                    Text(
                        message.createdAt,
                        style: .time
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                }

                if let body =
                        message.body {
                    Text(body)
                        .font(.caption)
                }
            }
        }
        .padding(
            .vertical,
            3
        )
    }

    private func sendMessage() {
        guard
            let userID =
                social.currentUserID,
            let participant =
                ownParticipant
        else {
            return
        }

        let text =
            messageText
        messageText = ""

        Task {
            await companion.sendText(
                text,
                sessionID:
                    sessionID,
                senderID:
                    userID,
                displayName:
                    participant
                        .displayNameSnapshot
            )
        }
    }

    private func sendReaction(
        _ reaction: String
    ) {
        guard
            let userID =
                social.currentUserID,
            let participant =
                ownParticipant
        else {
            return
        }

        Task {
            await companion.sendReaction(
                reaction,
                sessionID:
                    sessionID,
                senderID:
                    userID,
                displayName:
                    participant
                        .displayNameSnapshot
            )
        }
    }

    private func requestLocation() {
        guard
            let userID =
                social.currentUserID,
            let participant =
                ownParticipant
        else {
            return
        }

        Task {
            await companion
                .requestLocation(
                    sessionID:
                        sessionID,
                    senderID:
                        userID,
                    displayName:
                        participant
                            .displayNameSnapshot
                )
        }
    }

    private func setSummary(
        _ sets:
            [SocialWorkoutLiveSetSnapshot]
    ) -> String {
        let completed =
            sets.filter {
                $0.completed
            }

        guard !completed.isEmpty
        else {
            return ATHLTHLocalization.choose(
                english:
                    "No completed sets yet",
                norwegian:
                    "Ingen fullførte sett ennå"
            )
        }

        return completed
            .map { set in
                var components:
                    [String] = []

                if let reps =
                        set.reps {
                    components.append(
                        "\(reps) reps"
                    )
                }

                if let weight =
                        set
                            .weightKilograms {
                    components.append(
                        String(
                            format:
                                "%.1f kg",
                            weight
                        )
                    )
                }

                return components
                    .isEmpty
                    ? ATHLTHLocalization.choose(
                        english:
                            "Completed",
                        norwegian:
                            "Fullført"
                    )
                    : components
                        .joined(
                            separator:
                                " × "
                        )
            }
            .joined(
                separator: " · "
            )
    }

    private func durationText(
        _ seconds: Double?
    ) -> String {
        guard let seconds else {
            return "—"
        }

        let value =
            max(
                Int(
                    seconds
                        .rounded()
                ),
                0
            )
        let minutes =
            value / 60
        let remainder =
            value % 60

        return String(
            format:
                "%d:%02d",
            minutes,
            remainder
        )
    }

    private func paceText(
        _ seconds: Double?
    ) -> String {
        guard
            let seconds,
            seconds.isFinite,
            seconds > 0
        else {
            return "—"
        }

        let value =
            Int(
                seconds
                    .rounded()
            )

        return String(
            format:
                "%d:%02d/km",
            value / 60,
            value % 60
        )
    }
}
