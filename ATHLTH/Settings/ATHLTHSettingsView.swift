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

                    settingsSection("Privacy") {
                        PremiumSettingsCard {
                            NavigationLink {
                                ATHLTHPrivacyCenterView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "hand.raised",
                                    title: "Privacy Center",
                                    subtitle: privacySummary
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
                                        subtitle: "Developer diagnostics and capability tests"
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
        if health.lastSuccessfulRefreshAt != nil && !health.hasReadableHealthData {
            return "No data"
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

            if health.hasReadableHealthData {
                return "Apple Health data imported successfully. Last synced \(relative)."
            }

            return "Apple Health responded, but ATHLTH found no readable compatible data. Check that ATHLTH has read access in Apple Health, then tap Sync now."
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

        if health.hasReadableHealthData {
            return "Connected · compatible health data is available"
        }

        if health.lastSuccessfulRefreshAt != nil {
            return "Permission configured · no readable data found yet"
        }

        return "Permission configured · run the first sync"
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
            health.resumeUserInitiatedHealthSync()
            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            await health.refreshAll()
            syncHealthProfileFromAppleHealthIfAppropriate()
            healthRequestInProgress = false
        }
    }

    private func syncHealthProfileFromAppleHealthIfAppropriate() {
        guard session.onboardingProfile?.personalDetailsSource != .manual,
              health.personalDetails.hasAnyValue
        else {
            return
        }

        session.updatePersonalDetails(
            health.personalDetails,
            source: .appleHealth
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
        Form {
            Section("Primary training device") {
                ForEach(TrainingDeviceProvider.allCases) { provider in
                    HStack(spacing: 10) {
                        Button {
                            select(provider)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: provider.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(
                                        settings.trainingDeviceProvider == provider
                                            ? ATHLTHTheme.accent
                                            : .secondary
                                    )
                                    .frame(width: 34)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 7) {
                                        Text(provider.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        if provider == .garmin {
                                            Text("COMING SOON")
                                                .font(.system(size: 8, weight: .bold))
                                                .tracking(0.7)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Color.primary.opacity(0.05),
                                                    in: Capsule()
                                                )
                                        }
                                    }

                                    Text(deviceSubtitle(provider))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        settings.trainingDeviceProvider == provider
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    settings.trainingDeviceProvider == provider
                                        ? ATHLTHTheme.accent
                                        : Color.secondary.opacity(0.55)
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(provider == .garmin)
                        .opacity(provider == .garmin ? 0.62 : 1)

                        if provider == .appleWatch {
                            NavigationLink {
                                AppleWatchConnectionView()
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("Apple Watch details")
                        } else if provider == .garmin {
                            NavigationLink {
                                GarminConnectionSetupView()
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("Garmin setup information")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if settings.trainingDeviceProvider == .appleWatch {
                Section("Apple Watch") {
                    LabeledContent(
                        "Status",
                        value: watchConnection.statusText
                    )

                    if watchConnection.state == .appNotInstalled {
                        Label(
                            "ATHLTH is not installed on the paired Watch.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    } else if watchConnection.isReady {
                        Label(
                            "ATHLTH Watch app is installed and ready.",
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.accent)
                    }

                    NavigationLink {
                        AppleWatchConnectionView()
                    } label: {
                        Label(
                            watchConnection.isReady
                                ? "Apple Watch details"
                                : "Finish Apple Watch setup",
                            systemImage: "applewatch"
                        )
                    }
                }
            }

            if settings.trainingDeviceProvider == .garmin {
                Section("Garmin") {
                    NavigationLink {
                        GarminConnectionSetupView()
                    } label: {
                        Label("Set up Garmin", systemImage: "watch.analog")
                    }
                }
            }
        }
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
                return "Connected · ATHLTH Watch app installed"
            case .appNotInstalled:
                return "Paired · ATHLTH Watch app not installed"
            case .notPaired:
                return "No paired Apple Watch found"
            case .checking:
                return "Checking Apple Watch…"
            case .unsupported:
                return "Apple Watch unavailable on this device"
            }

        case .garmin:
            return "Setup will open here when Garmin access is enabled"

        case .none:
            return "Use ATHLTH with iPhone and available Apple Health data"
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
            Section("Workout") {
                if settings.trainingDeviceProvider != .none {
                    Picker(
                        "Preferred workout device",
                        selection: $settings.preferredWorkoutCapture
                    ) {
                        Text("Automatic").tag(WorkoutCapturePreference.automatic)
                        Text("iPhone").tag(WorkoutCapturePreference.iPhone)

                        if settings.trainingDeviceProvider == .appleWatch {
                            Text("Apple Watch")
                                .tag(WorkoutCapturePreference.appleWatch)
                        }
                    }

                    if settings.trainingDeviceProvider == .garmin {
                        Text(
                            "Garmin is your selected wearable. Until Garmin authorization is available, workouts started in ATHLTH use iPhone/manual capture and Garmin sync remains pending."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Picker("Strength tracking", selection: $settings.defaultStrengthTracking) {
                    ForEach(StrengthTrackingPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }

                Text("Only settings that are connected to the active workout flow are shown here. Auto-pause, audio cues and Watch haptic controls will return when those workout-engine features are implemented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Completed workouts") {
                Toggle(
                    "Publish completed workouts automatically",
                    isOn: $settings.autoPublishCompletedWorkouts
                )

                if settings.autoPublishCompletedWorkouts {
                    LabeledContent(
                        "Automatic visibility",
                        value: settings.defaultActivityVisibility.title
                    )

                    Text("The workout is saved first. Post-workout review still opens so you can add context or change visibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
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
