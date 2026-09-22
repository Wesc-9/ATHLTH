import SwiftUI
import UserNotifications

struct ATHLTHNotificationCenterView: View {
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore

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
                        .tint(.green)
                    }
                    .padding(.vertical, 6)
                }
            }

            if notifications.items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No notifications yet",
                        systemImage: "bell",
                        description: Text("Completed workouts, reached milestones and goal updates will appear here.")
                    )
                }
            } else {
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
            await notifications.refreshAuthorizationStatus()
        }
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
        case .workoutCompleted: return .green
        case .milestoneReached: return .blue
        case .goalCompleted: return .green
        case .personalRecord: return .orange
        case .achievement: return .purple
        case .social: return .blue
        case .system: return .secondary
        }
    }
}
