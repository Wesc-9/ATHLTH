import SwiftUI
import UIKit
import UserNotifications

private enum ATHLTHNotificationScope: String, CaseIterable, Identifiable {
    case all = "All"
    case activity = "Activity"
    case challenges = "Challenges"
    case social = "Social"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:
            return ATHLTHLocalization.string("All")
        case .activity:
            return ATHLTHLocalization.string("Activity")
        case .challenges:
            return ATHLTHLocalization.string("Challenges")
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
        case .challenges:
            return "trophy.fill"
        case .social:
            return "person.2.fill"
        }
    }
}

struct ATHLTHNotificationCenterView: View {
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var challenges: ChallengeStore
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var trophies: TrophyStore

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

                        let count = unreadCount(for: scope)
                        if count > 0 {
                            Text("\(min(count, 99))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(
                                    selectedScope == scope
                                        ? ATHLTHTheme.accentDeep
                                        : Color.white
                                )
                                .frame(minWidth: 17, minHeight: 17)
                                .padding(.horizontal, count > 9 ? 2 : 0)
                                .background(
                                    selectedScope == scope
                                        ? Color.white
                                        : ATHLTHTheme.accentDeep,
                                    in: Capsule()
                                )
                        }
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
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: "Updates",
                subtitle: inboxSubtitle
            )

            if filteredNotificationItems.isEmpty &&
                !shouldShowWorkoutImports {
                emptyState
            } else if filteredNotificationItems.isEmpty {
                emptyFilteredState
            } else {
                if !actionableNotificationItems.isEmpty {
                    notificationGroup(
                        title: "Needs attention",
                        subtitle: "Requests and invites",
                        items: actionableNotificationItems,
                        emphasized: true
                    )
                }

                if !todayNotificationItems.isEmpty {
                    notificationGroup(
                        title: "Today",
                        subtitle: nil,
                        items: todayNotificationItems
                    )
                }

                if !earlierNotificationItems.isEmpty {
                    notificationGroup(
                        title: "Earlier",
                        subtitle: nil,
                        items: earlierNotificationItems
                    )
                }
            }
        }
    }

    private func notificationGroup(
        title: String,
        subtitle: String?,
        items: [ATHLTHNotificationItem],
        emphasized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.45)
                    .foregroundStyle(
                        emphasized
                            ? ATHLTHTheme.accentDeep
                            : ATHLTHTheme.mutedText
                    )

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                let unread = items.filter(\.isUnread).count
                if unread > 0 {
                    Text("\(unread) new")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            emphasized
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.mutedText
                        )
                }
            }
            .padding(.horizontal, 2)

            LazyVStack(spacing: 9) {
                ForEach(items) { item in
                    NotificationSwipeDeleteContainer(
                        onDelete: {
                            withAnimation(
                                .easeOut(duration: 0.18)
                            ) {
                                notifications.delete(
                                    item.id
                                )
                            }
                        }
                    ) {
                        notificationCard(item)
                    }
                }
            }
        }
    }

    private var actionableNotificationItems:
        [ATHLTHNotificationItem] {
        filteredNotificationItems.filter(isActionable)
    }

    private var todayNotificationItems:
        [ATHLTHNotificationItem] {
        filteredNotificationItems.filter {
            !isActionable($0) &&
            Calendar.current.isDateInToday($0.createdAt)
        }
    }

    private var earlierNotificationItems:
        [ATHLTHNotificationItem] {
        filteredNotificationItems.filter {
            !isActionable($0) &&
            !Calendar.current.isDateInToday($0.createdAt)
        }
    }

    private func isActionable(
        _ item: ATHLTHNotificationItem
    ) -> Bool {
        let eventKind =
            item.socialEventKind?.lowercased() ?? ""

        if eventKind == "friend_request" ||
            eventKind == "follow_request" {
            return followRequest(for: item) != nil
        }

        return eventKind.contains("invite")
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
                    "Important progress, personal records, challenges and social updates will appear here. Routine workout completions stay in your activity history."
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
        items(for: selectedScope)
    }

    private func items(
        for scope: ATHLTHNotificationScope
    ) -> [ATHLTHNotificationItem] {
        notifications.notificationCenterItems.filter {
            item in

            switch scope {
            case .all:
                return true

            case .activity:
                return item.kind == .personalRecord ||
                    item.kind == .milestoneReached ||
                    item.kind == .goalCompleted ||
                    item.kind == .achievement ||
                    item.kind == .system

            case .social:
                return item.kind == .social &&
                    !isChallengeItem(item)

            case .challenges:
                return isChallengeItem(item)
            }
        }
    }

    private func unreadCount(
        for scope: ATHLTHNotificationScope
    ) -> Int {
        items(for: scope)
            .filter(\.isUnread)
            .count
    }

    private func isChallengeItem(
        _ item: ATHLTHNotificationItem
    ) -> Bool {
        if item.kind == .challenge ||
            item.challengeID != nil {
            return true
        }

        let eventKind =
            item.socialEventKind?.lowercased() ?? ""
        let entityType =
            item.socialEntityType?.lowercased() ?? ""

        return eventKind.contains("challenge") ||
            entityType.contains("challenge")
    }

    private var inboxSubtitle: String? {
        let unread =
            filteredNotificationItems
                .filter(\.isUnread)
                .count

        if unread > 0 {
            return unread == 1
                ? "1 new"
                : "\(unread) new"
        }

        if !filteredNotificationItems.isEmpty {
            return "\(filteredNotificationItems.count) updates"
        }

        return nil
    }

    private var permissionExplanation: String {
        if notifications.authorizationStatus == .denied {
            return "Your ATHLTH inbox still works. Turn device alerts back on in iOS Settings when you want important progress, challenge and social updates outside the app."
        }

        return "Get personal records, milestones, challenge updates and important social activity without needing to keep ATHLTH open."
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
        if let request = followRequest(for: item) {
            VStack(spacing: 8) {
                Button {
                    markOpened(item)
                } label: {
                    notificationLabel(
                        item,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 9) {
                    Button {
                        Task {
                            await social.decline(request)
                            markOpened(item)
                        }
                    } label: {
                        Text("Decline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                Color.primary.opacity(0.045),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            await social.accept(request)
                            markOpened(item)
                        }
                    } label: {
                        Text("Accept")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                ATHLTHTheme.accentDeep,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    ATHLTHTheme.card.opacity(0.92),
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
                        Color.primary.opacity(0.045),
                        lineWidth: 1
                    )
                }
            }
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
        } else {
            Group {
                if let stageKey =
                        trophyUnlockStageKey(
                            for: item
                        ) {
                    Button {
                        markOpened(item)
                        _ = trophies
                            .presentReveal(
                                forStageKey:
                                    stageKey
                            )
                    } label: {
                        notificationLabel(
                            item,
                            showsChevron: true
                        )
                    }
                } else if hasDestination(item) {
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
                } else if isDeletedGoalNotification(item) {
                    notificationLabel(
                        item,
                        showsChevron: false
                    )
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
    }

    private func trophyUnlockStageKey(
        for item: ATHLTHNotificationItem
    ) -> String? {
        guard item.kind == .achievement else {
            return nil
        }

        let prefix = "trophy-"
        let suffix = "-unlocked"
        let key = item.eventKey

        guard key.hasPrefix(prefix),
              key.hasSuffix(suffix),
              key.count >
                prefix.count +
                suffix.count
        else {
            return nil
        }

        return String(
            key
                .dropFirst(
                    prefix.count
                )
                .dropLast(
                    suffix.count
                )
        )
    }

    private func followRequest(
        for item: ATHLTHNotificationItem
    ) -> SocialFriendRequestDisplay? {
        let eventKind =
            item.socialEventKind?.lowercased() ?? ""

        guard eventKind == "friend_request" ||
                eventKind == "follow_request",
              let entityID = item.socialEntityID
        else {
            return nil
        }

        return social.incomingRequests.first {
            $0.request.id == entityID
        }
    }

    private func notificationLabel(
        _ item: ATHLTHNotificationItem,
        showsChevron: Bool
    ) -> some View {
        let tint = notificationTint(item)

        return HStack(alignment: .top, spacing: 13) {
            notificationLeading(item, tint: tint)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(notificationCategoryTitle(item))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(tint)

                    if item.isUnread {
                        Circle()
                            .fill(tint)
                            .frame(width: 4, height: 4)
                    }

                    Spacer(minLength: 8)

                    Text(relativeTimeText(item.createdAt))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Text(item.title)
                    .font(
                        .system(
                            size: 16,
                            weight: item.isUnread
                                ? .bold
                                : .semibold
                        )
                    )
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(2)

                if !item.message
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty {
                    Text(item.message)
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                }

                if let context = challengeContextText(item) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))

                        Text(context)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(tint.opacity(0.86))
                }

                if isDeletedGoalNotification(item) {
                    HStack(spacing: 5) {
                        Image(
                            systemName:
                                "archivebox"
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold
                            )
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Goal deleted",
                                norwegian:
                                    "Målet er slettet"
                            )
                        )
                        .font(
                            .caption2
                                .weight(.medium)
                        )
                    }
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .padding(.top, 1)
                } else if isActionable(item) || showsChevron {
                    HStack(spacing: 5) {
                        Text(
                            isActionable(item)
                                ? "Review"
                                : destinationActionTitle(item)
                        )
                        .font(.caption2.weight(.semibold))

                        Image(systemName: "arrow.right")
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                    }
                    .foregroundStyle(tint)
                    .padding(.top, 1)
                }
            }
        }
        .padding(15)
        .background {
            ZStack {
                ATHLTHTheme.card.opacity(
                    item.isUnread ? 0.99 : 0.93
                )

                if item.isUnread {
                    LinearGradient(
                        colors: [
                            tint.opacity(0.055),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
        }
        .overlay(alignment: .leading) {
            if item.isUnread {
                Capsule()
                    .fill(tint.opacity(0.75))
                    .frame(width: 3, height: 38)
                    .padding(.leading, 1)
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                item.isUnread
                    ? tint.opacity(0.12)
                    : Color.primary.opacity(0.045),
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(
                item.isUnread ? 0.035 : 0.018
            ),
            radius: 10,
            y: 4
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func notificationLeading(
        _ item: ATHLTHNotificationItem,
        tint: Color
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            if let profile = notificationProfile(item) {
                SocialAvatar(
                    profile: profile,
                    size: 46
                )
            } else {
                Image(systemName: notificationIcon(item))
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(
                        tint.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
            }

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
    }

    private func notificationProfile(
        _ item: ATHLTHNotificationItem
    ) -> SocialProfileCard? {
        guard let entityID = item.socialEntityID else {
            return nil
        }

        if let request = social.incomingRequests.first(where: {
            $0.request.id == entityID
        }) {
            return request.profile
        }

        return nil
    }

    private func notificationCategoryTitle(
        _ item: ATHLTHNotificationItem
    ) -> String {
        if isChallengeItem(item) {
            return "CHALLENGE"
        }

        switch item.kind {
        case .milestoneReached,
             .goalCompleted:
            return "PROGRESS"
        case .personalRecord:
            return "PERFORMANCE"
        case .achievement:
            return "ACHIEVEMENT"
        case .social:
            return "SOCIAL"
        case .system:
            return "ATHLTH"
        case .challenge:
            return "CHALLENGE"
        case .workoutCompleted:
            return "ACTIVITY"
        }
    }

    private func notificationIcon(
        _ item: ATHLTHNotificationItem
    ) -> String {
        if isChallengeItem(item) {
            return "trophy.fill"
        }

        switch item.socialEventKind?.lowercased() {
        case "friend_request",
             "follow_request":
            return "person.crop.circle.badge.plus"
        case "friend_accepted",
             "follow_accepted":
            return "person.crop.circle.badge.checkmark"
        case "reaction":
            return "heart.fill"
        default:
            return item.kind.systemImage
        }
    }

    private func notificationTint(
        _ item: ATHLTHNotificationItem
    ) -> Color {
        if isChallengeItem(item) {
            return .orange
        }

        return iconTint(item.kind)
    }

    private func challengeContextText(
        _ item: ATHLTHNotificationItem
    ) -> String? {
        guard let challengeID = item.challengeID,
              let challenge = challenges.challenge(id: challengeID)
        else {
            return nil
        }

        let status: String
        switch challenge.status {
        case .draft:
            status = "Draft"
        case .invited:
            status = "Invitation"
        case .upcoming:
            status = "Upcoming"
        case .active:
            status = "Active"
        case .completed:
            status = "Completed"
        case .cancelled:
            status = "Cancelled"
        }

        if challenge.status == .completed ||
            challenge.status == .cancelled {
            return status
        }

        if let endsAt = challenge.rules.endsAt {
            return "\(status) · ends \(endsAt.formatted(.dateTime.day().month(.abbreviated)))"
        }

        return status
    }

    private func destinationActionTitle(
        _ item: ATHLTHNotificationItem
    ) -> String {
        if item.challengeID != nil {
            return "View challenge"
        }

        if item.goalID != nil {
            return "View goal"
        }

        if item.kind == .achievement {
            return "View trophies"
        }

        switch item.socialEventKind?.lowercased() {
        case "reaction":
            return "View activity"
        case "friend_accepted",
             "follow_accepted":
            return "View following"
        default:
            return "Open"
        }
    }

    private func relativeTimeText(
        _ date: Date
    ) -> String {
        let interval =
            max(Date().timeIntervalSince(date), 0)

        if interval < 60 {
            return "Now"
        }

        if interval < 3_600 {
            return "\(max(Int(interval / 60), 1))m"
        }

        if interval < 86_400 {
            return "\(max(Int(interval / 3_600), 1))h"
        }

        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }

        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
        )
    }

    private func hasDestination(
        _ item: ATHLTHNotificationItem
    ) -> Bool {
        if item.challengeID != nil {
            return true
        }

        if let goalID = item.goalID {
            return goals.goals.contains {
                $0.id == goalID
            }
        }

        if item.kind == .achievement ||
            isActionable(item) {
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
        } else if let goalID = item.goalID,
                  goals.goals.contains(
                    where: {
                        $0.id == goalID
                    }
                  ) {
            GoalDetailView(
                goalID: goalID
            )
        } else if item.goalID != nil {
            ContentUnavailableView(
                ATHLTHLocalization.choose(
                    english: "Goal deleted",
                    norwegian: "Målet er slettet"
                ),
                systemImage: "archivebox",
                description: Text(
                    ATHLTHLocalization.choose(
                        english:
                            "This notification belongs to a goal that no longer exists.",
                        norwegian:
                            "Dette varselet tilhører et mål som ikke finnes lenger."
                    )
                )
            )
        } else if item.kind == .achievement {
            TrophyCollectionView()
        } else {
            let eventKind =
                item.socialEventKind?.lowercased() ?? ""

            if eventKind == "friend_request" ||
                eventKind == "follow_request" ||
                eventKind.contains("workout_invite") {
                SocialHubView(
                    initialTab: .requests
                )
            } else if eventKind == "friend_accepted" ||
                eventKind == "follow_accepted" {
                ProfileFollowListView(
                    mode: .following
                )
            } else if eventKind == "reaction" {
                SocialHubView(
                    initialTab: .feed
                )
            } else if eventKind.contains("invite") ||
                eventKind.hasPrefix("group_") ||
                eventKind.contains("event") {
                ATHLTHCommunityV4View()
            } else {
                SocialHubView(
                    initialTab: .feed
                )
            }
        }
    }

    private func isDeletedGoalNotification(
        _ item: ATHLTHNotificationItem
    ) -> Bool {
        guard let goalID =
                item.goalID
        else {
            return false
        }

        return !goals.goals.contains {
            $0.id == goalID
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
        case .challenge:
            return .orange
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

private struct NotificationSwipeDeleteContainer<
    Content: View
>: View {
    let onDelete: () -> Void
    let content: () -> Content

    init(
        onDelete: @escaping () -> Void,
        @ViewBuilder content:
            @escaping () -> Content
    ) {
        self.onDelete = onDelete
        self.content = content
    }

    @State private var restingOffset:
        CGFloat = 0
    @GestureState private var dragOffset:
        CGFloat = 0

    private let revealWidth:
        CGFloat = 78

    private var effectiveOffset:
        CGFloat {
        min(
            max(
                restingOffset +
                    dragOffset,
                -revealWidth
            ),
            0
        )
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .fill(Color.red)

            Button(
                role: .destructive
            ) {
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(
                        systemName:
                            "trash.fill"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english: "Delete",
                            norwegian: "Slett"
                        )
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .semibold
                        )
                    )
                }
                .foregroundStyle(.white)
                .frame(
                    width: revealWidth
                )
                .frame(
                    maxHeight: .infinity
                )
            }
            .buttonStyle(.plain)

            content()
                .offset(
                    x: effectiveOffset
                )
                .contentShape(
                    Rectangle()
                )
                .simultaneousGesture(
                    DragGesture(
                        minimumDistance: 12
                    )
                    .updating(
                        $dragOffset
                    ) { value, state, _ in
                        guard abs(
                            value.translation.width
                        ) >
                            abs(
                                value.translation.height
                            )
                        else {
                            return
                        }

                        state =
                            value.translation.width
                    }
                    .onEnded { value in
                        guard abs(
                            value.translation.width
                        ) >
                            abs(
                                value.translation.height
                            )
                        else {
                            return
                        }

                        if value.translation.width <
                            -140 {
                            onDelete()
                            return
                        }

                        withAnimation(
                            .snappy(
                                duration: 0.18
                            )
                        ) {
                            restingOffset =
                                value.translation.width <
                                    -34
                                    ? -revealWidth
                                    : 0
                        }
                    }
                )
                .onTapGesture {
                    if restingOffset != 0 {
                        withAnimation(
                            .snappy(
                                duration: 0.16
                            )
                        ) {
                            restingOffset = 0
                        }
                    }
                }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .accessibilityAction(
            named:
                Text(
                    ATHLTHLocalization.choose(
                        english: "Delete notification",
                        norwegian: "Slett varsel"
                    )
                )
        ) {
            onDelete()
        }
    }
}
