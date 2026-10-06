import Foundation
import Supabase
import SwiftUI

struct CommunityEventChatMessageRecord:
    Codable,
    Hashable,
    Identifiable
{
    let id: UUID
    let eventID: UUID
    let authorID: UUID?
    let kind: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case authorID = "author_id"
        case kind
        case body
        case createdAt = "created_at"
    }
}

private struct CommunityEventChatInsert:
    Encodable
{
    let eventID: UUID
    let authorID: UUID
    let kind: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case authorID = "author_id"
        case kind
        case body
    }
}

private struct CommunityEventChatStatusRow:
    Decodable
{
    let status: String
}

@MainActor
final class CommunityEventChatStore:
    ObservableObject
{
    @Published private(set)
    var messages:
        [CommunityEventChatMessageRecord] = []
    @Published private(set)
    var profiles:
        [UUID: SocialProfileCard] = [:]
    @Published private(set)
    var eventStatus: String?
    @Published private(set)
    var isLoading = false
    @Published private(set)
    var isSending = false
    @Published var errorMessage: String?

    let eventID: UUID

    private let client: SupabaseClient

    init(
        eventID: UUID,
        client: SupabaseClient =
            SupabaseEnvironment.client
    ) {
        self.eventID = eventID
        self.client = client
    }

    var currentUserID: UUID? {
        client.auth.currentUser?.id
    }

    var latestAdminStatus:
        CommunityEventChatMessageRecord? {
        messages.last {
            $0.kind == "status"
        }
    }

    var chatMessageCount: Int {
        messages.filter {
            $0.kind == "message"
        }.count
    }

    func profile(
        for userID: UUID?
    ) -> SocialProfileCard? {
        guard let userID else {
            return nil
        }

        return profiles[userID]
    }

    func refresh(
        showLoading: Bool = false
    ) async {
        if showLoading {
            isLoading = true
        }

        defer {
            if showLoading {
                isLoading = false
            }
        }

        do {
            async let messagesQuery:
                [CommunityEventChatMessageRecord] =
                    client
                        .from(
                            "community_event_messages"
                        )
                        .select()
                        .eq(
                            "event_id",
                            value: eventID
                        )
                        .order(
                            "created_at",
                            ascending: true
                        )
                        .execute()
                        .value

            async let statusQuery:
                [CommunityEventChatStatusRow] =
                    client
                        .from(
                            "community_events"
                        )
                        .select("status")
                        .eq(
                            "id",
                            value: eventID
                        )
                        .limit(1)
                        .execute()
                        .value

            let loadedMessages =
                try await messagesQuery
            let statuses =
                try await statusQuery

            let authorIDs =
                Array(
                    Set(
                        loadedMessages
                            .compactMap(
                                \.authorID
                            )
                    )
                )

            let loadedProfiles:
                [SocialProfileCard]

            if authorIDs.isEmpty {
                loadedProfiles = []
            } else {
                loadedProfiles =
                    try await client
                        .from(
                            "social_profile_cards"
                        )
                        .select()
                        .in(
                            "user_id",
                            values:
                                authorIDs
                                    .map(
                                        \.uuidString
                                    )
                        )
                        .execute()
                        .value
            }

            messages = loadedMessages
            profiles =
                Dictionary(
                    uniqueKeysWithValues:
                        loadedProfiles.map {
                            (
                                $0.userID,
                                $0
                            )
                        }
                )
            eventStatus =
                statuses.first?.status
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            errorMessage =
                error.localizedDescription
        }
    }

    func sendMessage(
        _ text: String
    ) async -> Bool {
        await send(
            text,
            kind: "message",
            maxLength: 1_500
        )
    }

    func sendStatus(
        _ text: String
    ) async -> Bool {
        await send(
            text,
            kind: "status",
            maxLength: 500
        )
    }

    private func send(
        _ text: String,
        kind: String,
        maxLength: Int
    ) async -> Bool {
        guard let currentUserID else {
            return false
        }

        let clean =
            text.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard !clean.isEmpty else {
            return false
        }

        isSending = true
        defer {
            isSending = false
        }

        do {
            try await client
                .from(
                    "community_event_messages"
                )
                .insert(
                    CommunityEventChatInsert(
                        eventID: eventID,
                        authorID:
                            currentUserID,
                        kind: kind,
                        body:
                            String(
                                clean.prefix(
                                    maxLength
                                )
                            )
                    )
                )
                .execute()

            await refresh()
            return true
        } catch {
            errorMessage =
                error.localizedDescription
            return false
        }
    }
}

struct CommunityEventSocialSection:
    View
{
    @EnvironmentObject private var session:
        AppSessionStore

    let item: CommunityEventItem

    @StateObject private var chat:
        CommunityEventChatStore
    @State private var showingStatusComposer =
        false

    init(item: CommunityEventItem) {
        self.item = item
        _chat = StateObject(
            wrappedValue:
                CommunityEventChatStore(
                    eventID: item.id
                )
        )
    }

    private var isAdmin: Bool {
        item.event.creatorID ==
            session.profile.userID
    }

    private var canUseChat: Bool {
        isAdmin ||
        item.participantRows.contains {
            $0.userID ==
                session.profile.userID
        }
    }

    private var canSendStatus: Bool {
        isAdmin &&
        item.event.status != "completed" &&
        item.event.status != "cancelled"
    }

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Event chat",
                            norwegian:
                                "Arrangementchat"
                        )
                    )
                    .font(.headline)

                    Text(
                        canUseChat
                            ? ATHLTHLocalization
                                .format(
                                    english:
                                        "%d messages",
                                    norwegian:
                                        "%d meldinger",
                                    chat
                                        .chatMessageCount
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "Join the event to access the chat.",
                                    norwegian:
                                        "Delta på arrangementet for å få tilgang til chatten."
                                )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "bubble.left.and.bubble.right.fill"
                )
                .font(.title3)
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )
            }

            if let status =
                    chat.latestAdminStatus {
                Divider()
                    .padding(.vertical, 8)

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Latest status",
                            norwegian:
                                "Siste status"
                        ),
                        systemImage:
                            "megaphone.fill"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )

                    Text(status.body)
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                    Text(
                        status.createdAt
                            .formatted(
                                date: .omitted,
                                time: .shortened
                            )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                }
            }

            if canUseChat {
                NavigationLink {
                    CommunityEventChatView(
                        event: item.event
                    )
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Open chat",
                            norwegian: "Åpne chat"
                        ),
                        systemImage:
                            "bubble.left.fill"
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 42
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    ATHLTHTheme.vitality
                )
                .padding(.top, 9)
            }

            if canSendStatus {
                Button {
                    showingStatusComposer =
                        true
                } label: {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "Send status",
                            norwegian: "Send status"
                        ),
                        systemImage:
                            "megaphone"
                    )
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 38
                    )
                }
                .buttonStyle(.bordered)
                .padding(.top, 6)
            }
        }
        .task {
            if canUseChat {
                await chat.refresh(
                    showLoading: true
                )
            }
        }
        .sheet(
            isPresented:
                $showingStatusComposer
        ) {
            CommunityEventAdminStatusSheet(
                chat: chat,
                eventTitle:
                    item.event.title
            )
        }
    }
}

struct CommunityEventChatView: View {
    @EnvironmentObject private var session:
        AppSessionStore

    let event: CommunityEventRecord

    @StateObject private var chat:
        CommunityEventChatStore
    @State private var draft = ""

    init(event: CommunityEventRecord) {
        self.event = event
        _chat = StateObject(
            wrappedValue:
                CommunityEventChatStore(
                    eventID: event.id
                )
        )
    }

    private var resolvedStatus: String {
        chat.eventStatus ??
            event.status
    }

    private var canSend: Bool {
        resolvedStatus == "upcoming" ||
        resolvedStatus == "live"
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme.vitality
                        .opacity(0.16)
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                messageList

                if canSend {
                    composer
                } else {
                    closedComposer
                }
            }
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Event chat",
                norwegian:
                    "Arrangementchat"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task {
            await chat.refresh(
                showLoading: true
            )

            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds:
                            6_000_000_000
                    )
                } catch {
                    break
                }

                await chat.refresh()
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(
                    spacing: 10
                ) {
                    if chat.isLoading &&
                        chat.messages.isEmpty {
                        ProgressView()
                            .padding(.top, 50)
                    } else if chat.messages
                        .isEmpty {
                        ContentUnavailableView {
                            Label(
                                ATHLTHLocalization.choose(
                                    english:
                                        "No messages yet",
                                    norwegian:
                                        "Ingen meldinger ennå"
                                ),
                                systemImage:
                                    "bubble.left"
                            )
                        } description: {
                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Use the event chat to coordinate with everyone who is attending.",
                                    norwegian:
                                        "Bruk arrangementchatten til å koordinere med alle som deltar."
                                )
                            )
                        }
                        .padding(.top, 52)
                    }

                    ForEach(
                        chat.messages
                    ) { message in
                        EventChatMessageRow(
                            message: message,
                            profile:
                                chat.profile(
                                    for:
                                        message
                                            .authorID
                                ),
                            isOwn:
                                message.authorID ==
                                session.profile
                                    .userID
                        )
                        .id(message.id)
                    }

                    if let error =
                            chat.errorMessage,
                       !error.isEmpty {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(
                .interactively
            )
            .onChange(
                of: chat.messages.count
            ) { _, _ in
                guard let last =
                        chat.messages.last
                else {
                    return
                }

                withAnimation(
                    .easeOut(
                        duration: 0.20
                    )
                ) {
                    proxy.scrollTo(
                        last.id,
                        anchor: .bottom
                    )
                }
            }
        }
    }

    private var composer: some View {
        HStack(
            alignment: .bottom,
            spacing: 9
        ) {
            TextField(
                ATHLTHLocalization.choose(
                    english: "Message",
                    norwegian: "Melding"
                ),
                text: $draft,
                axis: .vertical
            )
            .lineLimit(1...5)
            .padding(
                .horizontal,
                13
            )
            .padding(
                .vertical,
                10
            )
            .background(
                ATHLTHTheme.cardWarm,
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style:
                            .continuous
                    )
            )

            Button {
                send()
            } label: {
                if chat.isSending {
                    ProgressView()
                        .frame(
                            width: 40,
                            height: 40
                        )
                } else {
                    Image(
                        systemName:
                            "arrow.up"
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .background(
                        ATHLTHTheme.vitality,
                        in: Circle()
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(
                draft
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .isEmpty ||
                chat.isSending
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(
            .bottom,
            10
        )
        .background(
            .ultraThinMaterial
        )
    }

    private var closedComposer: some View {
        Label(
            resolvedStatus == "cancelled"
                ? ATHLTHLocalization.choose(
                    english:
                        "This event is cancelled. The chat is read-only.",
                    norwegian:
                        "Arrangementet er avlyst. Chatten er skrivebeskyttet."
                )
                : ATHLTHLocalization.choose(
                    english:
                        "This event is completed. The chat is read-only.",
                    norwegian:
                        "Arrangementet er fullført. Chatten er skrivebeskyttet."
                ),
            systemImage: "lock.fill"
        )
        .font(.caption)
        .foregroundStyle(
            .secondary
        )
        .frame(
            maxWidth: .infinity
        )
        .padding(14)
        .background(
            .ultraThinMaterial
        )
    }

    private func send() {
        let message = draft
        draft = ""

        Task {
            let sent =
                await chat.sendMessage(
                    message
                )

            if !sent {
                draft = message
            }
        }
    }
}

private struct EventChatMessageRow:
    View
{
    let message:
        CommunityEventChatMessageRecord
    let profile: SocialProfileCard?
    let isOwn: Bool

    var body: some View {
        switch message.kind {
        case "system":
            systemMessage

        case "status":
            statusMessage

        default:
            chatMessage
        }
    }

    private var systemMessage: some View {
        HStack {
            Spacer()

            Label(
                systemMessageText(
                    message.body
                ),
                systemImage:
                    systemMessageIcon(
                        message.body
                    )
            )
            .font(
                .caption.weight(
                    .semibold
                )
            )
            .foregroundStyle(
                .secondary
            )
            .padding(
                .horizontal,
                12
            )
            .padding(
                .vertical,
                7
            )
            .background(
                ATHLTHTheme.cardWarm,
                in: Capsule()
            )

            Spacer()
        }
        .padding(.vertical, 3)
    }

    private var statusMessage: some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            HStack(spacing: 7) {
                Image(
                    systemName:
                        "megaphone.fill"
                )
                .foregroundStyle(
                    ATHLTHTheme.vitality
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Status from organizer",
                        norwegian:
                            "Status fra arrangør"
                    )
                )
                .font(
                    .caption.weight(
                        .bold
                    )
                )

                Spacer()

                Text(
                    message.createdAt
                        .formatted(
                            date: .omitted,
                            time: .shortened
                        )
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }

            Text(message.body)
                .font(
                    .subheadline
                        .weight(.semibold)
                )
        }
        .padding(13)
        .background(
            ATHLTHTheme
                .surfaceSage,
            in:
                RoundedRectangle(
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
                ATHLTHTheme.vitality
                    .opacity(0.18),
                lineWidth: 1
            )
        }
    }

    private var chatMessage: some View {
        HStack(
            alignment: .bottom,
            spacing: 8
        ) {
            if isOwn {
                Spacer(minLength: 48)
            } else {
                EventChatAvatar(
                    profile: profile,
                    size: 28
                )
            }

            VStack(
                alignment:
                    isOwn
                        ? .trailing
                        : .leading,
                spacing: 3
            ) {
                if !isOwn {
                    Text(
                        profile?
                            .resolvedName ??
                        ATHLTHLocalization
                            .choose(
                                english:
                                    "ATHLTH athlete",
                                norwegian:
                                    "ATHLTH-utøver"
                            )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .padding(
                        .horizontal,
                        12
                    )
                    .padding(
                        .vertical,
                        9
                    )
                    .background(
                        isOwn
                            ? ATHLTHTheme
                                .vitalitySoft
                            : ATHLTHTheme
                                .cardWarm,
                        in:
                            RoundedRectangle(
                                cornerRadius: 17,
                                style:
                                    .continuous
                            )
                    )

                Text(
                    message.createdAt
                        .formatted(
                            date: .omitted,
                            time: .shortened
                        )
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }

            if !isOwn {
                Spacer(minLength: 48)
            }
        }
    }

    private func systemMessageText(
        _ code: String
    ) -> String {
        switch code {
        case "event_started":
            return ATHLTHLocalization.choose(
                english:
                    "The event has started",
                norwegian:
                    "Arrangementet er startet"
            )
        case "event_completed":
            return ATHLTHLocalization.choose(
                english:
                    "The event is completed",
                norwegian:
                    "Arrangementet er fullført"
            )
        case "event_cancelled":
            return ATHLTHLocalization.choose(
                english:
                    "The event was cancelled",
                norwegian:
                    "Arrangementet ble avlyst"
            )
        default:
            return code
        }
    }

    private func systemMessageIcon(
        _ code: String
    ) -> String {
        switch code {
        case "event_started":
            return "play.fill"
        case "event_completed":
            return "checkmark.seal.fill"
        case "event_cancelled":
            return "xmark.circle.fill"
        default:
            return "info.circle.fill"
        }
    }
}

private struct EventChatAvatar:
    View
{
    let profile: SocialProfileCard?
    let size: CGFloat

    var body: some View {
        Group {
            if let rawURL =
                    profile?.avatarURL,
               let url =
                    URL(string: rawURL) {
                ATHLTHStorageImage(
                    url: url
                ) { phase in
                    switch phase {
                    case .success(
                        let image
                    ):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(
            width: size,
            height: size
        )
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(
                ATHLTHTheme.accentSoft
            )
            .overlay {
                Image(
                    systemName:
                        "person.fill"
                )
                .font(
                    .system(
                        size:
                            size * 0.38
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accent
                )
            }
    }
}

private struct CommunityEventAdminStatusSheet:
    View
{
    @Environment(\.dismiss)
    private var dismiss

    @ObservedObject var chat:
        CommunityEventChatStore

    let eventTitle: String

    @State private var text = ""

    private var presets: [String] {
        [
            ATHLTHLocalization.choose(
                english:
                    "We start in 15 minutes.",
                norwegian:
                    "Vi starter om 15 minutter."
            ),
            ATHLTHLocalization.choose(
                english:
                    "We're running 10 minutes late.",
                norwegian:
                    "Vi er 10 minutter forsinket."
            ),
            ATHLTHLocalization.choose(
                english:
                    "We start now.",
                norwegian:
                    "Vi starter nå."
            ),
            ATHLTHLocalization.choose(
                english:
                    "The meetup point has been updated. Check the event details.",
                norwegian:
                    "Møtestedet er oppdatert. Se detaljene i arrangementet."
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .vitality
                            .opacity(0.16)
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 16
                    ) {
                        VStack(
                            alignment:
                                .leading,
                            spacing: 5
                        ) {
                            Label(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Organizer status",
                                        norwegian:
                                            "Arrangørstatus"
                                    ),
                                systemImage:
                                    "megaphone.fill"
                            )
                            .font(
                                .title3
                                    .weight(
                                        .bold
                                    )
                            )

                            Text(eventTitle)
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                        }

                        ATHLTHCard {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Quick status",
                                        norwegian:
                                            "Hurtigstatus"
                                    )
                            )
                            .font(.headline)

                            VStack(
                                spacing: 8
                            ) {
                                ForEach(
                                    presets,
                                    id: \.self
                                ) { preset in
                                    Button {
                                        text =
                                            preset
                                    } label: {
                                        HStack {
                                            Text(
                                                preset
                                            )
                                            .font(
                                                .subheadline
                                            )
                                            .multilineTextAlignment(
                                                .leading
                                            )

                                            Spacer()

                                            if text ==
                                                preset {
                                                Image(
                                                    systemName:
                                                        "checkmark.circle.fill"
                                                )
                                                .foregroundStyle(
                                                    ATHLTHTheme
                                                        .vitality
                                                )
                                            }
                                        }
                                        .frame(
                                            maxWidth:
                                                .infinity,
                                            alignment:
                                                .leading
                                        )
                                    }
                                    .buttonStyle(
                                        .plain
                                    )

                                    if preset !=
                                        presets.last {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }

                        ATHLTHCard {
                            Text(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Message",
                                        norwegian:
                                            "Melding"
                                    )
                            )
                            .font(.headline)

                            TextField(
                                ATHLTHLocalization
                                    .choose(
                                        english:
                                            "Write a status update",
                                        norwegian:
                                            "Skriv en statusoppdatering"
                                    ),
                                text: $text,
                                axis: .vertical
                            )
                            .lineLimit(3...7)
                            .padding(.top, 6)
                        }

                        Button {
                            send()
                        } label: {
                            HStack {
                                if chat.isSending {
                                    ProgressView()
                                } else {
                                    Image(
                                        systemName:
                                            "paperplane.fill"
                                    )
                                }

                                Text(
                                    ATHLTHLocalization
                                        .choose(
                                            english:
                                                "Send status",
                                            norwegian:
                                                "Send status"
                                        )
                                )
                                .font(
                                    .headline
                                )
                            }
                            .frame(
                                maxWidth:
                                    .infinity,
                                minHeight: 48
                            )
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .tint(
                            ATHLTHTheme.vitality
                        )
                        .disabled(
                            text
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )
                                .isEmpty ||
                            chat.isSending
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Send status",
                    norwegian: "Send status"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Close",
                            norwegian: "Lukk"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func send() {
        let status = text

        Task {
            if await chat.sendStatus(
                status
            ) {
                dismiss()
            }
        }
    }
}
