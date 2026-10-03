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
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

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

                            SettingsDivider()

                            Menu {
                                ForEach(
                                    AppLanguage
                                        .currentlySupported
                                ) { language in
                                    Button {
                                        settings.language =
                                            language
                                    } label: {
                                        if settings.language ==
                                            language {
                                            Label(
                                                language.title,
                                                systemImage:
                                                    "checkmark"
                                            )
                                        } else {
                                            Text(
                                                language.title
                                            )
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(
                                        systemName: "globe"
                                    )
                                    .font(
                                        .system(
                                            size: 18,
                                            weight: .medium
                                        )
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .primaryText
                                    )
                                    .frame(
                                        width: 44,
                                        height: 44
                                    )
                                    .background(
                                        ATHLTHTheme
                                            .accentSoft,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 14,
                                                style:
                                                    .continuous
                                            )
                                    )

                                    VStack(
                                        alignment: .leading,
                                        spacing: 3
                                    ) {
                                        Text("Language")
                                            .font(
                                                .system(
                                                    size: 16.5,
                                                    weight:
                                                        .medium
                                                )
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme
                                                    .primaryText
                                            )

                                        Text(
                                            "Choose English or Norwegian"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                    }

                                    Spacer(
                                        minLength: 12
                                    )

                                    HStack(spacing: 8) {
                                        Text(
                                            settings
                                                .language
                                                .title
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )

                                        Image(
                                            systemName:
                                                "chevron.up.chevron.down"
                                        )
                                        .font(
                                            .caption2
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                                .opacity(
                                                    0.72
                                                )
                                        )
                                    }
                                }
                                .padding(
                                    .horizontal,
                                    16
                                )
                                .padding(
                                    .vertical,
                                    13
                                )
                                .contentShape(
                                    Rectangle()
                                )
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHWidgetsAndSurfacesSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "rectangle.grid.2x2",
                                    iconTint: ATHLTHTheme.vitality,
                                    iconBackground: ATHLTHTheme.vitalitySoft,
                                    title: "Widgets & Surfaces",
                                    subtitle: "Home Screen, Live Activities, Siri and Lock Screen"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText.opacity(0.72)
                                        )
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

                            Menu {
                                ForEach(
                                    ExternalWorkoutImportMode.allCases
                                ) { mode in
                                    Button {
                                        settings.externalWorkoutImportMode = mode
                                        Task {
                                            await health
                                                .applyExternalWorkoutImportMode(
                                                    mode
                                                )
                                        }
                                    } label: {
                                        if settings.externalWorkoutImportMode ==
                                            mode {
                                            Label(
                                                mode.title,
                                                systemImage: "checkmark"
                                            )
                                        } else {
                                            Text(mode.title)
                                        }
                                    }
                                }
                            } label: {
                                PremiumSettingsRow(
                                    icon: "square.and.arrow.down",
                                    title: "External workouts",
                                    subtitle:
                                        "Control workouts found in Apple Health"
                                ) {
                                    HStack(spacing: 8) {
                                        Text(
                                            settings
                                                .externalWorkoutImportMode
                                                .shortTitle
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                        )

                                        Image(
                                            systemName: "chevron.right"
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                                .opacity(0.72)
                                        )
                                    }
                                }
                            }
                            .buttonStyle(.plain)

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
                                        healthRequestInProgress
                                            ? "Syncing"
                                            : health.hasRequestedAuthorization
                                                ? "Sync now"
                                                : "Connect",
                                        showChevron: false,
                                        loading: healthRequestInProgress
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(healthRequestInProgress)
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
                                        !health.hasRequestedAuthorization
                                            ? "Connect"
                                            : health.hasReadableHealthData
                                                ? "Connected"
                                                : "Configured",
                                        showChevron: true
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
                                                    ? "Connected"
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
                                    icon: "applewatch",
                                    iconTint: ATHLTHTheme.primaryText,
                                    title: "Watch",
                                    subtitle: trainingDeviceSubtitle
                                ) {
                                    connectionTrailing(
                                        watchDeviceTrailingTitle,
                                        showChevron: true
                                    )
                                }
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            NavigationLink {
                                SpotifySettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "music.note",
                                    iconTint: spotifyGreen,
                                    iconBackground: spotifyGreen.opacity(0.12),
                                    title: "Spotify",
                                    subtitle: spotifyConnectionSubtitle
                                ) {
                                    connectionTrailing(
                                        spotify.connectionState.title,
                                        showChevron: true,
                                        loading:
                                            spotify.connectionState == .connecting
                                    )
                                }
                            }
                            .buttonStyle(.plain)

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
                                ATHLTHWorkoutGuidanceSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "waveform.and.mic",
                                    iconTint: ATHLTHTheme.premiumGold,
                                    iconBackground:
                                        ATHLTHTheme.premiumGoldSoft,
                                    title: "Workout Guidance",
                                    subtitle:
                                        "Audio Coach · Route Guardian · Ghost Updates"
                                ) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(
                                            ATHLTHTheme.mutedText
                                                .opacity(0.72)
                                        )
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

                            SettingsDivider()

                            NavigationLink {
                                ATHLTHAchievementSettingsView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "medal.fill",
                                    iconTint: ATHLTHTheme.premiumGold,
                                    iconBackground:
                                        ATHLTHTheme.premiumGoldSoft,
                                    title:
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Achievements",
                                            norwegian:
                                                "Achievements"
                                        ),
                                    subtitle:
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Unlock effects, sound and haptics",
                                            norwegian:
                                                "Unlock-effekter, lyd og haptikk"
                                        )
                                ) {
                                    HStack(spacing: 8) {
                                        Text(
                                            settings
                                                .achievementEffects
                                                .title
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )

                                        Image(
                                            systemName:
                                                "chevron.right"
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                                .opacity(
                                                    0.72
                                                )
                                        )
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

                    settingsSection("Account") {
                        PremiumSettingsCard {
                            NavigationLink {
                                ATHLTHAccountSecurityView()
                            } label: {
                                PremiumSettingsRow(
                                    icon: "person.badge.key",
                                    title: ATHLTHLocalization.choose(
                                        english: "Account & Security",
                                        norwegian: "Konto og sikkerhet"
                                    ),
                                    subtitle: ATHLTHLocalization.choose(
                                        english: "Sign-in, security, privacy and your data",
                                        norwegian: "Innlogging, sikkerhet, personvern og data"
                                    )
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

                    if session.currentRole.canAccessControlCenter {
                        settingsSection("Developer") {
                            PremiumSettingsCard {
                                NavigationLink {
                                    AdminAIUsageView()
                                } label: {
                                    PremiumSettingsRow(
                                        icon: "sparkles.rectangle.stack",
                                        title: "AI Usage",
                                        subtitle: "Live Groq quota and prompt-saving status"
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
                        settingsSection("Developer Tools") {
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
            _ = await health.restoreAuthorizationStateFromSystem()

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
            Text(localizedSettingsSectionTitle(title).uppercased())
                .font(.caption.weight(.semibold))
                .tracking(2.8)
                .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                .padding(.leading, 16)

            content()
        }
        .padding(.bottom, 24)
    }

    private func localizedSettingsSectionTitle(
        _ title: String
    ) -> String {
        guard ATHLTHLocalization.isNorwegian else {
            return title
        }

        switch title {
        case "App":
            return "App"
        case "Profile":
            return "Profil"
        case "Privacy & Data":
            return "Personvern og data"
        case "Health & Sync":
            return "Helse og synkronisering"
        case "Connections":
            return "Tilkoblinger"
        case "Preferences":
            return "Preferanser"
        case "Membership":
            return "Medlemskap"
        case "Account":
            return "Konto"
        case "About":
            return "Om ATHLTH"
        case "Support":
            return "Brukerstøtte"
        case "Developer":
            return "Utvikler"
        case "Admin":
            return "Admin"
        case "Developer Tools":
            return "Utviklerverktøy"
        default:
            return title
        }
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
        switch watchConnection.state {
        case .ready:
            return ATHLTHLocalization.choose(
                english: "Apple Watch connected",
                norwegian: "Apple Watch tilkoblet"
            )
        case .appNotInstalled:
            return ATHLTHLocalization.choose(
                english: "Apple Watch paired · install ATHLTH on Watch",
                norwegian: "Apple Watch sammenkoblet · installer ATHLTH på klokken"
            )
        case .notPaired:
            return ATHLTHLocalization.choose(
                english: "No Apple Watch connected",
                norwegian: "Ingen Apple Watch tilkoblet"
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking Apple Watch",
                norwegian: "Sjekker Apple Watch"
            )
        case .unsupported:
            return ATHLTHLocalization.choose(
                english: "Apple Watch unavailable on this device",
                norwegian: "Apple Watch er ikke tilgjengelig på denne enheten"
            )
        }
    }

    private var watchDeviceTrailingTitle: String {
        switch watchConnection.state {
        case .ready:
            return "Apple Watch"
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking",
                norwegian: "Sjekker"
            )
        case .appNotInstalled, .notPaired, .unsupported:
            return ATHLTHLocalization.choose(
                english: "Setup",
                norwegian: "Oppsett"
            )
        }
    }

    private var spotifyConnectionSubtitle: String {
        if spotify.isConnected {
            if spotify.playlists.isEmpty {
                return ATHLTHLocalization.choose(
                    english: "Spotify connected",
                    norwegian: "Spotify tilkoblet"
                )
            }

            return ATHLTHLocalization.format(
                english: "Connected · %d playlists available",
                norwegian: "Tilkoblet · %d spillelister tilgjengelig",
                spotify.playlists.count
            )
        }

        switch spotify.connectionState {
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "Spotify setup is unavailable in this build",
                norwegian: "Spotify-oppsett er ikke tilgjengelig i denne versjonen"
            )
        case .connecting:
            return ATHLTHLocalization.choose(
                english: "Connecting to Spotify…",
                norwegian: "Kobler til Spotify…"
            )
        case .error:
            return ATHLTHLocalization.choose(
                english: "Connection needs attention",
                norwegian: "Tilkoblingen krever oppmerksomhet"
            )
        case .disconnected:
            return ATHLTHLocalization.choose(
                english: "Connect Spotify for workout playlists",
                norwegian: "Koble til Spotify for spillelister til trening"
            )
        case .connected:
            return ATHLTHLocalization.choose(
                english: "Spotify connected",
                norwegian: "Spotify tilkoblet"
            )
        }
    }

    private var notificationSummary: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return ATHLTHLocalization.choose(
                english: "System notifications allowed · choose what ATHLTH sends",
                norwegian: "Systemvarsler tillatt · velg hva ATHLTH skal sende"
            )
        case .denied:
            return ATHLTHLocalization.choose(
                english: "System notifications are disabled in iOS Settings",
                norwegian: "Systemvarsler er deaktivert i iOS-innstillinger"
            )
        case .notDetermined:
            return ATHLTHLocalization.choose(
                english: "System notification permission has not been requested",
                norwegian: "Tillatelse til systemvarsler er ikke forespurt"
            )
        @unknown default:
            return ATHLTHLocalization.choose(
                english: "Review notification preferences",
                norwegian: "Se gjennom varslingsinnstillingene"
            )
        }
    }

    private var healthSyncHasIssue: Bool {
        let backgroundIssue = !(health.backgroundSyncError?.isEmpty ?? true)
        let readIssue = !(health.authorizationError?.isEmpty ?? true)
        return backgroundIssue || readIssue
    }

    private var healthSyncStateTitle: String {
        guard settings.backgroundHealthSyncEnabled else {
            return ATHLTHLocalization.choose(
                english: "Off",
                norwegian: "Av"
            )
        }
        if health.isRefreshing {
            return ATHLTHLocalization.choose(
                english: "Syncing",
                norwegian: "Synkroniserer"
            )
        }
        if !health.hasRequestedAuthorization {
            return ATHLTHLocalization.choose(
                english: "Not connected",
                norwegian: "Ikke tilkoblet"
            )
        }
        if healthSyncHasIssue {
            return ATHLTHLocalization.choose(
                english: "Issue",
                norwegian: "Problem"
            )
        }
        if health.lastSuccessfulRefreshAt != nil && !health.hasTrainingHealthData {
            return health.personalDetails.hasAnyValue
                ? ATHLTHLocalization.choose(
                    english: "Profile only",
                    norwegian: "Kun profil"
                )
                : ATHLTHLocalization.choose(
                    english: "No data",
                    norwegian: "Ingen data"
                )
        }
        if health.lastSuccessfulRefreshAt != nil &&
            health.hasTrainingHealthData &&
            !health.canWriteWorkouts {
            return ATHLTHLocalization.choose(
                english: "Read only",
                norwegian: "Kun lesing"
            )
        }
        return health.lastSuccessfulRefreshAt != nil
            ? ATHLTHLocalization.choose(
                english: "Synced",
                norwegian: "Synkronisert"
            )
            : ATHLTHLocalization.choose(
                english: "Ready",
                norwegian: "Klar"
            )
    }

    private var healthSyncStatusText: String {
        if healthRequestInProgress {
            return ATHLTHLocalization.choose(
                english: "Reading workouts, activity, sleep, heart data and profile values from Apple Health.",
                norwegian: "Leser økter, aktivitet, søvn, hjertedata og profilverdier fra Apple Health."
            )
        }

        if let error = health.backgroundSyncError, !error.isEmpty {
            return ATHLTHLocalization.choose(
                english: "Background sync needs attention: \(error)",
                norwegian: "Bakgrunnssynkronisering krever oppmerksomhet: \(error)"
            )
        }

        if let error = health.authorizationError, !error.isEmpty {
            return ATHLTHLocalization.choose(
                english: "Apple Health read needs attention: \(error)",
                norwegian: "Lesetilgang til Apple Health krever oppmerksomhet: \(error)"
            )
        }

        guard health.hasRequestedAuthorization else {
            return ATHLTHLocalization.choose(
                english: "Apple Health is not connected yet. Tap here to connect.",
                norwegian: "Apple Health er ikke tilkoblet ennå. Trykk her for å koble til."
            )
        }

        if let lastRefresh = health.lastSuccessfulRefreshAt {
            let synced = healthSyncTimestamp(lastRefresh)

            if health.hasTrainingHealthData {
                if health.canWriteWorkouts {
                    return ATHLTHLocalization.choose(
                        english: "Apple Health training data imported successfully. Last synced \(synced).",
                        norwegian: "Treningsdata fra Apple Health er importert. Sist synkronisert \(synced)."
                    )
                }

                return ATHLTHLocalization.choose(
                    english: "Apple Health data was imported \(synced), but workout write access is off. Tap Sync now to review Health permissions.",
                    norwegian: "Apple Health-data ble importert \(synced), men skrivetilgang for økter er av. Trykk Synkroniser nå for å kontrollere Health-tillatelser."
                )
            }

            if health.personalDetails.hasAnyValue {
                return ATHLTHLocalization.choose(
                    english: "Apple Health profile values were imported, but ATHLTH found no readable workouts, activity, sleep or heart data. Review Health read access, then tap Sync now.",
                    norwegian: "Profilverdier fra Apple Health ble importert, men ATHLTH fant ingen lesbare økter, aktivitets-, søvn- eller hjertedata. Kontroller lesetilgangen i Health og trykk deretter Synkroniser nå."
                )
            }

            return ATHLTHLocalization.choose(
                english: "Apple Health responded, but ATHLTH found no readable compatible data. Review Health read access, then tap Sync now.",
                norwegian: "Apple Health svarte, men ATHLTH fant ingen kompatible data som kunne leses. Kontroller lesetilgangen i Health og trykk deretter Synkroniser nå."
            )
        }

        return settings.backgroundHealthSyncEnabled
            ? ATHLTHLocalization.choose(
                english: "Apple Health is configured. Tap Sync now to perform the first full import.",
                norwegian: "Apple Health er konfigurert. Trykk Synkroniser nå for å utføre første fullstendige import."
            )
            : ATHLTHLocalization.choose(
                english: "Apple Health is configured. Background sync is off, but you can still tap Sync now.",
                norwegian: "Apple Health er konfigurert. Bakgrunnssynkronisering er av, men du kan fortsatt trykke Synkroniser nå."
            )
    }

    private func healthSyncTimestamp(
        _ date: Date
    ) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return ATHLTHLocalization.choose(
                english: "today at ",
                norwegian: "i dag kl. "
            ) + date.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        if calendar.isDateInYesterday(date) {
            return ATHLTHLocalization.choose(
                english: "yesterday at ",
                norwegian: "i går kl. "
            ) + date.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        return date.formatted(
            date: .abbreviated,
            time: .shortened
        )
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
        ATHLTHLocalization.choose(
            english: "Sync with Apple Health automatically in the background.",
            norwegian: "Synkroniser automatisk med Apple Health i bakgrunnen."
        )
    }

    private var appleHealthConnectionSubtitle: String {
        guard health.hasRequestedAuthorization else {
            return ATHLTHLocalization.choose(
                english: "Connect your Apple Health data",
                norwegian: "Koble til Apple Health-data"
            )
        }

        if health.authorizationReviewNeeded {
            return ATHLTHLocalization.choose(
                english: "Connected · optional new Health permissions are available",
                norwegian: "Tilkoblet · valgfrie nye Health-tillatelser er tilgjengelige"
            )
        }

        if health.hasTrainingHealthData {
            return health.canWriteWorkouts
                ? ATHLTHLocalization.choose(
                    english: "Connected · training and health data is available",
                    norwegian: "Tilkoblet · trenings- og helsedata er tilgjengelig"
                )
                : ATHLTHLocalization.choose(
                    english: "Connected for reading · workout write access is off",
                    norwegian: "Tilkoblet for lesing · skrivetilgang for økter er av"
                )
        }

        if health.personalDetails.hasAnyValue {
            return ATHLTHLocalization.choose(
                english: "Configured · profile values available, no training data yet",
                norwegian: "Konfigurert · profilverdier tilgjengelig, ingen treningsdata ennå"
            )
        }

        if health.lastSuccessfulRefreshAt != nil {
            return ATHLTHLocalization.choose(
                english: "Permission configured · no readable data found yet",
                norwegian: "Tillatelse konfigurert · ingen lesbare data funnet ennå"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Permission configured · run the first sync",
            norwegian: "Tillatelse konfigurert · kjør første synkronisering"
        )
    }

    private var appleCalendarConnectionSubtitle: String {
        if calendarSync.isEnabled {
            return ATHLTHLocalization.choose(
                english: "Training plan sync · ATHLTH calendar",
                norwegian: "Synkronisering av treningsplan · ATHLTH-kalender"
            )
        }

        if calendarSync.hasFullAccess {
            return ATHLTHLocalization.choose(
                english: "Calendar connected · training plan sync is off",
                norwegian: "Kalender tilkoblet · synkronisering av treningsplan er av"
            )
        }

        return ATHLTHLocalization.choose(
            english: "Sync planned workouts to a dedicated ATHLTH calendar",
            norwegian: "Synkroniser planlagte økter til en egen ATHLTH-kalender"
        )
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
                Text(localizedConnectionStatus(text))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(ATHLTHTheme.mutedText.opacity(0.72))
            }
        }
    }

    private func localizedConnectionStatus(
        _ status: String
    ) -> String {
        guard ATHLTHLocalization.isNorwegian else {
            return status
        }

        switch status {
        case "Connected":
            return "Tilkoblet"
        case "Not connected":
            return "Ikke tilkoblet"
        case "Connect":
            return "Koble til"
        case "Syncing":
            return "Synkroniserer"
        case "Configured":
            return "Konfigurert"
        case "Ready":
            return "Klar"
        case "Checking":
            return "Sjekker"
        case "Setup":
            return "Oppsett"
        case "Connection issue":
            return "Tilkoblingsproblem"
        case "Needs setup":
            return "Må konfigureres"
        case "Connecting…":
            return "Kobler til…"
        default:
            return status
        }
    }

    private func handleAppleHealthTap() {
        Task {
            healthRequestInProgress = true

            let restoredExistingSetup =
                await health.restoreAuthorizationStateFromSystem()

            if !restoredExistingSetup || health.authorizationReviewNeeded {
                // The Apple Health row is the explicit place to connect or
                // review newly introduced permissions. Normal sync never
                // reopens the Health permission flow.
                await health.requestAuthorization()
                await health.completeAuthorizationSetup()
            } else {
                health.resumeUserInitiatedHealthSync()
            }

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            _ = await health.refreshWorkoutImportInbox()
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

            // Sync with the permissions that are already in place. Do not
            // reopen Health authorization simply because the app was updated
            // or because ATHLTH added another optional Health data type.
            _ = await health.restoreAuthorizationStateFromSystem()
            health.resumeUserInitiatedHealthSync()

            await health.configureBackgroundSync(
                allowed: settings.backgroundHealthSyncEnabled
            )
            _ = await health.refreshWorkoutImportInbox()
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
    @EnvironmentObject private var communityEvents: CommunityEventStore
    @EnvironmentObject private var communityGroups: CommunityGroupStore
    @EnvironmentObject private var challenges: ChallengeStore

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
                                Text("Sync ATHLTH Calendar")
                                    .font(.system(size: 16.5, weight: .medium))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text("Keep your plan, event responses and challenge invitations in Calendar.")
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
                                    await syncAllCalendarContent()
                                } else {
                                    await enableCalendarSync()
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
                await syncAllCalendarContent()
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
                    await syncAllCalendarContent()
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
                        await enableCalendarSync()
                    }
                } else {
                    calendarSync.disable()
                }
            }
        )
    }

    private func refreshCalendarSources() async {
        async let eventRefresh: Void =
            communityEvents.refresh()
        async let groupRefresh: Void =
            communityGroups.refreshCalendarContent()

        _ = await (
            eventRefresh,
            groupRefresh
        )
    }

    private func syncAllCalendarContent() async {
        await refreshCalendarSources()

        await calendarSync.sync(
            plan: session.activePlan,
            communityEvents: communityEvents.events,
            groupEvents: communityGroups.calendarEvents,
            groupEventRSVPs:
                communityGroups.calendarEventRSVPs,
            challenges: challenges.challenges,
            currentUserID: session.profile.userID
        )
    }

    private func enableCalendarSync() async {
        await refreshCalendarSources()

        await calendarSync.enable(
            plan: session.activePlan,
            communityEvents: communityEvents.events,
            groupEvents: communityGroups.calendarEvents,
            groupEventRSVPs:
                communityGroups.calendarEventRSVPs,
            challenges: challenges.challenges,
            currentUserID: session.profile.userID
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
            return ATHLTHLocalization.choose(
                english: "Never",
                norwegian: "Aldri"
            )
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
                Text(
                    LocalizedStringKey(title)
                )
                    .font(.system(size: 16.5, weight: .medium))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(
                        LocalizedStringKey(
                            subtitle
                        )
                    )
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
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("APPLE WATCH")
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("HOW WORKOUT RECORDING WORKS")
                        .font(.caption.weight(.semibold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                        .padding(.leading, 16)

                    PremiumSettingsCard {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "figure.run.circle")
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

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Choose when you start")
                                    .font(.system(size: 16.5, weight: .semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(
                                    "iPhone and Apple Watch are chosen for each workout when you press Start. This screen only manages your Watch connection."
                                )
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(16)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("OTHER WATCHES")
                        .font(.caption.weight(.semibold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep.opacity(0.82))
                        .padding(.leading, 16)

                    PremiumSettingsCard {
                        HStack(spacing: 14) {
                            Image(systemName: "watch.analog")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(ATHLTHTheme.mutedText)
                                .frame(width: 44, height: 44)
                                .background(
                                    Color.primary.opacity(0.035),
                                    in: RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Garmin")
                                        .font(.system(size: 16.5, weight: .semibold))
                                        .foregroundStyle(ATHLTHTheme.primaryText)

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
                                }

                                Text("Garmin Connect support is planned and will appear here when it is ready.")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()
                        }
                        .padding(16)
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
        .navigationTitle("Watch")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            watchConnection.connect()
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
            return ATHLTHLocalization.choose(
                english: "Paired",
                norwegian: "Sammenkoblet"
            )
        case .notPaired:
            return ATHLTHLocalization.choose(
                english: "Not paired",
                norwegian: "Ikke sammenkoblet"
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking…",
                norwegian: "Sjekker…"
            )
        case .unsupported:
            return ATHLTHLocalization.choose(
                english: "Unavailable",
                norwegian: "Ikke tilgjengelig"
            )
        }
    }

    private var watchAppTitle: String {
        switch watchConnection.state {
        case .ready:
            return ATHLTHLocalization.choose(
                english: "Installed",
                norwegian: "Installert"
            )
        case .appNotInstalled:
            return ATHLTHLocalization.choose(
                english: "Not installed",
                norwegian: "Ikke installert"
            )
        case .notPaired, .unsupported:
            return ATHLTHLocalization.choose(
                english: "Unavailable",
                norwegian: "Ikke tilgjengelig"
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "Checking…",
                norwegian: "Sjekker…"
            )
        }
    }

    private var watchSetupDetail: String {
        switch watchConnection.state {
        case .ready:
            return ATHLTHLocalization.choose(
                english: "ATHLTH Watch is ready for live workouts, routes and HealthKit sync.",
                norwegian: "ATHLTH på Apple Watch er klar for liveøkter, ruter og HealthKit-synkronisering."
            )
        case .appNotInstalled:
            return ATHLTHLocalization.choose(
                english: "Install the ATHLTH Watch app to start workouts, sync routes and use live tracking.",
                norwegian: "Installer ATHLTH på Apple Watch for å starte økter, synkronisere ruter og bruke live-sporing."
            )
        case .notPaired:
            return ATHLTHLocalization.choose(
                english: "Pair an Apple Watch with this iPhone first, then return here to finish ATHLTH setup.",
                norwegian: "Koble først en Apple Watch til denne iPhonen, og gå deretter tilbake hit for å fullføre ATHLTH-oppsettet."
            )
        case .checking:
            return ATHLTHLocalization.choose(
                english: "ATHLTH is checking the paired Apple Watch and app installation.",
                norwegian: "ATHLTH sjekker den sammenkoblede Apple Watch-en og appinstallasjonen."
            )
        case .unsupported:
            return ATHLTHLocalization.choose(
                english: "Apple Watch connectivity is unavailable on this device.",
                norwegian: "Apple Watch-tilkobling er ikke tilgjengelig på denne enheten."
            )
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
            Section {
                Picker(
                    ATHLTHLocalization.choose(
                        english: "Default workout setup",
                        norwegian: "Standard oppsett"
                    ),
                    selection:
                        $settings
                            .workoutSetupPreference
                ) {
                    ForEach(
                        WorkoutSetupPreference
                            .allCases
                    ) { preference in
                        Text(preference.title)
                            .tag(preference)
                    }
                }

                Text(
                    settings
                        .workoutSetupPreference
                        .subtitle
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Workout setup",
                        norwegian: "Oppsett av økt"
                    )
                )
            } footer: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "This controls the starting mode only. You can still switch between Basic and Advanced for an individual workout without changing the preference.",
                        norwegian:
                            "Dette styrer bare hvilken modus økten åpner i. Du kan fortsatt bytte mellom Basic og Avansert for en enkeltøkt uten å endre standardvalget."
                    )
                )
            }

            Section {
                Toggle(
                    ATHLTHLocalization.choose(
                        english: "Auto-pause outdoor workouts",
                        norwegian: "Auto-pause utendørs trening"
                    ),
                    isOn:
                        $settings
                            .autoPauseOutdoorWorkouts
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "This is the default for outdoor running and walking. Advanced setup on an individual workout can use this default or override it.",
                        norwegian:
                            "Dette er standarden for utendørs løping og gåing. Avansert oppsett på en enkelt økt kan bruke standarden eller overstyre den."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Outdoor workouts",
                        norwegian: "Utendørsøkter"
                    )
                )
            }

            Section {
                NavigationLink {
                    ATHLTHWorkoutGuidanceSettingsView()
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Workout Guidance")
                            .font(
                                .subheadline
                                    .weight(.semibold)
                            )

                        Text(
                            "Audio Coach, Route Guardian, Ghost Updates and alert priority"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    ATHLTHRouteGuardianSettingsView()
                } label: {
                    HStack {
                        Text("Route Guardian")
                        Spacer()
                        Text(
                            settings.routeAlertsEnabled
                                ? "\(Int(settings.routeAlertDeviationMeters.rounded())) m"
                                : "Off"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Guidance & alerts")
            } footer: {
                Text(
                    "Open a guidance category to adjust it. Training no longer expands all route and audio controls into one long page."
                )
            }

            Section("Activity sharing") {
                Toggle(
                    "Share completed workouts by default",
                    isOn: $settings.autoPublishCompletedWorkouts
                )
                .onChange(
                    of: settings.autoPublishCompletedWorkouts
                ) { _, enabled in
                    settings.workoutSharingChoiceCompleted = true

                    if enabled &&
                        settings.defaultActivityVisibility == .privateOnly {
                        settings.defaultActivityVisibility = .friends
                    }
                }

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
                        "ATHLTH preselects your sharing visibility, but Workout Complete always opens before anything is published."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Completed workouts default to private. Workout Complete still opens after every session so you can choose what to share."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
    }

}

private struct ATHLTHAchievementSettingsView:
    View
{
    @EnvironmentObject private var settings:
        AppSettingsStore
    @Environment(
        \.accessibilityReduceMotion
    ) private var reduceMotion
    @Environment(
        \.accessibilityReduceTransparency
    ) private var reduceTransparency

    var body: some View {
        Form {
            Section {
                Picker(
                    ATHLTHLocalization.choose(
                        english:
                            "Visual effects",
                        norwegian:
                            "Visuelle effekter"
                    ),
                    selection:
                        $settings
                            .achievementEffects
                ) {
                    ForEach(
                        AchievementEffectPreference
                            .allCases
                    ) {
                        preference in
                        Text(
                            preference.title
                        )
                        .tag(preference)
                    }
                }
                .pickerStyle(
                    .segmented
                )

                Text(
                    settings
                        .achievementEffects
                        .subtitle
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            } header: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Achievement effects",
                        norwegian:
                            "Achievement-effekter"
                    )
                )
            } footer: {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "iOS Reduce Motion and Reduce Transparency always take priority over this setting.",
                        norwegian:
                            "iOS Reduser bevegelse og Reduser gjennomsiktighet har alltid prioritet over denne innstillingen."
                    )
                )
            }

            Section(
                ATHLTHLocalization.choose(
                    english:
                        "Unlock feedback",
                    norwegian:
                        "Unlock-feedback"
                )
            ) {
                Toggle(
                    ATHLTHLocalization.choose(
                        english:
                            "Unlock sounds",
                        norwegian:
                            "Unlock-lyder"
                    ),
                    isOn:
                        $settings
                            .achievementUnlockSoundsEnabled
                )

                Toggle(
                    ATHLTHLocalization.choose(
                        english:
                            "Unlock haptics",
                        norwegian:
                            "Unlock-haptikk"
                    ),
                    isOn:
                        $settings
                            .achievementUnlockHapticsEnabled
                )
            }

            if reduceMotion ||
               reduceTransparency {
                Section(
                    ATHLTHLocalization.choose(
                        english:
                            "Accessibility",
                        norwegian:
                            "Tilgjengelighet"
                    )
                ) {
                    if reduceMotion {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Reduce Motion is active. Tilt, particle movement and large reveal transitions are reduced.",
                                norwegian:
                                    "Reduser bevegelse er aktivert. Tilt, partikkelbevegelse og store reveal-animasjoner reduseres."
                            ),
                            systemImage:
                                "figure.walk.motion"
                        )
                    }

                    if reduceTransparency {
                        Label(
                            ATHLTHLocalization.choose(
                                english:
                                    "Reduce Transparency is active. Holographic and glass effects use solid alternatives.",
                                norwegian:
                                    "Reduser gjennomsiktighet er aktivert. Holografiske effekter og glassflater bruker solide alternativer."
                            ),
                            systemImage:
                                "circle.lefthalf.filled"
                        )
                    }
                }
                .font(.caption)
            }
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Achievements",
                norwegian:
                    "Achievements"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
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
                Toggle("Mentions", isOn: $settings.mentionNotificationsEnabled)

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
        case .notDetermined:
            return ATHLTHLocalization.choose(
                english: "Not requested",
                norwegian: "Ikke forespurt"
            )
        case .denied:
            return ATHLTHLocalization.choose(
                english: "Disabled",
                norwegian: "Deaktivert"
            )
        case .authorized:
            return ATHLTHLocalization.choose(
                english: "Allowed",
                norwegian: "Tillatt"
            )
        case .provisional:
            return ATHLTHLocalization.choose(
                english: "Provisional",
                norwegian: "Midlertidig tillatt"
            )
        case .ephemeral:
            return ATHLTHLocalization.choose(
                english: "Temporary",
                norwegian: "Midlertidig"
            )
        @unknown default:
            return ATHLTHLocalization.choose(
                english: "Unknown",
                norwegian: "Ukjent"
            )
        }
    }
}
