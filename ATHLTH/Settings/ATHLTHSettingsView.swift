import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct ATHLTHSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var calendarSync: AppleCalendarSyncStore

    @State private var showingMembership = false
    @State private var healthRequestInProgress = false

    var body: some View {
        ZStack {
            settingsBackground

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.bottom, 24)

                    settingsSection("App") {
                        PremiumSettingsCard {
                            Menu {
                            ForEach(MeasurementPreference.allCases) { preference in
                                Button {
                                    settings.measurementPreference = preference
                                } label: {
                                    if settings.measurementPreference == preference {
                                        Label(preference.title, systemImage: "checkmark")
                                    } else {
                                        Text(preference.title)
                                    }
                                }
                            }
                        } label: {
                            PremiumSettingsRow(
                                icon: "ruler",
                                title: "Measurements",
                                subtitle: "Units for distance, weight and temperature"
                            ) {
                                HStack(spacing: 8) {
                                    Text(settings.measurementPreference.title)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            Menu {
                                ForEach(TimeFormatPreference.allCases) { preference in
                                    Button {
                                        settings.timeFormatPreference = preference
                                    } label: {
                                        if settings.timeFormatPreference == preference {
                                            Label(
                                                "\(preference.title) · \(preference.example)",
                                                systemImage: "checkmark"
                                            )
                                        } else {
                                            Text(
                                                "\(preference.title) · \(preference.example)"
                                            )
                                        }
                                    }
                                }
                            } label: {
                                PremiumSettingsRow(
                                    icon: "clock",
                                    title: "Time format",
                                    subtitle: "Used for times throughout ATHLTH"
                                ) {
                                    HStack(spacing: 8) {
                                        Text(settings.timeFormatPreference.title)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(
                                                ATHLTHTheme.mutedText.opacity(0.72)
                                            )
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsSection("Profile") {
                        PremiumSettingsCard {
                            NavigationLink {
                                PersonalHealthProfileView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "heart.text.square",
                                    title: "Health Profile",
                                    subtitle: "Private health details and Apple Health source"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsSection("Health & Sync") {
                        PremiumSettingsCard {
                            PremiumSettingsRow(
                                icon: "heart",
                                title: "Background Health Sync",
                                subtitle: backgroundHealthSubtitle
                            ) {
                                Toggle("", isOn: backgroundHealthSyncBinding)
                                    .labelsHidden()
                                    .tint(ATHLTHTheme.accent)
                                    .disabled(false)
                            }
                            .opacity(1)

                            SettingsDivider()

                            Button {
                                runHealthSync()
                            } label: {
                                PremiumSettingsRow(
                                    icon: healthSyncHasIssue
                                        ? "exclamationmark.triangle"
                                        : health.hasReadableHealthData
                                            ? "checkmark.circle"
                                            : "arrow.triangle.2.circlepath",
                                    iconTint: healthSyncHasIssue
                                        ? .orange
                                        : ATHLTHTheme.accentDeep,
                                    title: "Sync status",
                                    subtitle: healthSyncStatusText
                                ) {
                                    connectionTrailing(
                                        health.isRefreshing
                                            ? "Syncing"
                                            : health.hasRequestedAuthorization
                                                ? "Sync now"
                                                : "Connect",
                                        showChevron: false,
                                        loading: health.isRefreshing || healthRequestInProgress
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(health.isRefreshing || healthRequestInProgress)
                        }
                    }

                    settingsSection("Connections") {
                        PremiumSettingsCard {
                            Button {
                                handleAppleHealthTap()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "heart.fill",
                                    iconTint: .pink,
                                    iconBackground: Color.pink.opacity(0.10),
                                    title: "Apple Health",
                                    subtitle: appleHealthConnectionSubtitle
                                ) {
                                    connectionTrailing(
                                        health.isRefreshing
                                            ? "Syncing"
                                            : !health.hasRequestedAuthorization
                                                ? "Connect"
                                                : health.hasReadableHealthData
                                                    ? "Connected"
                                                    : "Configured",
                                        showChevron: true,
                                        loading: healthRequestInProgress
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(healthRequestInProgress)

                            SettingsDivider()

                            if session.subscriptionAccess.hasPaidAccess {
                                NavigationLink {
                                    AppleCalendarSettingsView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "calendar",
                                        iconTint: .red,
                                        iconBackground: Color.red.opacity(0.09),
                                        title: "Calendar",
                                        subtitle: appleCalendarConnectionSubtitle
                                    ) {
                                        connectionTrailing(
                                            calendarSync.isSyncing
                                                ? "Syncing"
                                                : calendarSync.isEnabled
                                                    ? "On"
                                                    : calendarSync.hasFullAccess
                                                        ? "Ready"
                                                        : "Connect",
                                            showChevron: true,
                                            loading: calendarSync.isSyncing
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    showingMembership = true
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "calendar",
                                        iconTint: .red,
                                        iconBackground: Color.red.opacity(0.09),
                                        title: "Calendar",
                                        subtitle:
                                            "ATHLTH+ · sync your training plan to Calendar"
                                    ) {
                                        HStack(spacing: 7) {
                                            Text("ATHLTH+")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(
                                                    ATHLTHTheme.premiumGold
                                                )

                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(
                                                    ATHLTHTheme.mutedText
                                                        .opacity(0.72)
                                                )
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHTrainingDeviceSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: settings.trainingDeviceProvider.systemImage,
                                    iconTint: ATHLTHTheme.primaryText,
                                    title: "Training device",
                                    subtitle: trainingDeviceSubtitle
                                ) {
                                    connectionTrailing(
                                        settings.trainingDeviceProvider.title,
                                        showChevron: true
                                    )
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            PremiumSettingsRow(
                                icon: "music.note",
                                iconTint: spotifyGreen,
                                iconBackground: spotifyGreen.opacity(0.12),
                                title: "Spotify",
                                subtitle: "Spotify integration is planned"
                            ) {
                                Text("Planned")
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            SettingsDivider()

                            PremiumSettingsRow(
                                icon: "house",
                                iconTint: Color(red: 0.12, green: 0.58, blue: 0.86),
                                iconBackground: Color(red: 0.12, green: 0.58, blue: 0.86).opacity(0.11),
                                title: "Home Assistant",
                                subtitle: "Home Assistant integration is planned"
                            ) {
                                Text("Planned")
                                    .font(.subheadline)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }

                    settingsSection("Preferences") {
                        PremiumSettingsCard {
                            NavigationLink {
                                ATHLTHTrainingSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "figure.strengthtraining.traditional",
                                    title: "Training",
                                    subtitle: "Workout device, strength tracking and publishing"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHAudioCoachSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "waveform.and.mic",
                                    iconTint: ATHLTHTheme.premiumGold,
                                    iconBackground:
                                        ATHLTHTheme.premiumGoldSoft,
                                    title: "Audio Coach",
                                    subtitle:
                                        "ATHLTH+ · voice, language, pace and route updates"
                                ) {
                                    HStack(spacing: 7) {
                                        Text("ATHLTH+")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(
                                                ATHLTHTheme.premiumGold
                                            )
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(
                                                ATHLTHTheme.mutedText
                                                    .opacity(0.72)
                                            )
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHNotificationSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "bell",
                                    title: "Notifications",
                                    subtitle: notificationSummary
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsSection("Language") {
                        PremiumSettingsCard {
                            PremiumSettingsRow(
                            icon: "globe",
                            title: "Language",
                            subtitle: "More languages are planned"
                        ) {
                                Text("English")
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }

                    settingsSection("Membership") {
                        PremiumSettingsCard {
                            Button {
                                showingMembership = true
                            } label: {
                                PremiumSettingsRow(
                                    icon: "crown.fill",
                                    iconTint: ATHLTHTheme.premiumGold,
                                    iconBackground: ATHLTHTheme.premiumGoldSoft,
                                    title: "Plan",
                                    subtitle: "Your current plan"
                                ) {
                                    HStack(spacing: 8) {
                                        Text(session.subscriptionAccess.displayTitle)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            if let billingPeriod = session.subscriptionAccess.billingPeriodTitle {
                                SettingsDivider()
                                PremiumSettingsRow(
                                    icon: "creditcard",
                                    title: "Billing",
                                    subtitle: "Your billing cycle"
                                ) {
                                    Text(billingPeriod)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                            }

                            if session.subscriptionAccess.trialIsActive,
                               let trialEndsAt = session.subscriptionAccess.trialEndsAt {
                                SettingsDivider()
                                PremiumSettingsRow(
                                    icon: "calendar",
                                    title: "7-day trial ends",
                                    subtitle: "Keep going. You’re almost there."
                                ) {
                                    Text(trialEndsAt.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                        .multilineTextAlignment(.trailing)
                                }
                            }

                            if let periodEndsAt = session.subscriptionAccess.currentPeriodEndsAt {
                                switch session.subscriptionAccess.lifecycleState {
                                case .active:
                                    SettingsDivider()
                                    PremiumSettingsRow(
                                        icon: "calendar.badge.clock",
                                        title: "Current period",
                                        subtitle: "Your current ATHLTH+ access"
                                    ) {
                                        Text(periodEndsAt.formatted(date: .abbreviated, time: .omitted))
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                case .expired:
                                    SettingsDivider()
                                    PremiumSettingsRow(
                                        icon: "calendar.badge.exclamationmark",
                                        title: "Access ended",
                                        subtitle: "Your ATHLTH+ access has ended"
                                    ) {
                                        Text(periodEndsAt.formatted(date: .abbreviated, time: .omitted))
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                default:
                                    EmptyView()
                                }
                            }

                            SettingsDivider()

                            Button {
                                Task {
                                    _ = await subscriptionStore.restorePurchases()
                                }
                            } label: {
                                PremiumSettingsRow(
                                    icon: "arrow.counterclockwise",
                                    title: "Restore Purchases",
                                    subtitle: "Restore your ATHLTH+ purchase"
                                ) {
                                    if subscriptionStore.restoreInProgress {
                                        ProgressView()
                                            .tint(ATHLTHTheme.accent)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(subscriptionStore.restoreInProgress)

                            if session.subscriptionAccess.hasPaidAccess {
                                SettingsDivider()

                                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                                    PremiumSettingsRow(
                                        icon: "creditcard",
                                        title: "Manage Subscription",
                                        subtitle: "Open Apple subscription settings"
                                    ) {
                                        Image(systemName: "arrow.up.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if let errorMessage = subscriptionStore.errorMessage {
                                SettingsDivider()
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                        }
                    }

                    settingsSection("Account") {
                        PremiumSettingsCard {
                            NavigationLink {
                                ATHLTHAccountSecurityView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "person.badge.key",
                                    title: "Account & Security",
                                    subtitle: "Sign-in, password, export and account controls"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsSection("About") {
                        PremiumSettingsCard {
                            Link(destination: URL(string: "https://repdb.co")!) {
                                PremiumSettingsRow(
                                    icon: "figure.strengthtraining.traditional",
                                    title: "Exercise data",
                                    subtitle: "Exercise catalog powered by RepDB"
                                ) {
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                LegalDocumentView(kind: .terms)
                            } label: {
                                PremiumSettingsRow(
                                    icon: "doc.text",
                                    title: "Terms of Service",
                                    subtitle: "Read the ATHLTH terms"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                LegalDocumentView(kind: .privacy)
                            } label: {
                                PremiumSettingsRow(
                                    icon: "lock.shield",
                                    title: "Privacy Policy",
                                    subtitle: "How ATHLTH handles your data"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if session.currentRole.canAccessControlCenter {
                        settingsSection("Support") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    ATHLTHSystemDiagnosticsView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "stethoscope",
                                        title: "System Diagnostics",
                                        subtitle: "Health, Watch, push, account and build status"
                                    ) {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    #if DEBUG
                    if session.currentRole.canAccessControlCenter {
                        settingsSection("Admin") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    AdminCenterView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "lock.rectangle.stack",
                                        title: "Control Center",
                                        subtitle: "Development preview · not production data"
                                    ) {
                                        HStack(spacing: 8) {
                                            Text(session.currentRole.title)
                                                .font(.subheadline)
                                                .foregroundStyle(ATHLTHTheme.mutedText)
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if session.previewModeEnabled || session.currentRole.canAccessControlCenter {
                        settingsSection("Developer") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    CapabilityLabView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "testtube.2",
                                        title: "Capability Lab",
                                        subtitle: "Run low-level Health and capability tests"
                                    ) {
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    #endif

                    Text("ATHLTH \(appVersion) · Progress lives here.")
                        .font(.caption2.weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                        .padding(.top, 6)
                        .padding(.bottom, 34)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingMembership) {
            SubscriptionOfferView {
                showingMembership = false
            }
        }
        .task {
            await notifications.refreshAuthorizationStatus()

            if health.hasRequestedAuthorization,
               health.lastSuccessfulRefreshAt == nil,
               !health.isRefreshing {
                health.resumeUserInitiatedHealthSync()
                await health.configureBackgroundSync(
                    allowed: settings.backgroundHealthSyncEnabled
                )
                await health.refreshAll()
            }
        }
    }

    private var settingsBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    ATHLTHTheme.premiumGold.opacity(0.055),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 7) {
                ATHLTHBrandMark(size: .compact)
                    .scaleEffect(0.78)

                Text("Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(ATHLTHTheme.primaryText)
            }
            .padding(.top, 8)

            HStack(alignment: .top) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.86), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(ATHLTHTheme.border, lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.035), radius: 14, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                Text("A healthier\nyou, further")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.70))
                    .multilineTextAlignment(.trailing)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(2.8)
                .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                .padding(.leading, 16)

            content()
        }
        .padding(.bottom, 24)
    }

    private var privacySummary: String {
        let profileTitle: String
        if let raw = social.privacy?.profileVisibility,
           let visibility = ProfileVisibility(rawValue: raw) {
            profileTitle = visibility.title
        } else {
            profileTitle = settings.profileVisibility.title
        }

        let routeTitle = settings.hideRouteStartAndEnd
            ? "route endpoints hidden"
            : "full routes"

        return "\(profileTitle) profile · \(routeTitle)"
    }

    private var trainingDeviceSubtitle: String {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return watchConnection.isReady
                ? "Apple Watch connected"
                : watchConnection.statusText
        case .garmin:
            return "Garmin Connect prepared · authorization pending"
        case .none:
            return "ATHLTH works without a watch"
        }
    }

    private var notificationSummary: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "System notifications allowed · choose what ATHLTH sends"
        case .denied:
            return "System notifications are disabled in iOS Settings"
        case .notDetermined:
            return "System notification permission has not been requested"
        @unknown default:
            return "Review notification preferences"
        }
    }

    private var healthSyncHasIssue: Bool {
        let backgroundIssue = !(health.backgroundSyncError?.isEmpty ?? true)
        let readIssue = !(health.authorizationError?.isEmpty ?? true)
        return backgroundIssue || readIssue
    }

    private var healthSyncStateTitle: String {
        guard settings.backgroundHealthSyncEnabled else {
            return "Off"
        }
        if health.isRefreshing {
            return "Syncing"
        }
        if !health.hasRequestedAuthorization {
            return "Not connected"
        }
        if healthSyncHasIssue {
            return "Issue"
        }
        if health.lastSuccessfulRefreshAt != nil && !health.hasTrainingHealthData {
            return health.personalDetails.hasAnyValue ? "Profile only" : "No data"
        }
        if health.lastSuccessfulRefreshAt != nil &&
            health.hasTrainingHealthData &&
            !health.canWriteWorkouts {
            return "Read only"
        }
        return health.lastSuccessfulRefreshAt != nil ? "Synced" : "Ready"
    }

    private var healthSyncStatusText: String {
        if health.isRefreshing {
            return "Reading workouts, activity, sleep, heart data and profile values from Apple Health."
        }

        if let error = health.backgroundSyncError, !error.isEmpty {
            return "Background sync needs attention: \(error)"
        }

        if let error = health.authorizationError, !error.isEmpty {
            return "Apple Health read needs attention: \(error)"
        }

        guard health.hasRequestedAuthorization else {
            return "Apple Health is not connected yet. Tap here to connect."
        }

        if let lastRefresh = health.lastSuccessfulRefreshAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: lastRefresh, relativeTo: Date())

            if health.hasTrainingHealthData {
                if health.canWriteWorkouts {
                    return "Apple Health training data imported successfully. Last synced \(relative)."
                }

                return "Apple Health data was imported \(relative), but workout write access is off. Tap Sync now to review Health permissions."
            }

            if health.personalDetails.hasAnyValue {
                return "Apple Health profile values were imported, but ATHLTH found no readable workouts, activity, sleep or heart data. Review Health read access, then tap Sync now."
            }

            return "Apple Health responded, but ATHLTH found no readable compatible data. Review Health read access, then tap Sync now."
        }

        return settings.backgroundHealthSyncEnabled
            ? "Apple Health is configured. Tap Sync now to perform the first full import."
            : "Apple Health is configured. Background sync is off, but you can still tap Sync now."
    }

    private var backgroundHealthSyncBinding: Binding<Bool> {
        Binding(
            get: {
                settings.backgroundHealthSyncEnabled
            },
            set: { enabled in
                settings.backgroundHealthSyncEnabled = enabled
            }
        )
    }

    private var backgroundHealthSubtitle: String {
        "Sync with Apple Health automatically in the background."
    }

    private var appleHealthConnectionSubtitle: String {
        guard health.hasRequestedAuthorization else {
            return "Connect your Apple Health data"
        }

        if health.isRefreshing {
            return "Reading Apple Health data now"
        }

        if health.hasTrainingHealthData {
            return health.canWriteWorkouts
                ? "Connected · training and health data is available"
                : "Connected for reading · workout write access is off"
        }

        if health.personalDetails.hasAnyValue {
            return "Configured · profile values available, no training data yet"
        }

        if health.lastSuccessfulRefreshAt != nil {
            return "Permission configured · no readable data found yet"
        }

        return "Permission configured · run the first sync"
    }

    private var appleCalendarConnectionSubtitle: String {
        if calendarSync.isEnabled {
            return "Training plan sync · ATHLTH calendar"
        }

        if calendarSync.hasFullAccess {
            return "Calendar connected · training plan sync is off"
        }

        return "Sync planned workouts to a dedicated ATHLTH calendar"
    }

    private var spotifyGreen: Color {
        Color(red: 0.12, green: 0.72, blue: 0.35)
    }

    @ViewBuilder
    private func connectionTrailing(
        _ text: String,
        showChevron: Bool,
        loading: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView()
                    .tint(ATHLTHTheme.accent)
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
            }
        }
    }

    private func handleAppleHealthTap() {
        if health.hasRequestedAuthorization {
            runHealthSync()
            return
        }

        Task {
            healthRequestInProgress = true
            await health.requestAuthorization()
            await health.completeAuthorizationSetup()
            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
            healthRequestInProgress = false
        }
    }

    private func runHealthSync() {
        guard health.hasRequestedAuthorization else {
            handleAppleHealthTap()
            return
        }

        Task {
            healthRequestInProgress = true
            await health.requestAuthorization()
            await health.completeAuthorizationSetup()
            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
            healthRequestInProgress = false
        }
    }

    private func syncHealthProfileFromAppleHealthIfAppropriate() {
        guard health.personalDetails.hasAnyValue else {
            return
        }

        session.mergePersonalDetailsFromAppleHealth(
            health.personalDetails
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct AppleCalendarSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var calendarSync: AppleCalendarSyncStore

    @State private var showingRemoveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("CALENDAR")

                    PremiumSettingsCard {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 46, height: 46)
                                .background(
                                    Color.red.opacity(0.09),
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("ATHLTH Calendar")
                                    .font(.headline)
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(calendarSync.authorizationTitle)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            if calendarSync.isSyncing {
                                ProgressView()
                                    .tint(ATHLTHTheme.accent)
                            } else {
                                Image(
                                    systemName:
                                        calendarSync.hasFullAccess
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                )
                                .font(.title3)
                                .foregroundStyle(
                                    calendarSync.hasFullAccess
                                        ? ATHLTHTheme.accentDeep
                                        : Color.secondary.opacity(0.45)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        SettingsDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sync Training Plan")
                                    .font(.system(size: 16.5, weight: .medium))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text("Keep your active ATHLTH plan in Calendar.")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            Toggle(
                                "",
                                isOn: calendarSyncBinding
                            )
                            .labelsHidden()
                            .tint(ATHLTHTheme.accent)
                            .disabled(calendarSync.isSyncing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("SYNC STATUS")

                    PremiumSettingsCard {
                        statusRow(
                            title: "Calendar",
                            value: calendarSync.calendarExists
                                ? calendarSync.calendarName
                                : "Not created",
                            icon: "calendar.badge.checkmark"
                        )

                        SettingsDivider()

                        statusRow(
                            title: "Last sync",
                            value: lastSyncText,
                            icon: "arrow.triangle.2.circlepath"
                        )

                        SettingsDivider()

                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Default workout time")
                                    .font(.subheadline.weight(.medium))

                                Text(
                                    "Used only when the workout time is set to “–”."
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            DatePicker(
                                "",
                                selection: defaultCalendarTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        SettingsDivider()

                        Button {
                            Task {
                                if calendarSync.hasFullAccess {
                                    await calendarSync.sync(
                                        plan: session.activePlan
                                    )
                                } else {
                                    await calendarSync.enable(
                                        plan: session.activePlan
                                    )
                                }
                            }
                        } label: {
                            HStack {
                                Label(
                                    calendarSync.hasFullAccess
                                        ? "Sync Now"
                                        : "Connect Calendar",
                                    systemImage: calendarSync.hasFullAccess
                                        ? "arrow.triangle.2.circlepath"
                                        : "calendar.badge.plus"
                                )
                                .font(.subheadline.weight(.semibold))

                                Spacer()

                                if calendarSync.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                            }
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .disabled(calendarSync.isSyncing)

                        if calendarPermissionNeedsSettings {
                            SettingsDivider()

                            Button {
                                if let url = URL(
                                    string: UIApplication.openSettingsURLString
                                ) {
                                    openURL(url)
                                }
                            } label: {
                                HStack {
                                    Label(
                                        "Open iOS Settings",
                                        systemImage: "gear"
                                    )
                                    .font(.subheadline.weight(.semibold))

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.bold())
                                }
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("HOW IT WORKS")

                    ATHLTHCard {
                        VStack(alignment: .leading, spacing: 14) {
                            calendarInfoRow(
                                icon: "clock",
                                title: "Planned time",
                                text:
                                    "Workouts with a time use that exact start time and planned duration."
                            )

                            Divider()

                            calendarInfoRow(
                                icon: "calendar.day.timeline.left",
                                title: "No time set",
                                text:
                                    "A workout with “–” uses your default Calendar time (18:00 initially). A time set on the workout always takes priority."
                            )

                            Divider()

                            calendarInfoRow(
                                icon: "arrow.triangle.2.circlepath",
                                title: "Automatic updates",
                                text:
                                    "Adding, editing or removing workouts in the active plan updates the ATHLTH calendar automatically."
                            )

                            Divider()

                            calendarInfoRow(
                                icon: "arrow.right",
                                title: "One-way sync",
                                text:
                                    "ATHLTH remains the source of truth. Changes made directly in Calendar do not edit your training plan."
                            )
                        }
                    }
                }

                if calendarSync.calendarExists {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("CALENDAR")

                        PremiumSettingsCard {
                            Button(role: .destructive) {
                                showingRemoveConfirmation = true
                            } label: {
                                HStack {
                                    Label(
                                        "Remove ATHLTH Calendar",
                                        systemImage: "trash"
                                    )
                                    .font(.subheadline.weight(.semibold))

                                    Spacer()
                                }
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(
                            "Turning sync off keeps the calendar and its current events. Removing the calendar deletes the dedicated ATHLTH calendar."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 80)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            calendarSync.refreshAuthorizationStatus()

            guard session.subscriptionAccess.hasPaidAccess else {
                return
            }

            if calendarSync.isEnabled {
                await calendarSync.syncIfEnabled(
                    plan: session.activePlan
                )
            }
        }
        .confirmationDialog(
            "Remove ATHLTH Calendar?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Remove Calendar",
                role: .destructive
            ) {
                Task {
                    await calendarSync.removeATHLTHCalendar()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the dedicated ATHLTH calendar and all workout events synced into it. Your ATHLTH training plan is not changed."
            )
        }
        .alert(
            "Calendar",
            isPresented: Binding(
                get: {
                    calendarSync.errorMessage != nil
                },
                set: { visible in
                    if !visible {
                        calendarSync.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                calendarSync.errorMessage ??
                "Calendar could not be updated."
            )
        }
    }

    private var defaultCalendarTimeBinding: Binding<Date> {
        Binding(
            get: {
                calendarSync.defaultStartTime
            },
            set: { newTime in
                guard session.subscriptionAccess.hasPaidAccess else {
                    return
                }

                calendarSync.setDefaultStartTime(
                    newTime
                )

                guard calendarSync.isEnabled else {
                    return
                }

                Task {
                    await calendarSync.sync(
                        plan: session.activePlan
                    )
                }
            }
        )
    }

    private var calendarSyncBinding: Binding<Bool> {
        Binding(
            get: {
                calendarSync.isEnabled
            },
            set: { enabled in
                guard session.subscriptionAccess.hasPaidAccess else {
                    return
                }

                if enabled {
                    Task {
                        await calendarSync.enable(
                            plan: session.activePlan
                        )
                    }
                } else {
                    calendarSync.disable()
                }
            }
        )
    }

    private var calendarPermissionNeedsSettings: Bool {
        switch calendarSync.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    private var lastSyncText: String {
        guard let date = calendarSync.lastSyncedAt else {
            return "Never"
        }

        return date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private func sectionTitle(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(2.4)
            .foregroundStyle(
                ATHLTHTheme.accentDeep.opacity(0.82)
            )
            .padding(.leading, 16)
    }

    private func statusRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 32)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func calendarInfoRow(
        icon: String,
        title: String,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 32, height: 32)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer()
        }
    }
}

private struct PremiumSettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            ATHLTHTheme.card,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 20, x: 0, y: 10)
    }
}

private struct PremiumSettingsRow<Trailing: View>: View {
    let icon: String
    var iconTint: Color = ATHLTHTheme.primaryText
    var iconBackground: Color = ATHLTHTheme.accentSoft
    let title: String
    let subtitle: String?
    var titleColor: Color = ATHLTHTheme.primaryText
    @ViewBuilder let trailing: Trailing

    init(
        icon: String,
        iconTint: Color = ATHLTHTheme.primaryText,
        iconBackground: Color = ATHLTHTheme.accentSoft,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = ATHLTHTheme.primaryText,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.iconBackground = iconBackground
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 44, height: 44)
                .background(
                    iconBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, 74)
            .padding(.trailing, 16)
    }
}

private struct ATHLTHTrainingDeviceSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PRIMARY TRAINING DEVICE")
                        .font(.caption.weight(.semibold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                        .padding(.leading, 16)

                    PremiumSettingsCard {
                        deviceRow(.appleWatch)

                        SettingsDivider()

                        deviceRow(.garmin)

                        SettingsDivider()

                        deviceRow(.none)
                    }
                }

                selectedDeviceDetails

                VStack(alignment: .leading, spacing: 10) {
                    Text("WORKOUT CAPTURE")
                        .font(.caption.weight(.semibold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                        .padding(.leading, 16)

                    PremiumSettingsCard {
                        HStack(spacing: 14) {
                            Image(systemName: "record.circle")
                                .font(.system(size: 20, weight: .medium))
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
                                Text("Preferred workout device")
                                    .font(.system(size: 16.5, weight: .semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(workoutCaptureSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)

                            Picker(
                                "Preferred workout device",
                                selection: $settings.preferredWorkoutCapture
                            ) {
                                Text("Automatic")
                                    .tag(WorkoutCapturePreference.automatic)
                                Text("iPhone")
                                    .tag(WorkoutCapturePreference.iPhone)

                                if settings.trainingDeviceProvider == .appleWatch {
                                    Text("Apple Watch")
                                        .tag(WorkoutCapturePreference.appleWatch)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 48)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    Color.white,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Training Device")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if settings.trainingDeviceProvider == .appleWatch {
                watchConnection.connect()
            }
        }
        .onChange(of: settings.trainingDeviceProvider) { _, provider in
            if provider != .appleWatch,
               settings.preferredWorkoutCapture == .appleWatch {
                settings.preferredWorkoutCapture = .iPhone
            }
        }
    }

    private func deviceRow(
        _ provider: TrainingDeviceProvider
    ) -> some View {
        Button {
            select(provider)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: provider.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        settings.trainingDeviceProvider == provider
                            ? ATHLTHTheme.accentDeep
                            : ATHLTHTheme.mutedText
                    )
                    .frame(width: 44, height: 44)
                    .background(
                        providerIconBackground(provider),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.title)
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(
                                provider == .garmin
                                    ? ATHLTHTheme.mutedText
                                    : ATHLTHTheme.primaryText
                            )
                            .lineLimit(1)
                            .layoutPriority(1)

                        if provider == .garmin {
                            Text("COMING SOON")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.7)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Color.primary.opacity(0.045),
                                    in: Capsule()
                                )
                                .fixedSize()
                        }
                    }

                    Text(deviceSubtitle(provider))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(
                    systemName:
                        settings.trainingDeviceProvider == provider
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(
                    settings.trainingDeviceProvider == provider
                        ? ATHLTHTheme.accentDeep
                        : Color.secondary.opacity(0.42)
                )
                .frame(width: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(provider == .garmin)
        .opacity(provider == .garmin ? 0.72 : 1)
    }

    @ViewBuilder
    private var selectedDeviceDetails: some View {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            VStack(alignment: .leading, spacing: 10) {
                Text("APPLE WATCH SETUP")
                    .font(.caption.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                    .padding(.leading, 16)

                PremiumSettingsCard {
                    VStack(alignment: .leading, spacing: 0) {
                        detailRow(
                            title: "Connection",
                            value: watchConnectionTitle,
                            icon: "applewatch"
                        )

                        SettingsDivider()

                        detailRow(
                            title: "Watch app",
                            value: watchAppTitle,
                            icon: watchConnection.isReady
                                ? "checkmark.circle.fill"
                                : "app.badge"
                        )

                        SettingsDivider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text(watchSetupDetail)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)

                            NavigationLink {
                                AppleWatchConnectionView()
                            } label: {
                                HStack {
                                    Label(
                                        watchConnection.isReady
                                            ? "Open Apple Watch details"
                                            : watchConnection.state == .appNotInstalled
                                                ? "Install Watch app"
                                                : "Open setup",
                                        systemImage: "applewatch"
                                    )
                                    .font(.subheadline.weight(.semibold))

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .padding(.horizontal, 14)
                                .frame(height: 46)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                    }
                }
            }

        case .none:
            VStack(alignment: .leading, spacing: 10) {
                Text("IPHONE & APPLE HEALTH")
                    .font(.caption.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                    .padding(.leading, 16)

                PremiumSettingsCard {
                    HStack(spacing: 14) {
                        Image(systemName: "iphone")
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 44, height: 44)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("No watch required")
                                .font(.headline)
                            Text(
                                "ATHLTH can still use your iPhone and available Apple Health data. You can connect a watch later."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(16)
                }
            }

        case .garmin:
            EmptyView()
        }
    }

    private func detailRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .frame(width: 32)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(
                    value == "Not installed" ||
                    value == "Not paired" ||
                    value == "Unavailable"
                        ? Color.orange
                        : ATHLTHTheme.mutedText
                )
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var watchConnectionTitle: String {
        switch watchConnection.state {
        case .ready, .appNotInstalled:
            return "Paired"
        case .notPaired:
            return "Not paired"
        case .checking:
            return "Checking…"
        case .unsupported:
            return "Unavailable"
        }
    }

    private var watchAppTitle: String {
        switch watchConnection.state {
        case .ready:
            return "Installed"
        case .appNotInstalled:
            return "Not installed"
        case .notPaired:
            return "Unavailable"
        case .checking:
            return "Checking…"
        case .unsupported:
            return "Unavailable"
        }
    }

    private var watchSetupDetail: String {
        switch watchConnection.state {
        case .ready:
            return "ATHLTH Watch is ready for live workouts, routes and HealthKit sync."
        case .appNotInstalled:
            return "Install the ATHLTH Watch app to start workouts, sync routes and use live tracking."
        case .notPaired:
            return "Pair an Apple Watch with this iPhone first, then return here to finish ATHLTH setup."
        case .checking:
            return "ATHLTH is checking the paired Apple Watch and app installation."
        case .unsupported:
            return "Apple Watch connectivity is unavailable on this device."
        }
    }

    private func providerIconBackground(
        _ provider: TrainingDeviceProvider
    ) -> Color {
        if provider == .garmin {
            return Color.primary.opacity(0.035)
        }

        return settings.trainingDeviceProvider == provider
            ? ATHLTHTheme.accentSoft
            : Color.primary.opacity(0.035)
    }

    private var workoutCaptureSubtitle: String {
        switch settings.preferredWorkoutCapture {
        case .automatic:
            return settings.trainingDeviceProvider == .appleWatch
                ? "ATHLTH chooses between iPhone and Apple Watch based on workout and availability."
                : "ATHLTH uses iPhone capture when no supported watch is active."
        case .iPhone:
            return "New workouts default to iPhone capture."
        case .appleWatch:
            return "New workouts default to Apple Watch when it is available."
        }
    }

    private func select(_ provider: TrainingDeviceProvider) {
        guard provider != .garmin else { return }

        settings.trainingDeviceProvider = provider

        if provider == .none {
            settings.preferredWorkoutCapture = .iPhone
            settings.watchConnected = false
        } else if provider != .appleWatch,
                  settings.preferredWorkoutCapture == .appleWatch {
            settings.preferredWorkoutCapture = .iPhone
        }

        if provider == .appleWatch {
            watchConnection.connect()
        }
    }

    private func deviceSubtitle(
        _ provider: TrainingDeviceProvider
    ) -> String {
        switch provider {
        case .appleWatch:
            switch watchConnection.state {
            case .ready:
                return "Paired · ATHLTH Watch app installed"
            case .appNotInstalled:
                return "Paired · Watch app needs installation"
            case .notPaired:
                return "No paired Apple Watch found"
            case .checking:
                return "Checking Apple Watch…"
            case .unsupported:
                return "Apple Watch unavailable"
            }

        case .garmin:
            return "Garmin Connect integration will be available later"

        case .none:
            return "Use ATHLTH with iPhone and Apple Health"
        }
    }
}

private struct GarminConnectionSetupView: View {
    var body: some View {
        Form {
            Section("Garmin Connect") {
                Label("Garmin integration is coming soon", systemImage: "watch.analog")
                    .font(.headline)

                Text(
                    "When Garmin access is enabled, this screen will guide you through account authorization, permissions and the data ATHLTH can sync."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Planned sync") {
                Label("Workouts and routes", systemImage: "figure.run")
                Label("Heart rate and HRV", systemImage: "heart.fill")
                Label("Sleep and recovery", systemImage: "moon.fill")
                Label("Steps and activity", systemImage: "figure.walk")
            }
        }
        .navigationTitle("Garmin Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ATHLTHTrainingSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Strength") {
                Picker(
                    "Strength tracking",
                    selection: $settings.defaultStrengthTracking
                ) {
                    ForEach(StrengthTrackingPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }

                Text(strengthTrackingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Route alerts") {
                Toggle(
                    "Off-route alerts",
                    isOn: $settings.routeAlertsEnabled
                )

                if settings.routeAlertsEnabled {
                    Picker(
                        "Alert when off route",
                        selection:
                            $settings.routeAlertDeviationMeters
                    ) {
                        Text("25 m").tag(25.0)
                        Text("50 m").tag(50.0)
                        Text("80 m").tag(80.0)
                        Text("100 m").tag(100.0)
                        Text("150 m").tag(150.0)
                        Text("250 m").tag(250.0)
                    }

                    Picker(
                        "Wait before alert",
                        selection:
                            $settings.routeAlertGraceSeconds
                    ) {
                        Text("Immediately").tag(0)
                        Text("5 sec").tag(5)
                        Text("10 sec").tag(10)
                        Text("20 sec").tag(20)
                        Text("30 sec").tag(30)
                    }

                    Picker(
                        "Alert style",
                        selection:
                            $settings.routeAlertDelivery
                    ) {
                        ForEach(
                            WatchAlertDelivery.allCases
                        ) { delivery in
                            Text(delivery.title)
                                .tag(delivery)
                        }
                    }

                    Picker(
                        "Repeat while off route",
                        selection:
                            $settings.routeAlertRepeatSeconds
                    ) {
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                        Text("2 min").tag(120)
                        Text("5 min").tag(300)
                    }

                    Toggle(
                        "Tell me when I'm back on route",
                        isOn:
                            $settings
                                .routeAlertAnnounceBackOnRoute
                    )
                }

                Text(
                    "These are your defaults for every planned ATHLTH route. The Watch ignores short GPS jumps until the selected distance and delay are exceeded."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Activity sharing") {
                Toggle(
                    "Publish completed workouts automatically",
                    isOn: $settings.autoPublishCompletedWorkouts
                )

                if settings.autoPublishCompletedWorkouts {
                    Picker(
                        "Automatic visibility",
                        selection: $settings.defaultActivityVisibility
                    ) {
                        ForEach(ProfileVisibility.allCases) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }

                    Text(
                        "ATHLTH publishes the workout after it is saved. Post-workout review still opens so you can add context or change visibility."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Completed workouts stay private until you choose to share them."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var strengthTrackingDescription: String {
        switch settings.defaultStrengthTracking {
        case .simple:
            return "Simple keeps strength logging fast with a lighter set and rep workflow."
        case .advanced:
            return "Advanced enables the full strength workflow with more detailed workout tracking."
        }
    }
}

private struct ATHLTHNotificationSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore

    var body: some View {
        Form {
            Section("System permission") {
                LabeledContent("iOS notifications", value: authorizationTitle)

                switch notifications.authorizationStatus {
                case .notDetermined:
                    Button("Allow Notifications") {
                        Task {
                            await notifications.requestSystemNotificationPermission()
                        }
                    }
                case .denied:
                    Button("Open iOS Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                default:
                    EmptyView()
                }
            }

            Section("ATHLTH alerts") {
                Toggle("Workout updates", isOn: $settings.workoutRemindersEnabled)
                Toggle("Friend activity", isOn: $settings.friendActivityNotificationsEnabled)
                Toggle("Challenges", isOn: $settings.challengeNotificationsEnabled)
                Toggle("Messages", isOn: $settings.messageNotificationsEnabled)

                Text("These switches control system alerts. Events can still appear in the ATHLTH notification center so you do not lose your activity history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notifications.refreshAuthorizationStatus()
            await notifications.reconcileSystemPreferences()
        }
        .onChange(of: settings.challengeNotificationsEnabled) { _, _ in
            Task {
                await notifications.reconcileSystemPreferences()
            }
        }
    }

    private var authorizationTitle: String {
        switch notifications.authorizationStatus {
        case .notDetermined: return "Not requested"
        case .denied: return "Disabled"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Temporary"
        @unknown default: return "Unknown"
        }
    }
}
