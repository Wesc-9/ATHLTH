import SwiftUI
import UIKit
import UserNotifications

private enum ATHLTHNotificationScope: String, CaseIterable, Identifiable {
    case all = "All"
    case activity = "Activity"
    case goals = "Goals"
    case social = "Social"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:
            return ATHLTHLocalization.string("All")
        case .activity:
            return ATHLTHLocalization.string("Activity")
        case .goals:
            return ATHLTHLocalization.string("Goals")
        case .social:
            return ATHLTHLocalization.string("Social")
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "sparkles"
        case .activity:
            return "figure.run"
        case .goals:
            return "target"
        case .social:
            return "person.2.fill"
        }
    }
}

struct ATHLTHNotificationCenterView: View {
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager

    @State private var selectedWorkoutImportIDs: Set<UUID> = []
    @State private var selectedScope: ATHLTHNotificationScope = .all
    @State private var permissionBannerDismissed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                scopePicker

                if shouldShowPermissionPrompt {
                    permissionCard
                        .transition(
                            .opacity.combined(
                                with: .move(edge: .top)
                            )
                        )
                }

                if shouldShowWorkoutImports {
                    workoutImportSection
                }

                inboxSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 36)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.22)
            )
        )
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if notifications.notificationCenterUnreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Read all") {
                        notifications.markAllRead()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }
        }
        .animation(
            .easeInOut(duration: 0.18),
            value: permissionBannerDismissed
        )
        .task {
            async let notificationStatus: Void =
                notifications.refreshAuthorizationStatus()
            async let workoutImports: Bool =
                health.refreshWorkoutImportInbox()
            _ = await (
                notificationStatus,
                workoutImports
            )
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 5) {
            ForEach(ATHLTHNotificationScope.allCases) { scope in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedScope = scope
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: scope.icon)
                            .font(.system(size: 10, weight: .bold))

                        Text(scope.localizedTitle)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        selectedScope == scope
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        selectedScope == scope
                            ? ATHLTHTheme.accentDeep
                            : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            ATHLTHTheme.card.opacity(0.93),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    Color.primary.opacity(0.055),
                    lineWidth: 1
                )
        }
        .shadow(
            color: Color.black.opacity(0.025),
            radius: 8,
            y: 4
        )
    }

    private var permissionCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "bell.badge.slash.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ATHLTHTheme.premiumGold)
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.champagneSoft,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            notifications.authorizationStatus == .denied
                                ? "Device alerts are disabled"
                                : "Stay in the loop"
                        )
                        .font(.headline)
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                        Text(permissionExplanation)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }

                    Spacer(minLength: 26)
                }

                Button {
                    Task {
                        await enableDeviceAlerts()
                    }
                } label: {
                    HStack {
                        Text(permissionActionTitle)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accentDeep)
            }

            Button {
                permissionBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Color.primary.opacity(0.045),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss alert prompt")
        }
        .padding(16)
        .background {
            ZStack {
                ATHLTHTheme.card.opacity(0.98)

                LinearGradient(
                    colors: [
                        ATHLTHTheme.champagneSoft.opacity(0.48),
                        .clear,
                        ATHLTHTheme.accentSoft.opacity(0.30)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.82),
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(0.04),
            radius: 14,
            y: 6
        )
    }

    private var workoutImportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Apple Health",
                subtitle:
                    health.pendingWorkoutImports.count == 1
                        ? "1 workout waiting for you"
                        : "\(health.pendingWorkoutImports.count) workouts waiting for you"
            )

            VStack(spacing: 0) {
                ForEach(
                    Array(
                        health.pendingWorkoutImports.enumerated()
                    ),
                    id: \.element.id
                ) { index, item in
                    pendingWorkoutRow(item)

                    if index <
                        health.pendingWorkoutImports.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Button(
                        selectedWorkoutImportIDs.isEmpty
                            ? "Import all"
                            : "Import selected"
                    ) {
                        let ids =
                            selectedWorkoutImportIDs.isEmpty
                                ? Set(
                                    health.pendingWorkoutImports
                                        .map(\.id)
                                )
                                : selectedWorkoutImportIDs

                        health.importPendingWorkouts(ids)
                        selectedWorkoutImportIDs.subtract(ids)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)

                    Menu {
                        if !selectedWorkoutImportIDs.isEmpty {
                            Button("Import All") {
                                health.importAllPendingWorkouts()
                                selectedWorkoutImportIDs.removeAll()
                            }

                            Button(
                                "Ignore Selected",
                                role: .destructive
                            ) {
                                let ids =
                                    selectedWorkoutImportIDs
                                health.ignorePendingWorkouts(ids)
                                selectedWorkoutImportIDs
                                    .removeAll()
                            }
                        }

                        Button(
                            "Ignore All",
                            role: .destructive
                        ) {
                            health.ignoreAllPendingWorkouts()
                            selectedWorkoutImportIDs.removeAll()
                        }
                    } label: {
                        Label(
                            "More",
                            systemImage: "ellipsis"
                        )
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
            }
            .background(
                ATHLTHTheme.card.opacity(0.97),
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.055),
                    lineWidth: 1
                )
            }
        }
    }

    @ViewBuilder
    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Inbox",
                subtitle: inboxSubtitle
            )

            if filteredNotificationItems.isEmpty &&
                !shouldShowWorkoutImports {
                emptyState
            } else if filteredNotificationItems.isEmpty {
                emptyFilteredState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredNotificationItems) { item in
                        notificationCard(item)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(
                        ATHLTHTheme.champagneSoft.opacity(0.65)
                    )
                    .frame(width: 104, height: 104)

                Circle()
                    .stroke(
                        ATHLTHTheme.accent.opacity(0.08),
                        lineWidth: 10
                    )
                    .frame(width: 82, height: 82)

                Image(systemName: "bell.fill")
                    .font(.system(size: 36, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }

            VStack(spacing: 6) {
                Text("All quiet for now")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(
                    "Completed workouts, milestones, goal updates and community activity will appear here."
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 20)
        .background(
            ATHLTHTheme.card.opacity(0.97),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.05),
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(0.03),
            radius: 14,
            y: 6
        )
    }

    private var emptyFilteredState: some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(systemName: selectedScope.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 44, height: 44)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        ATHLTHLocalization.format(
                            english: "No %@ notifications",
                            norwegian: "Ingen %@ varsler",
                            selectedScope.localizedTitle.lowercased()
                        )
                    )
                    .font(.headline)

                    Text(
                        "New updates in this category will appear here."
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()
            }
        }
    }

    private func sectionHeader(
        title: String,
        subtitle: String?
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.7)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
                        : Color.secondary.opacity(0.7)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isSelected
                    ? "Deselect workout"
                    : "Select workout"
            )

            Image(systemName: item.summary.activity.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 40, height: 40)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 12,
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

                Button(
                    "Ignore",
                    role: .destructive
                ) {
                    health.ignorePendingWorkout(item.id)
                    selectedWorkoutImportIDs.remove(item.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.primary.opacity(0.04),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func pendingWorkoutDetails(
        _ item: PendingWorkoutImport
    ) -> String {
        let summary = item.summary
        let minutes =
            max(
                Int(
                    (summary.duration / 60)
                        .rounded()
                ),
                1
            )

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
                String(
                    format: "%.2f km",
                    distance
                )
            )
        }

        return parts.joined(separator: " · ")
    }

    private var shouldShowPermissionPrompt: Bool {
        !permissionBannerDismissed &&
        (
            notifications.authorizationStatus == .notDetermined ||
            notifications.authorizationStatus == .denied
        )
    }

    private var shouldShowWorkoutImports: Bool {
        !health.pendingWorkoutImports.isEmpty &&
        (
            selectedScope == .all ||
            selectedScope == .activity
        )
    }

    private var filteredNotificationItems:
        [ATHLTHNotificationItem] {
        notifications.notificationCenterItems.filter {
            item in
            switch selectedScope {
            case .all:
                return true
            case .activity:
                return item.kind == .workoutCompleted ||
                    item.kind == .personalRecord ||
                    item.kind == .system
            case .goals:
                return item.kind == .milestoneReached ||
                    item.kind == .goalCompleted ||
                    item.kind == .achievement
            case .social:
                return item.kind == .social
            }
        }
    }

    private var inboxSubtitle: String? {
        let unread =
            filteredNotificationItems.filter(\.isUnread)
                .count

        if unread > 0 {
            return unread == 1
                ? "1 unread"
                : "\(unread) unread"
        }

        if !filteredNotificationItems.isEmpty {
            return "\(filteredNotificationItems.count) updates"
        }

        return nil
    }

    private var permissionExplanation: String {
        if notifications.authorizationStatus == .denied {
            return "Your ATHLTH inbox still works. Turn device alerts back on in iOS Settings when you want workout, goal and social updates outside the app."
        }

        return "Get workout completions, milestones, goals and important community updates without needing to keep ATHLTH open."
    }

    private var permissionActionTitle: String {
        notifications.authorizationStatus == .denied
            ? "Open iOS Settings"
            : "Enable device alerts"
    }

    @MainActor
    private func enableDeviceAlerts() async {
        if notifications.authorizationStatus == .denied {
            guard let url =
                    URL(
                        string:
                            UIApplication.openSettingsURLString
                    )
            else {
                return
            }

            await UIApplication.shared.open(url)
            return
        }

        await notifications
            .requestSystemNotificationPermission()
    }

    @ViewBuilder
    private func notificationCard(
        _ item: ATHLTHNotificationItem
    ) -> some View {
        Group {
            if hasDestination(item) {
                NavigationLink {
                    notificationDestination(item)
                        .onAppear {
                            markOpened(item)
                        }
                } label: {
                    notificationLabel(
                        item,
                        showsChevron: true
                    )
                }
            } else {
                Button {
                    markOpened(item)
                } label: {
                    notificationLabel(
                        item,
                        showsChevron: false
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.isUnread {
                Button {
                    notifications.markRead(item.id)
                } label: {
                    Label(
                        "Mark as Read",
                        systemImage: "checkmark.circle"
                    )
                }
            }

            Button(role: .destructive) {
                notifications.delete(item.id)
            } label: {
                Label(
                    "Delete",
                    systemImage: "trash"
                )
            }
        }
    }

    private func notificationLabel(
        _ item: ATHLTHNotificationItem,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconTint(item.kind))
                    .frame(width: 44, height: 44)
                    .background(
                        iconTint(item.kind).opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                if item.isUnread {
                    Circle()
                        .fill(ATHLTHTheme.vitality)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white,
                                    lineWidth: 1.5
                                )
                        }
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(
                            .subheadline.weight(
                                item.isUnread
                                    ? .bold
                                    : .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(
                        item.createdAt,
                        style: .relative
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .multilineTextAlignment(.leading)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
        }
        .padding(14)
        .background(
            ATHLTHTheme.card.opacity(
                item.isUnread ? 1.0 : 0.92
            ),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                item.isUnread
                    ? ATHLTHTheme.accent.opacity(0.12)
                    : Color.primary.opacity(0.045),
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(
                item.isUnread ? 0.035 : 0.02
            ),
            radius: 10,
            y: 4
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }

    private func hasDestination(
        _ item: ATHLTHNotificationItem
    ) -> Bool {
        if item.challengeID != nil ||
            item.goalID != nil {
            return true
        }

        if item.kind == .achievement {
            return true
        }

        switch item.socialEventKind {
        case "friend_request",
             "friend_accepted",
             "follow_request",
             "follow_accepted",
             "reaction":
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func notificationDestination(
        _ item: ATHLTHNotificationItem
    ) -> some View {
        if let challengeID = item.challengeID {
            ChallengeDetailView(
                challengeID: challengeID
            )
        } else if let goalID = item.goalID {
            GoalDetailView(
                goalID: goalID
            )
        } else if item.kind == .achievement {
            TrophyCollectionView()
        } else {
            switch item.socialEventKind {
            case "friend_request",
                 "follow_request":
                SocialHubView(
                    initialTab: .requests
                )
            case "friend_accepted",
                 "follow_accepted":
                ProfileFollowListView(
                    mode: .following
                )
            case "reaction":
                SocialHubView(
                    initialTab: .feed
                )
            default:
                SocialHubView(
                    initialTab: .feed
                )
            }
        }
    }

    private func markOpened(
        _ item: ATHLTHNotificationItem
    ) {
        notifications.markRead(item.id)

        if let backendEventID =
                item.backendEventID {
            Task {
                await social
                    .markBackendInboxRead(
                        backendEventID
                    )
            }
        }
    }

    private func iconTint(
        _ kind: ATHLTHNotificationKind
    ) -> Color {
        switch kind {
        case .workoutCompleted:
            return ATHLTHTheme.accent
        case .milestoneReached:
            return .blue
        case .goalCompleted:
            return ATHLTHTheme.vitality
        case .personalRecord:
            return .orange
        case .achievement:
            return .purple
        case .social:
            return .blue
        case .system:
            return .secondary
        }
    }
}

struct ATHLTHNotificationPermissionPrimerView: View {
    let onAllow: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.28)
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .fill(
                            ATHLTHTheme.champagneSoft.opacity(0.82)
                        )
                        .frame(width: 136, height: 136)

                    Circle()
                        .stroke(
                            ATHLTHTheme.accent.opacity(0.09),
                            lineWidth: 14
                        )
                        .frame(width: 106, height: 106)

                    Image(systemName: "bell.badge.fill")
                        .font(
                            .system(
                                size: 50,
                                weight: .medium
                            )
                        )
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                }

                VStack(spacing: 10) {
                    Text("Stay connected to your progress")
                        .font(
                            .system(
                                size: 28,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .multilineTextAlignment(.center)

                    Text(
                        "ATHLTH can let you know when a workout is ready, a goal moves forward, you reach a milestone or something important happens in your community."
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 360)
                }

                VStack(spacing: 10) {
                    permissionReason(
                        icon: "figure.run",
                        title: "Workout updates"
                    )
                    permissionReason(
                        icon: "target",
                        title: "Goals & milestones"
                    )
                    permissionReason(
                        icon: "person.2.fill",
                        title: "Important social activity"
                    )
                }
                .padding(16)
                .background(
                    ATHLTHTheme.card.opacity(0.94),
                    in: RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 22,
                        style: .continuous
                    )
                    .stroke(
                        Color.primary.opacity(0.05),
                        lineWidth: 1
                    )
                }

                Spacer()

                VStack(spacing: 10) {
                    Button(action: onAllow) {
                        Text("Allow notifications")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accentDeep)

                    Button(action: onNotNow) {
                        Text("Not now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 520)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }

    private func permissionReason(
        icon: String,
        title: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Spacer()
        }
    }
}
