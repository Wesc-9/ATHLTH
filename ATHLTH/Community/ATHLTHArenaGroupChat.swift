import SwiftUI
import Supabase

/// One shared room per Arena series. Membership and posting authorization
/// are enforced in the database; this is not a reusable public Club chat.
struct ATHLTHArenaGroupChatView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore

    let series: ATHLTHArenaRemoteSeries

    @State private var messages: [ATHLTHArenaRemoteMessage] = []
    @State private var membership: ATHLTHArenaRemoteMember?
    @State private var responding = false

    private var isAccepted: Bool { membership?.response == "accepted" }
    private var hasInvitation: Bool { membership?.response == "invited" }
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var error: String?

    private let cloud = ATHLTHArenaCloudService()

    private var canSend: Bool {
        isAccepted && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSending && draft.count <= 2000
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        intro

                        if hasInvitation {
                            invitationCard
                        } else if !isAccepted {
                            Text(ATHLTHLocalization.choose(
                                english: "Accept the invitation to join the conversation.",
                                norwegian: "Godta invitasjonen for å delta i gruppesamtalen."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .padding(12)
                        }

                        if isAccepted {
                            ForEach(messages) { item in
                            messageBubble(item)
                                .id(item.id)
                            }
                        }

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isAccepted {
                HStack(spacing: 10) {
                TextField(
                    ATHLTHLocalization.choose(
                        english: "Message the group...",
                        norwegian: "Skriv til gruppen..."
                    ),
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .font(.subheadline)
                .padding(10)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 16))
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    ATHLTHTheme.accentDeep,
                    in: Circle()
                )
                .disabled(!canSend)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Send message", norwegian: "Send melding"
                ))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            }
        }
        .background(ATHLTHPremiumCanvas(
            accent: ATHLTHTheme.champagneSoft.opacity(0.13)
        ))
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: series.id) { await reload() }
        .task(id: series.id) { await listenForMessages() }
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 15) {
                    NavigationLink {
                        ATHLTHArenaOnlineDetailView(series: series)
                    } label: {
                        Image(systemName: "trophy.fill")
                    }
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "View competition and approve rounds",
                        norwegian: "Se konkurransen og godkjenn runder"
                    ))
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("ATHLTH Arena", systemImage: "person.3.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(ATHLTHLocalization.choose(
                english: "Group conversation for this competition",
                norwegian: "Gruppesamtale for denne konkurransen"
            ))
            .font(.subheadline.weight(.medium))
            Text(ATHLTHLocalization.choose(
                english: "Share ideas and agree on rounds. Only accepted participants can read or send messages.",
                norwegian: "Diskuter forslag og bli enige om rundene. Bare godkjente deltakere kan lese og sende meldinger."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var invitationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(ATHLTHLocalization.choose(
                english: "Competition invitation",
                norwegian: "Invitasjon til konkurranse"
            ), systemImage: "envelope.badge.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            Text(series.title)
                .font(.title3.weight(.semibold))
            Text(series.scoring.title)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Text(ATHLTHLocalization.choose(
                english: "Accept to join the group chat and propose rounds. You can review the full competition before deciding.",
                norwegian: "Godta for å bli med i gruppechatten og foreslå runder. Du kan se hele konkurransen før du bestemmer deg."
            ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            HStack(spacing: 10) {
                Button {
                    Task { await respond(accept: true) }
                } label: {
                    Label(ATHLTHLocalization.choose(english: "Accept", norwegian: "Godta"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
                Button {
                    Task { await respond(accept: false) }
                } label: {
                    Text(ATHLTHLocalization.choose(english: "Decline", norwegian: "Avslå"))
                }
                .buttonStyle(.bordered)
                .disabled(responding)
            }
        }
        .foregroundStyle(ATHLTHTheme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 21))
    }

    private func messageBubble(_ item: ATHLTHArenaRemoteMessage) -> some View {
        let mine = item.senderID == session.profile.userID
        let deleted = item.senderID == nil
        let name = deleted
            ? ATHLTHLocalization.choose(
                english: "Deleted user", norwegian: "Slettet bruker"
              )
            : (mine
                ? ATHLTHLocalization.choose(english: "You", norwegian: "Du")
                : (social.visibleProfiles + social.mutualFollows)
                    .first { $0.userID == item.senderID }?.resolvedName ??
                  ATHLTHLocalization.choose(english: "Participant", norwegian: "Deltaker"))

        return HStack {
            if mine { Spacer(minLength: 45) }
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(deleted ? Color.gray : ATHLTHTheme.accentDeep)
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(deleted ? Color.gray : ATHLTHTheme.primaryText)
                Text(item.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            .frame(maxWidth: 300, alignment: .leading)
            .padding(12)
            .background(
                mine ? ATHLTHTheme.accentDeep.opacity(0.10) : Color.white.opacity(0.87),
                in: RoundedRectangle(cornerRadius: 17)
            )
            if !mine { Spacer(minLength: 45) }
        }
    }

    @MainActor
    /// Live updates while the group chat is on screen. Supabase checks row
    /// access with existing Arena RLS; no participant data is broadcast
    /// outside the competition. The task stops on navigation away.
    private func listenForMessages() async {
        let channel = await SupabaseEnvironment.client.channel(
            "arena-chat-\(series.id.uuidString.lowercased())"
        )
        let changes = await channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "arena_series_messages"
        )
        await channel.subscribe()
        for await _ in changes {
            if Task.isCancelled { break }
            await reload()
        }
        await channel.unsubscribe()
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let allMembers = try await cloud.loadMembers(seriesID: series.id)
            membership = allMembers.first { $0.userID == session.profile.userID }
            if isAccepted {
                messages = try await cloud.loadGroupMessages(seriesID: series.id)
            } else {
                messages = []
            }
            error = nil
        } catch { self.error = error.localizedDescription
        }
    }

    @MainActor
    private func respond(accept: Bool) async {
        guard !responding else { return }
        responding = true
        defer { responding = false }
        do {
            try await cloud.respond(seriesID: series.id, accept: accept)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func send() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await cloud.sendGroupMessage(seriesID: series.id, body: draft)
            draft = ""
            await reload()
        } catch { self.error = error.localizedDescription
        }
    }
}
