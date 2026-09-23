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
                                ATHLTHEditProfileView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "person.crop.circle",
                                    title: "Edit Profile",
                                    subtitle: "Photo, display name, username and bio"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

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
                                    .disabled(!session.canAccess(.backgroundHealthSync))
                            }
                            .opacity(session.canAccess(.backgroundHealthSync) ? 1 : 0.64)

                            SettingsDivider()

                            PremiumSettingsRow(
                                icon: healthSyncHasIssue
                                    ? "exclamationmark.triangle"
                                    : "arrow.triangle.2.circlepath",
                                iconTint: healthSyncHasIssue
                                    ? .orange
                                    : ATHLTHTheme.accentDeep,
                                title: "Sync status",
                                subtitle: healthSyncStatusText
                            ) {
                                Text(healthSyncStateTitle)
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        healthSyncHasIssue
                                            ? Color.orange
                                            : ATHLTHTheme.mutedText
                                    )
                            }
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
                                    subtitle: health.hasRequestedAuthorization
                                        ? "Health access has been configured"
                                        : "Connect your Apple Health data"
                                ) {
                                    connectionTrailing(
                                        health.hasRequestedAuthorization ? "Configured" : "Connect",
                                        showChevron: true,
                                        loading: healthRequestInProgress
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(healthRequestInProgress)

                            SettingsDivider()

                            NavigationLink {
                                AppleWatchConnectionView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "applewatch",
                                    iconTint: ATHLTHTheme.primaryText,
                                    title: "Apple Watch",
                                    subtitle: watchConnection.statusText
                                ) {
                                    connectionTrailing(
                                        watchConnection.isReady ? "Connected" : "Open",
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

                    if session.currentRole.canAccessControlCenter {
                        settingsSection("Admin") {
                            PremiumSettingsCard {
                                NavigationLink {
                                AdminCenterView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "lock.rectangle.stack",
                                    title: "Control Center",
                                    subtitle: "ATHLTH administration"
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
        guard session.canAccess(.backgroundHealthSync),
              settings.backgroundHealthSyncEnabled
        else {
            return false
        }
        return !(health.backgroundSyncError?.isEmpty ?? true)
    }

    private var healthSyncStateTitle: String {
        guard session.canAccess(.backgroundHealthSync),
              settings.backgroundHealthSyncEnabled
        else {
            return "Off"
        }
        return healthSyncHasIssue ? "Issue" : "Active"
    }

    private var healthSyncStatusText: String {
        guard session.canAccess(.backgroundHealthSync) else {
            return "Background Health Sync is available with ATHLTH+."
        }

        guard settings.backgroundHealthSyncEnabled else {
            return "Background sync is turned off."
        }

        if let error = health.backgroundSyncError, !error.isEmpty {
            return "Background sync needs attention: \(error)"
        }

        if let lastRefresh = health.lastSuccessfulRefreshAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Last synced " + formatter.localizedString(for: lastRefresh, relativeTo: Date())
        }

        return health.hasRequestedAuthorization
            ? "Waiting for the first Apple Health refresh."
            : "Apple Health is not configured."
    }

    private var backgroundHealthSyncBinding: Binding<Bool> {
        Binding(
            get: {
                session.canAccess(.backgroundHealthSync) &&
                settings.backgroundHealthSyncEnabled
            },
            set: { enabled in
                guard session.canAccess(.backgroundHealthSync) else {
                    showingMembership = true
                    return
                }
                settings.backgroundHealthSyncEnabled = enabled
            }
        )
    }

    private var backgroundHealthSubtitle: String {
        if session.canAccess(.backgroundHealthSync) {
            return "Sync with Apple Health in the background. ATHLTH+ feature."
        }
        return "Available with ATHLTH+. Apple Health still works on Free."
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
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                openURL(settingsURL)
            }
            return
        }

        Task {
            healthRequestInProgress = true
            await health.requestAuthorization()
            await health.configureBackgroundSync(
                allowed:
                    session.canAccess(.backgroundHealthSync) &&
                    settings.backgroundHealthSyncEnabled
            )
            healthRequestInProgress = false
        }
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

private struct ATHLTHTrainingSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        Form {
            Section("Workout") {
                Picker("Preferred workout device", selection: $settings.preferredWorkoutCapture) {
                    ForEach(WorkoutCapturePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
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
