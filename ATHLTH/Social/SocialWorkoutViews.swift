import SwiftUI

struct WorkoutFriendPicker: View {
    @EnvironmentObject private var social: SocialStore

    @Binding var selectedFriendIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Invite friends (optional)", systemImage: "person.2.fill")
                    .font(.headline)

                Spacer()

                if !selectedFriendIDs.isEmpty {
                    Text("\(selectedFriendIDs.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }
            }

            if social.friends.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(ATHLTHTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Train solo")
                            .font(.subheadline.weight(.semibold))
                        Text("Friends are optional. You can start this workout by yourself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 13) {
                        ForEach(social.friends) { friend in
                            Button {
                                if selectedFriendIDs.contains(friend.userID) {
                                    selectedFriendIDs.remove(friend.userID)
                                } else {
                                    selectedFriendIDs.insert(friend.userID)
                                }
                            } label: {
                                VStack(spacing: 7) {
                                    ZStack(alignment: .bottomTrailing) {
                                        SocialAvatar(profile: friend, size: 52)

                                        Image(
                                            systemName: selectedFriendIDs.contains(friend.userID)
                                                ? "checkmark.circle.fill"
                                                : "plus.circle.fill"
                                        )
                                        .font(.system(size: 18))
                                        .foregroundStyle(
                                            selectedFriendIDs.contains(friend.userID)
                                                ? ATHLTHTheme.accent
                                                : .secondary
                                        )
                                        .background(.white, in: Circle())
                                    }

                                    Text(friend.resolvedName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 74)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Text(
                selectedFriendIDs.isEmpty
                    ? "No invite is required to start."
                    : "Selected friends receive an invite and appear as training partners after they accept."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    var selectedFriends: [SocialProfileCard] {
        social.friends.filter { selectedFriendIDs.contains($0.userID) }
    }
}

struct QuickWorkoutStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore

    let kind: WorkoutKind
    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: ([SocialProfileCard]) -> Void

    @State private var selectedFriendIDs: Set<UUID> = []

    private var canStart: Bool {
        trainingDeviceProvider == .appleWatch && watchConnected
    }

    private var deviceStatusText: String {
        switch trainingDeviceProvider {
        case .appleWatch:
            return watchConnected
                ? "Ready to start on Apple Watch."
                : "Finish Apple Watch setup before starting this outdoor workout."
        case .garmin:
            return "Garmin is selected. Record this workout on Garmin for now; direct Garmin sync will unlock after authorization is approved."
        case .none:
            return "No watch selected. ATHLTH stays fully usable, but direct outdoor workout capture is not enabled for this quick start yet."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHCard {
                        HStack(spacing: 14) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 52, height: 52)
                                .background(ATHLTHTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.title)
                                    .font(.title2.bold())
                                Text(deviceStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }

                    if kind == .running {
                        ATHLTHCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Route")
                                        .font(.headline)
                                    Text("Optional · create or pick a saved route before you start.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                NavigationLink {
                                    RunRouteBuilderView()
                                } label: {
                                    Label("Create", systemImage: "map.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(ATHLTHTheme.accent)
                            }

                            NavigationLink {
                                SavedRoutesView()
                            } label: {
                                Label("Saved Routes", systemImage: "map")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.top, 10)
                        }
                    }

                    ATHLTHCard {
                        WorkoutFriendPicker(
                            selectedFriendIDs: $selectedFriendIDs
                        )
                    }

                    Button {
                        let selected = social.friends.filter {
                            selectedFriendIDs.contains($0.userID)
                        }
                        onStart(selected)
                        dismiss()
                    } label: {
                        Label(
                            selectedFriendIDs.isEmpty
                                ? "Start Solo"
                                : "Start with \(selectedFriendIDs.count) Friend\(selectedFriendIDs.count == 1 ? "" : "s")",
                            systemImage: "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                    .disabled(!canStart)
                }
                .padding()
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if social.friends.isEmpty {
                    await social.refresh()
                }
            }
        }
    }
}

struct HomeActivitySection: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    @State private var showingPublish = false
    @State private var selectedScope = 0

    private var circleFeed: [SocialFeedItem] {
        guard let currentUserID = social.currentUserID else {
            return social.feed
        }

        return social.feed.filter { $0.actor.userID != currentUserID }
    }

    private var ownWorkouts: [SocialPublishableWorkout] {
        let healthItems = health.workouts.map(SocialPublishableWorkout.init)

        let localStrengthItems = strength.workoutHistory
            .filter {
                $0.isFinished &&
                $0.healthMetrics.healthKitWorkoutUUID == nil
            }
            .map(SocialPublishableWorkout.init)

        return Array(
            (healthItems + localStrengthItems)
                .sorted { $0.startDate > $1.startDate }
                .prefix(3)
        )
    }

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity Center")
                        .font(.title3.weight(.bold))
                    Text("Your training and your circle, in one place.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    if selectedScope == 0 {
                        WorkoutHistoryView()
                    } else {
                        SocialHubView(initialTab: .feed)
                    }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 34, height: 34)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full activity feed")
            }

            if social.pendingRequestCount > 0 {
                NavigationLink {
                    SocialHubView(initialTab: .requests)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "bolt.badge.clock.fill")
                            .foregroundStyle(.orange)

                        Text(
                            "\(social.pendingRequestCount) need\(social.pendingRequestCount == 1 ? "s" : "") your attention"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        Color.orange.opacity(0.08),
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }

            HStack(spacing: 6) {
                activityScopeButton("You", index: 0)
                activityScopeButton("Circle", index: 1)

                Spacer()

                Button {
                    showingPublish = true
                } label: {
                    Label("Post", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ATHLTHTheme.accentDeep)
            }
            .padding(.top, 12)

            if selectedScope == 0 {
                if ownWorkouts.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run.circle")
                            .font(.title2)
                            .foregroundStyle(ATHLTHTheme.vitality)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your activity starts here")
                                .font(.subheadline.weight(.semibold))
                            Text(
                                "Your latest completed workouts will appear here automatically."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 18)
                } else {
                    VStack(spacing: 11) {
                        ForEach(ownWorkouts) { workout in
                            HomeOwnWorkoutRow(workout: workout)

                            if workout.id != ownWorkouts.last?.id {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            } else if social.isHomeFeedRefreshing &&
                        social.feed.isEmpty {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating your circle…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if circleFeed.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.circle")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.vitality)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your circle is quiet")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Add friends or check back after they share training."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 11) {
                    ForEach(Array(circleFeed.prefix(3))) { item in
                        HomeActivityRow(item: item)

                        if item.id != circleFeed.prefix(3).last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingPublish) {
            WorkoutPublishView()
        }
        .task {
            await social.refreshHomeFeed()
        }
    }

    private func activityScopeButton(
        _ title: String,
        index: Int
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedScope = index
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    selectedScope == index
                        ? ATHLTHTheme.primaryText
                        : ATHLTHTheme.mutedText
                )
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    if selectedScope == index {
                        Capsule()
                            .fill(ATHLTHTheme.cardWarm)
                            .shadow(
                                color: ATHLTHTheme.accentDeep.opacity(0.08),
                                radius: 7,
                                y: 3
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeOwnWorkoutRow: View {
    let workout: SocialPublishableWorkout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.activity.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.vitality)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.vitalitySoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                Text(workout.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    workout.startDate.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer()

            Text(workout.source)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
        }
    }
}

private struct HomeActivityRow: View {
    @EnvironmentObject private var social: SocialStore

    let item: SocialFeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            NavigationLink {
                FriendProfileView(userID: item.actor.userID)
            } label: {
                SocialAvatar(profile: item.actor, size: 38)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(item.actor.resolvedName)
                        .font(.subheadline.weight(.semibold))

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text(item.activity.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 7) {
                    Text(item.activity.title)
                        .font(.subheadline.weight(.semibold))

                    if item.activity.kind == "personal_record" {
                        Text("PR")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: Capsule()
                            )
                    }

                    if item.activity.metadata?["verification"] == "manual" {
                        Text("Manual")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color.secondary.opacity(0.10),
                                in: Capsule()
                            )
                    }
                }

                if let subtitle = item.activity.subtitle {
                    Text(subtitle)
                        .font(
                            item.activity.kind == "personal_record"
                                ? .subheadline.weight(.bold)
                                : .caption
                        )
                        .foregroundStyle(
                            item.activity.kind == "personal_record"
                                ? .primary
                                : .secondary
                        )
                }

                if let names = item.activity.metadata?["with_names"],
                   !names.isEmpty {
                    Label("with \(names)", systemImage: "person.2.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                if let caption = item.activity.metadata?["caption"],
                   !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.82))
                        .padding(.top, 1)
                }

                let reactionCount = item.reactions.count
                if reactionCount > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                        Text("\(reactionCount) reaction\(reactionCount == 1 ? "" : "s")")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: activityIcon(item.activity.kind))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
        }
    }

    private func activityIcon(_ kind: String) -> String {
        switch kind {
        case "workout": return "figure.run"
        case "trophy": return "trophy.fill"
        case "goal": return "target"
        case "challenge": return "person.2.fill"
        case "personal_record": return "bolt.fill"
        default: return "sparkles"
        }
    }
}

struct WorkoutPublishView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var selectedWorkoutID: UUID?
    @State private var visibility: ProfileVisibility = .friends
    @State private var caption = ""
    @State private var publishing = false
    @State private var selectedAlreadyPublished = false
    @State private var successMessage: String?

    private var workouts: [SocialPublishableWorkout] {
        let healthItems = health.workouts.map(SocialPublishableWorkout.init)

        let localStrengthItems = strength.workoutHistory
            .filter {
                $0.isFinished &&
                $0.healthMetrics.healthKitWorkoutUUID == nil
            }
            .map(SocialPublishableWorkout.init)

        return Array(
            (healthItems + localStrengthItems)
                .sorted { $0.startDate > $1.startDate }
                .prefix(60)
        )
    }

    private var selectedWorkout: SocialPublishableWorkout? {
        guard let selectedWorkoutID else { return nil }
        return workouts.first { $0.id == selectedWorkoutID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    if workouts.isEmpty {
                        Text("No recent workouts are available to publish.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workouts) { workout in
                            Button {
                                selectedWorkoutID = workout.id
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: workout.activity.icon)
                                        .font(.title3)
                                        .foregroundStyle(ATHLTHTheme.accent)
                                        .frame(width: 36)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(workout.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)

                                        Text(
                                            "\(workout.summaryText) · \(workout.startDate.formatted(date: .abbreviated, time: .shortened))"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        Text(workout.source)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(
                                        systemName: selectedWorkoutID == workout.id
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .foregroundStyle(
                                        selectedWorkoutID == workout.id
                                            ? ATHLTHTheme.accent
                                            : .secondary
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let workout = selectedWorkout {
                    let partners = social.acceptedTrainingPartnerNames(
                        for: workout.id
                    )

                    if !partners.isEmpty {
                        Section("Training Together") {
                            Label(
                                partners.joined(separator: ", "),
                                systemImage: "person.2.fill"
                            )
                            .foregroundStyle(ATHLTHTheme.accent)

                            Text("Only friends who accepted the training invite are attached to this post.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Post") {
                        TextField(
                            "Add a caption (optional)",
                            text: $caption,
                            axis: .vertical
                        )
                        .lineLimit(2...5)

                        Picker("Who can see this", selection: $visibility) {
                            ForEach(ProfileVisibility.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }

                        if selectedAlreadyPublished {
                            Label(
                                "This workout is already published.",
                                systemImage: "checkmark.circle.fill"
                            )
                            .foregroundStyle(ATHLTHTheme.accent)
                        }
                    }
                }

                if let successMessage {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(ATHLTHTheme.accent)
                    }
                }
            }
            .navigationTitle("Post Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        Task { await publish() }
                    }
                    .disabled(
                        selectedWorkout == nil ||
                        selectedAlreadyPublished ||
                        publishing
                    )
                }
            }
            .task {
                visibility = settings.defaultActivityVisibility

                if health.hasRequestedAuthorization && health.workouts.isEmpty {
                    await health.refreshAll()
                }
            }
            .task(id: selectedWorkoutID) {
                guard let selectedWorkoutID else {
                    selectedAlreadyPublished = false
                    return
                }

                selectedAlreadyPublished = await social.isWorkoutPublished(
                    selectedWorkoutID
                )
            }
        }
    }

    private func publish() async {
        guard let workout = selectedWorkout else { return }

        publishing = true
        defer { publishing = false }

        let success = await social.publishWorkout(
            workout,
            visibility: visibility,
            caption: caption
        )

        if success {
            selectedAlreadyPublished = true
            successMessage = "Workout published to Activity."

            try? await Task.sleep(for: .milliseconds(650))
            dismiss()
        }
    }
}
