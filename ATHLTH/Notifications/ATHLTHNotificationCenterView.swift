import SwiftUI
import UserNotifications

struct ATHLTHNotificationCenterView: View {
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @State private var selectedWorkoutImportIDs: Set<UUID> = []

    var body: some View {
        List {
            if shouldShowPermissionPrompt {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Device alerts are off", systemImage: "bell.slash.fill")
                            .font(.headline)

                        Text("Your ATHLTH inbox works either way. Enable device alerts if you also want milestone, goal and workout notifications outside the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Enable Alerts") {
                            Task {
                                await notifications.requestSystemNotificationPermission()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                    }
                    .padding(.vertical, 6)
                }
            }

            if !health.pendingWorkoutImports.isEmpty {
                Section("Apple Health") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            health.pendingWorkoutImports.count == 1
                                ? "New workout available"
                                : "\(health.pendingWorkoutImports.count) workouts ready to import"
                        )
                        .font(.headline)

                        Text(
                            "Workouts recorded outside ATHLTH stay here until you choose what to bring into your ATHLTH history."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    ForEach(health.pendingWorkoutImports) { item in
                        pendingWorkoutRow(item)
                    }

                    HStack(spacing: 10) {
                        Button(
                            selectedWorkoutImportIDs.isEmpty
                                ? "Import All"
                                : "Import Selected"
                        ) {
                            let ids =
                                selectedWorkoutImportIDs.isEmpty
                                    ? Set(
                                        health.pendingWorkoutImports.map(\.id)
                                    )
                                    : selectedWorkoutImportIDs

                            health.importPendingWorkouts(ids)
                            selectedWorkoutImportIDs.subtract(ids)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)

                        Menu("More") {
                            if !selectedWorkoutImportIDs.isEmpty {
                                Button("Import All") {
                                    health.importAllPendingWorkouts()
                                    selectedWorkoutImportIDs.removeAll()
                                }

                                Button(
                                    "Ignore Selected",
                                    role: .destructive
                                ) {
                                    let ids = selectedWorkoutImportIDs
                                    health.ignorePendingWorkouts(ids)
                                    selectedWorkoutImportIDs.removeAll()
                                }
                            }

                            Button(
                                "Ignore All",
                                role: .destructive
                            ) {
                                health.ignoreAllPendingWorkouts()
                                selectedWorkoutImportIDs.removeAll()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }

            if notifications.items.isEmpty &&
                health.pendingWorkoutImports.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No notifications yet",
                        systemImage: "bell",
                        description: Text("Completed workouts, reached milestones and goal updates will appear here.")
                    )
                }
            } else if !notifications.items.isEmpty {
                Section {
                    ForEach(notifications.items) { item in
                        notificationRow(item)
                            .swipeActions {
                                Button(role: .destructive) {
                                    notifications.delete(item.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if notifications.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark All Read") {
                        notifications.markAllRead()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .task {
            async let notificationStatus: Void =
                notifications.refreshAuthorizationStatus()
            async let workoutImports: Bool =
                health.refreshWorkoutImportInbox()
            _ = await (notificationStatus, workoutImports)
        }
    }

    private func pendingWorkoutRow(
        _ item: PendingWorkoutImport
    ) -> some View {
        let isSelected =
            selectedWorkoutImportIDs.contains(item.id)

        return HStack(alignment: .center, spacing: 12) {
            Button {
                if isSelected {
                    selectedWorkoutImportIDs.remove(item.id)
                } else {
                    selectedWorkoutImportIDs.insert(item.id)
                }
            } label: {
                Image(
                    systemName:
                        isSelected
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? ATHLTHTheme.accent
                        : Color.secondary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isSelected ? "Deselect workout" : "Select workout"
            )

            Image(systemName: item.summary.activity.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accent.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.summary.activity.rawValue)
                    .font(.subheadline.weight(.semibold))

                Text(pendingWorkoutDetails(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(item.sourceDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                Button("Import") {
                    health.importPendingWorkout(item.id)
                    selectedWorkoutImportIDs.remove(item.id)
                }

                Button("Ignore", role: .destructive) {
                    health.ignorePendingWorkout(item.id)
                    selectedWorkoutImportIDs.remove(item.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func pendingWorkoutDetails(
        _ item: PendingWorkoutImport
    ) -> String {
        let summary = item.summary
        let minutes = max(Int((summary.duration / 60).rounded()), 1)
        var parts = [
            summary.startDate.formatted(
                date: .abbreviated,
                time: .shortened
            ),
            "\(minutes) min"
        ]

        if let distance = summary.distanceKilometers,
           distance > 0 {
            parts.append(
                String(format: "%.2f km", distance)
            )
        }

        return parts.joined(separator: " · ")
    }

    private var shouldShowPermissionPrompt: Bool {
        notifications.authorizationStatus == .notDetermined ||
        notifications.authorizationStatus == .denied
    }

    @ViewBuilder
    private func notificationRow(_ item: ATHLTHNotificationItem) -> some View {
        if hasDestination(item) {
            NavigationLink {
                notificationDestination(item)
                    .onAppear {
                        markOpened(item)
                    }
            } label: {
                notificationLabel(item)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                markOpened(item)
            } label: {
                notificationLabel(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func notificationLabel(_ item: ATHLTHNotificationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconTint(item.kind))
                    .frame(width: 40, height: 40)
                    .background(
                        iconTint(item.kind).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                if item.isUnread {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle().stroke(.white, lineWidth: 1.5)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(item.isUnread ? .bold : .semibold))
                    .foregroundStyle(.primary)

                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
    }

    private func hasDestination(_ item: ATHLTHNotificationItem) -> Bool {
        if item.challengeID != nil || item.goalID != nil {
            return true
        }

        if item.kind == .achievement {
            return true
        }

        switch item.socialEventKind {
        case "friend_request", "friend_accepted", "reaction":
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func notificationDestination(_ item: ATHLTHNotificationItem) -> some View {
        if let challengeID = item.challengeID {
            ChallengeDetailView(challengeID: challengeID)
        } else if let goalID = item.goalID {
            GoalDetailView(goalID: goalID)
        } else if item.kind == .achievement {
            TrophyCollectionView()
        } else {
            switch item.socialEventKind {
            case "friend_request":
                SocialHubView(initialTab: .requests)
            case "friend_accepted":
                SocialHubView(initialTab: .friends)
            case "reaction":
                SocialHubView(initialTab: .feed)
            default:
                SocialHubView(initialTab: .feed)
            }
        }
    }

    private func markOpened(_ item: ATHLTHNotificationItem) {
        notifications.markRead(item.id)

        if let backendEventID = item.backendEventID {
            Task {
                await social.markBackendInboxRead(backendEventID)
            }
        }
    }

    private func iconTint(_ kind: ATHLTHNotificationKind) -> Color {
        switch kind {
        case .workoutCompleted: return ATHLTHTheme.accent
        case .milestoneReached: return .blue
        case .goalCompleted: return ATHLTHTheme.accent
        case .personalRecord: return .orange
        case .achievement: return .purple
        case .social: return .blue
        case .system: return .secondary
        }
    }
}
