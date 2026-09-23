import CoreLocation
import SwiftUI

struct MessageInboxView: View {
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Messages")
                            .font(.title2.bold())
                        Text("Chat and share training with your friends.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if messaging.unreadCount > 0 {
                        Text("\(messaging.unreadCount)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(ATHLTHTheme.accent, in: Capsule())
                    }
                }

                if let error = messaging.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if social.friends.isEmpty {
                    ContentUnavailableView(
                        "No friends to message",
                        systemImage: "message",
                        description: Text("Add a friend first, then you can chat and share workouts, plans, routes and challenges.")
                    )
                    .padding(.vertical, 50)
                } else {
                    let activeConversations = conversationFriends

                    if !activeConversations.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CONVERSATIONS")
                                .font(.caption.weight(.semibold))
                                .tracking(2)
                                .foregroundStyle(ATHLTHTheme.mutedText)

                            ForEach(activeConversations) { item in
                                NavigationLink {
                                    DirectMessageThreadView(friend: item.friend)
                                } label: {
                                    MessageConversationRow(
                                        friend: item.friend,
                                        lastMessage: item.lastMessage,
                                        unreadCount: messaging.unreadCount(for: item.conversation.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    let availableFriends = friendsWithoutConversation
                    if !availableFriends.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("START A CONVERSATION")
                                .font(.caption.weight(.semibold))
                                .tracking(2)
                                .foregroundStyle(ATHLTHTheme.mutedText)

                            ForEach(availableFriends) { friend in
                                NavigationLink {
                                    DirectMessageThreadView(friend: friend)
                                } label: {
                                    HStack(spacing: 13) {
                                        SocialAvatar(profile: friend, size: 48)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(friend.resolvedName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(friend.usernameLabel)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "message.fill")
                                            .foregroundStyle(ATHLTHTheme.accent)
                                    }
                                    .padding(14)
                                    .background(
                                        Color.white.opacity(0.96),
                                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(ATHLTHTheme.border, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await messaging.refresh()
        }
        .task {
            await messaging.refresh()
        }
    }

    private var conversationFriends: [MessageConversationItem] {
        guard let currentUserID = messaging.currentUserID else { return [] }

        return messaging.conversations.compactMap { conversation in
            guard let friendID = conversation.otherUserID(for: currentUserID),
                  let friend = social.friends.first(where: { $0.userID == friendID })
            else {
                return nil
            }

            return MessageConversationItem(
                conversation: conversation,
                friend: friend,
                lastMessage: messaging.lastMessage(for: conversation.id)
            )
        }
        .sorted {
            ($0.conversation.lastMessageAt ?? $0.conversation.createdAt) >
            ($1.conversation.lastMessageAt ?? $1.conversation.createdAt)
        }
    }

    private var friendsWithoutConversation: [SocialProfileCard] {
        let conversationIDs = Set(conversationFriends.map { $0.friend.userID })
        return social.friends.filter { !conversationIDs.contains($0.userID) }
    }
}

private struct MessageConversationItem: Identifiable {
    var id: UUID { conversation.id }

    let conversation: DirectConversationRecord
    let friend: SocialProfileCard
    let lastMessage: DirectMessageRecord?
}

private struct MessageConversationRow: View {
    let friend: SocialProfileCard
    let lastMessage: DirectMessageRecord?
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 13) {
            SocialAvatar(profile: friend, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.resolvedName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(unreadCount > 0 ? .primary : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 7) {
                if let date = lastMessage?.createdAt {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(ATHLTHTheme.accent, in: Circle())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(
            Color.white.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }

    private var previewText: String {
        guard let lastMessage else { return "Start a conversation" }

        if let body = lastMessage.body, !body.isEmpty {
            return body
        }

        if let kind = lastMessage.attachmentKind {
            return "Shared \(kind.title.lowercased()) · \(lastMessage.attachmentTitle ?? "")"
        }

        return "Message"
    }
}

struct DirectMessageThreadView: View {
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore

    let friend: SocialProfileCard

    @State private var conversationID: UUID?
    @State private var text = ""
    @State private var selectedShare: MessageShareDraft?
    @State private var showingSharePicker = false
    @State private var isSending = false
    @State private var loadError: String?
    @State private var savedFeedback: String?

    var body: some View {
        VStack(spacing: 0) {
            if let conversationID {
                messagesView(conversationID)
            } else if let loadError {
                ContentUnavailableView(
                    "Messages unavailable",
                    systemImage: "exclamationmark.bubble",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Opening conversation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
        .navigationTitle(friend.resolvedName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .sheet(isPresented: $showingSharePicker) {
            MessageSharePicker { draft in
                selectedShare = draft
                showingSharePicker = false
            }
        }
        .alert(
            "Saved to ATHLTH",
            isPresented: Binding(
                get: { savedFeedback != nil },
                set: { if !$0 { savedFeedback = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedFeedback ?? "")
        }
        .task(id: friend.userID) {
            await openAndPoll()
        }
    }

    @ViewBuilder
    private func messagesView(_ conversationID: UUID) -> some View {
        let messages = messaging.messages(in: conversationID)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        ContentUnavailableView(
                            "Start the conversation",
                            systemImage: "message",
                            description: Text("Send a message or share a workout, plan, route or challenge.")
                        )
                        .padding(.top, 80)
                    }

                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            friend: friend,
                            currentUserID: messaging.currentUserID,
                            onSaveAttachment: {
                                saveAttachment(message)
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .task {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let selectedShare {
                HStack(spacing: 10) {
                    Image(systemName: selectedShare.kind.systemImage)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedShare.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(selectedShare.kind.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        self.selectedShare = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    showingSharePicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(ATHLTHTheme.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(conversationID == nil)

                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 38, height: 38)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                }
                .background(ATHLTHTheme.accent, in: Circle())
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
                .opacity(canSend ? 1 : 0.45)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        selectedShare != nil
    }

    private func openAndPoll() async {
        do {
            let id = try await messaging.openConversation(with: friend.userID)
            conversationID = id
            await messaging.refreshConversation(id)
            markLocalMessageNotificationsRead(conversationID: id)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await messaging.refreshConversation(id)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func markLocalMessageNotificationsRead(conversationID: UUID) {
        for item in notifications.items
        where item.socialEventKind == "message" &&
              item.socialEntityID == conversationID &&
              item.isUnread {
            notifications.markRead(item.id)
        }
    }

    private func send() async {
        guard let conversationID, canSend else { return }

        isSending = true
        let body = text
        let attachment = selectedShare

        if await messaging.send(
            to: friend.userID,
            conversationID: conversationID,
            body: body,
            attachment: attachment
        ) {
            text = ""
            selectedShare = nil
        }

        isSending = false
    }

    private func saveAttachment(_ message: DirectMessageRecord) {
        guard message.senderID != messaging.currentUserID else { return }

        switch message.attachmentKind {
        case .workout:
            if let workout = message.decodeSnapshot(PlannedSession.self) {
                session.saveSharedWorkout(
                    workout,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceSessionID: message.sourceObjectID
                )
                savedFeedback = "\(workout.title) was saved to your workout library."
            }

        case .trainingPlan:
            if let plan = message.decodeSnapshot(TrainingPlan.self) {
                session.saveSharedPlan(
                    plan,
                    sourceOwnerID: message.sourceOwnerID,
                    sourcePlanID: message.sourceObjectID,
                    sourceVersion: message.shareVersion
                )
                savedFeedback = "\(plan.title) was saved as your own private copy."
            }

        case .runningWorkout:
            if let workout = message.decodeSnapshot(RunningWorkoutTemplate.self) {
                _ = runningLibrary.saveShared(
                    workout,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceWorkoutID: message.sourceObjectID
                )
                savedFeedback = "\(workout.title) was saved to Running Workouts."
            }

        case .route:
            if let route = message.decodeSnapshot(TrainingRoute.self) {
                session.saveSharedRoute(
                    route,
                    sourceOwnerID: message.sourceOwnerID,
                    sourceRouteID: message.sourceObjectID
                )
                savedFeedback = "\(route.title) was saved as a private route."
            }

        case .challenge:
            savedFeedback = "Challenges stay linked to the original challenge. Open Challenges to accept or view it."

        case .none:
            break
        }
    }
}

private struct MessageBubble: View {
    let message: DirectMessageRecord
    let friend: SocialProfileCard
    let currentUserID: UUID?
    let onSaveAttachment: () -> Void

    private var isMine: Bool {
        message.senderID == currentUserID
    }

    private var provenanceText: String {
        if let sourceOwnerID = message.sourceOwnerID {
            if sourceOwnerID == currentUserID {
                return "Created by you"
            }
            if sourceOwnerID == friend.userID {
                return "Created by \(friend.resolvedName)"
            }
            return "Original creator preserved"
        }

        return isMine ? "Shared by you" : "Shared by \(friend.resolvedName)"
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isMine {
                Spacer(minLength: 48)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if let attachmentKind = message.attachmentKind {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Image(systemName: attachmentKind.systemImage)
                                .foregroundStyle(ATHLTHTheme.accent)
                            Text(attachmentKind.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(1)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                        }

                        Text(message.attachmentTitle ?? attachmentKind.title)
                            .font(.headline)

                        if let subtitle = message.attachmentSubtitle,
                           !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(provenanceText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        if !isMine {
                            Button {
                                onSaveAttachment()
                            } label: {
                                Label(
                                    attachmentKind == .challenge ? "View details" : "Save a copy",
                                    systemImage: attachmentKind == .challenge ? "bolt.fill" : "square.and.arrow.down"
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(ATHLTHTheme.accent)
                        }
                    }
                    .padding(13)
                    .frame(maxWidth: 300, alignment: .leading)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(ATHLTHTheme.border, lineWidth: 1)
                    }
                }

                if let body = message.body, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(isMine ? Color.white : ATHLTHTheme.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isMine ? ATHLTHTheme.accent : Color.white,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                }

                HStack(spacing: 4) {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    if isMine {
                        Image(systemName: message.readAt == nil ? "checkmark" : "checkmark.circle.fill")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if !isMine {
                Spacer(minLength: 48)
            }
        }
    }
}

struct MessageSharePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var challengeStore: ChallengeStore
    @EnvironmentObject private var settings: AppSettingsStore

    let onSelect: (MessageShareDraft) -> Void

    @State private var selectedKind: MessageShareKind = .workout
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MessageShareKind.allCases) { kind in
                            Button {
                                selectedKind = kind
                            } label: {
                                Label(kind.title, systemImage: kind.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(
                                        selectedKind == kind
                                            ? Color.white
                                            : ATHLTHTheme.primaryText
                                    )
                                    .background(
                                        selectedKind == kind
                                            ? ATHLTHTheme.accent
                                            : Color(.secondarySystemGroupedBackground),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                List {
                    shareContent
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Share with Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Could Not Share",
                isPresented: Binding(
                    get: { shareError != nil },
                    set: { if !$0 { shareError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareError ?? "")
            }
        }
    }

    @ViewBuilder
    private var shareContent: some View {
        switch selectedKind {
        case .workout:
            let workouts = shareableWorkouts
            if workouts.isEmpty {
                ContentUnavailableView(
                    "No saved workouts",
                    systemImage: "dumbbell",
                    description: Text("Create a workout or add one to a training plan first.")
                )
            } else {
                ForEach(workouts) { workout in
                    shareRow(
                        icon: workout.kind.systemImage,
                        title: workout.title,
                        subtitle: workoutSubtitle(workout)
                    ) {
                        createDraft(
                            kind: .workout,
                            title: workout.title,
                            subtitle: workoutSubtitle(workout),
                            snapshot: workout,
                            sourceObjectID: workout.sharedSourceSessionID ?? workout.id,
                            sourceOwnerID: workout.sharedSourceOwnerID ?? session.profile.userID
                        )
                    }
                }
            }

        case .trainingPlan:
            let plans = shareablePlans
            if plans.isEmpty {
                ContentUnavailableView(
                    "No training plans",
                    systemImage: "calendar",
                    description: Text("Create or save a training plan first.")
                )
            } else {
                ForEach(plans) { plan in
                    shareRow(
                        icon: "calendar",
                        title: plan.title,
                        subtitle: "\(plan.weeks.count) weeks · version \(plan.version)"
                    ) {
                        createDraft(
                            kind: .trainingPlan,
                            title: plan.title,
                            subtitle: "\(plan.weeks.count) weeks · snapshot v\(plan.version)",
                            snapshot: plan,
                            sourceObjectID: plan.sharedSourcePlanID ?? plan.id,
                            sourceOwnerID: plan.sharedSourceOwnerID ?? plan.ownerID,
                            shareVersion: plan.sharedSourceVersion ?? plan.version
                        )
                    }
                }
            }

        case .runningWorkout:
            if runningLibrary.customTemplates.isEmpty {
                ContentUnavailableView(
                    "No custom running workouts",
                    systemImage: "figure.run",
                    description: Text("Create a running workout first.")
                )
            } else {
                ForEach(runningLibrary.customTemplates) { workout in
                    shareRow(
                        icon: "figure.run",
                        title: workout.title,
                        subtitle: workout.summary
                    ) {
                        createDraft(
                            kind: .runningWorkout,
                            title: workout.title,
                            subtitle: workout.summary,
                            snapshot: workout,
                            sourceObjectID: workout.sharedSourceWorkoutID ?? workout.id,
                            sourceOwnerID: workout.sharedSourceOwnerID ?? session.profile.userID
                        )
                    }
                }
            }

        case .route:
            if session.savedRoutes.isEmpty {
                ContentUnavailableView(
                    "No saved routes",
                    systemImage: "map",
                    description: Text("Save or import a route first.")
                )
            } else {
                ForEach(session.savedRoutes) { route in
                    let safeRoute = privacySafeRoute(route)
                    shareRow(
                        icon: "map.fill",
                        title: route.title,
                        subtitle: routeSubtitle(safeRoute)
                    ) {
                        createDraft(
                            kind: .route,
                            title: route.title,
                            subtitle: routeSubtitle(safeRoute),
                            snapshot: safeRoute,
                            sourceObjectID: route.sharedSourceRouteID ?? route.id,
                            sourceOwnerID: route.sharedSourceOwnerID ?? route.ownerID
                        )
                    }
                }
            }

        case .challenge:
            if challengeStore.visibleChallenges.isEmpty {
                ContentUnavailableView(
                    "No challenges",
                    systemImage: "bolt",
                    description: Text("Create or join a challenge first.")
                )
            } else {
                ForEach(challengeStore.visibleChallenges) { challenge in
                    shareRow(
                        icon: challenge.sport.systemImage,
                        title: challenge.title,
                        subtitle: "\(challenge.sport.title) · \(challenge.rules.scoring.title)"
                    ) {
                        createDraft(
                            kind: .challenge,
                            title: challenge.title,
                            subtitle: "\(challenge.sport.title) · \(challenge.rules.scoring.title)",
                            snapshot: challenge,
                            sourceObjectID: challenge.id,
                            sourceOwnerID: challenge.creatorID
                        )
                    }
                }
            }
        }
    }

    private var shareablePlans: [TrainingPlan] {
        var result: [TrainingPlan] = []
        if let activePlan = session.activePlan {
            result.append(activePlan)
        }
        result.append(contentsOf: session.planTemplates)
        return result
    }

    private var shareableWorkouts: [PlannedSession] {
        var result = session.savedWorkoutTemplates

        if let plan = session.activePlan {
            result.append(
                contentsOf: plan.weeks
                    .flatMap(\.days)
                    .flatMap(\.sessions)
            )
        }

        var seen = Set<UUID>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private func workoutSubtitle(_ workout: PlannedSession) -> String {
        var parts: [String] = [workout.kind.title]
        if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
        }
        if !workout.exercises.isEmpty {
            parts.append("\(workout.exercises.count) exercises")
        }
        return parts.joined(separator: " · ")
    }

    private func routeSubtitle(_ route: TrainingRoute) -> String {
        var value = String(format: "%.2f km", route.distanceKilometers)
        if settings.hideRouteStartAndEnd {
            value += " · start/end hidden"
        }
        return value
    }

    private func privacySafeRoute(_ route: TrainingRoute) -> TrainingRoute {
        guard settings.hideRouteStartAndEnd,
              route.coordinates.count > 4
        else {
            return route
        }

        let trimmed = trimRoute(route.coordinates, bufferMeters: 250)
        guard trimmed.count >= 2 else { return route }

        var copy = route
        copy.coordinates = trimmed.enumerated().map { index, point in
            RouteCoordinate(
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                sequence: index
            )
        }
        copy.distanceKilometers = routeDistanceKilometers(copy.coordinates)
        copy.startName = nil
        copy.endName = nil
        return copy
    }

    private func routeDistanceKilometers(
        _ coordinates: [RouteCoordinate]
    ) -> Double {
        guard coordinates.count > 1 else { return 0 }

        return zip(coordinates, coordinates.dropFirst())
            .reduce(0) { total, pair in
                let start = CLLocation(
                    latitude: pair.0.latitude,
                    longitude: pair.0.longitude
                )
                let end = CLLocation(
                    latitude: pair.1.latitude,
                    longitude: pair.1.longitude
                )
                return total + start.distance(from: end)
            } / 1_000
    }

    private func trimRoute(
        _ coordinates: [RouteCoordinate],
        bufferMeters: CLLocationDistance
    ) -> [RouteCoordinate] {
        guard coordinates.count > 2 else { return coordinates }

        func location(_ point: RouteCoordinate) -> CLLocation {
            CLLocation(latitude: point.latitude, longitude: point.longitude)
        }

        var startIndex = 0
        var distance: CLLocationDistance = 0
        while startIndex + 1 < coordinates.count {
            distance += location(coordinates[startIndex]).distance(
                from: location(coordinates[startIndex + 1])
            )
            startIndex += 1
            if distance >= bufferMeters { break }
        }

        var endIndex = coordinates.count - 1
        distance = 0
        while endIndex - 1 > startIndex {
            distance += location(coordinates[endIndex]).distance(
                from: location(coordinates[endIndex - 1])
            )
            endIndex -= 1
            if distance >= bufferMeters { break }
        }

        guard startIndex < endIndex else { return coordinates }
        return Array(coordinates[startIndex...endIndex])
    }

    private func shareRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(ATHLTHTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "paperplane.fill")
                    .foregroundStyle(ATHLTHTheme.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private func createDraft<T: Encodable>(
        kind: MessageShareKind,
        title: String,
        subtitle: String,
        snapshot: T,
        sourceObjectID: UUID?,
        sourceOwnerID: UUID?,
        shareVersion: Int = 1
    ) {
        do {
            let draft = try MessageShareDraft(
                kind: kind,
                title: title,
                subtitle: subtitle,
                snapshot: snapshot,
                sourceObjectID: sourceObjectID,
                sourceOwnerID: sourceOwnerID,
                shareVersion: shareVersion
            )
            onSelect(draft)
        } catch {
            shareError = error.localizedDescription
        }
    }
}
