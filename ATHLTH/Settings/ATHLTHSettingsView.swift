import SwiftUI

struct ATHLTHSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    var body: some View {
        List {
            Section("App") {
                Picker("Language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }

                Picker("Measurements", selection: $settings.measurementPreference) {
                    ForEach(MeasurementPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }

                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }

                LabeledContent(
                    "Units",
                    value: "\(settings.measurementPreference.distanceUnit) · \(settings.measurementPreference.weightUnit) · \(settings.measurementPreference.temperatureUnit)"
                )
                .foregroundStyle(.secondary)
            }

            Section("Subscription") {
                LabeledContent("Plan", value: session.subscriptionAccess.displayTitle)

                if let billingPeriod = session.subscriptionAccess.billingPeriodTitle {
                    LabeledContent("Billing", value: billingPeriod)
                }

                if session.subscriptionAccess.trialIsActive,
                   let trialEndsAt = session.subscriptionAccess.trialEndsAt {
                    LabeledContent(
                        "7-day trial ends",
                        value: trialEndsAt.formatted(date: .abbreviated, time: .omitted)
                    )
                }

                if session.subscriptionAccess.state == .paid,
                   let periodEndsAt = session.subscriptionAccess.currentPeriodEndsAt {
                    LabeledContent(
                        "Current period",
                        value: periodEndsAt.formatted(date: .abbreviated, time: .omitted)
                    )
                }

                LabeledContent(
                    "Background Health sync",
                    value: session.canAccess(.backgroundHealthSync) ? "Included" : "ATHLTH+ feature"
                )

                Button {
                    Task {
                        _ = await subscriptionStore.restorePurchases()
                    }
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        Spacer()
                        if subscriptionStore.restoreInProgress {
                            ProgressView()
                        }
                    }
                }
                .disabled(subscriptionStore.restoreInProgress)

                if let errorMessage = subscriptionStore.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Apple Health and Apple Watch can still be connected on Free. Automatic Health background sync is an ATHLTH+ feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Profile") {
                NavigationLink {
                    PersonalHealthProfileView()
                } label: {
                    Label("Personal & health details", systemImage: "person.text.rectangle")
                }
            }

            Section("Privacy") {
                Picker("Profile visibility", selection: $settings.profileVisibility) {
                    ForEach(ProfileVisibility.allCases) { visibility in
                        Text(visibility.title).tag(visibility)
                    }
                }

                Picker("Default activity visibility", selection: $settings.defaultActivityVisibility) {
                    ForEach(ProfileVisibility.allCases) { visibility in
                        Text(visibility.title).tag(visibility)
                    }
                }

                Toggle("Show “Training now” status", isOn: $settings.shareTrainingPresence)
                Toggle("Share routes by default", isOn: $settings.shareRoutesByDefault)
                Toggle("Hide route start/end when sharing", isOn: $settings.hideRouteStartAndEnd)
                Toggle("Share heart rate by default", isOn: $settings.shareHeartRateByDefault)

                Toggle(
                    "Personalized ATHLTH offers",
                    isOn: Binding(
                        get: {
                            session.onboardingProfile?.personalizedOfferConsent == .granted
                        },
                        set: { enabled in
                            session.setPersonalizedOfferConsent(
                                enabled ? .granted : .declined
                            )
                        }
                    )
                )

                Text("Uses only goals and interests you choose in ATHLTH. Apple Health / HealthKit data is excluded from offer targeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Health data is private by default. Social sharing should always be explicit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connections") {
                integrationRow(
                    .appleHealth,
                    subtitle: health.hasRequestedAuthorization ? "Connected / authorization requested" : "Not configured",
                    connected: health.hasRequestedAuthorization
                )

                Button {
                    watchConnection.connect()
                } label: {
                    integrationRow(
                        .appleWatch,
                        subtitle: watchConnection.state.subtitle,
                        connected: watchConnection.isReady
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SpotifySettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: IntegrationKind.spotify.systemImage)
                            .frame(width: 30)
                            .foregroundStyle(settings.spotifyConnected ? Color.green : Color.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spotify")
                            Text(settings.spotifyConnected ? "Connected · training plans only" : "Connect training-plan playlists")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if settings.spotifyConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                integrationRow(
                    .homeAssistant,
                    subtitle: settings.homeAssistantConnected ? "Connected" : "Optional integration",
                    connected: settings.homeAssistantConnected
                )
            }

            Section("Training") {
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

                Text("Apple Watch and detailed set tracking are optional. Every workout can be started and completed from iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-pause outdoor workouts", isOn: $settings.autoPauseOutdoorWorkouts)
                Toggle("Audio cues", isOn: $settings.audioCuesEnabled)
                Toggle("Haptic cues on Apple Watch", isOn: $settings.hapticCuesEnabled)
            }

            Section("Notifications") {
                Toggle("Workout reminders", isOn: $settings.workoutRemindersEnabled)
                Toggle("Friend activity", isOn: $settings.friendActivityNotificationsEnabled)
                Toggle("Challenges", isOn: $settings.challengeNotificationsEnabled)
                Toggle("Messages", isOn: $settings.messageNotificationsEnabled)
            }

            Section("Legal") {
                NavigationLink {
                    LegalDocumentView(kind: .terms)
                } label: {
                    Label("Terms of Service", systemImage: "doc.text")
                }

                NavigationLink {
                    LegalDocumentView(kind: .privacy)
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
            }

            Section("Data & account") {
                NavigationLink {
                    Text("Export will package ATHLTH-owned data such as plans, routes and activities. HealthKit export stays under Apple Health controls.")
                        .padding()
                        .navigationTitle("Export Data")
                } label: {
                    Label("Export ATHLTH data", systemImage: "square.and.arrow.up")
                }

                NavigationLink {
                    Text("Blocked users and social safety controls will live here.")
                        .padding()
                        .navigationTitle("Blocked Users")
                } label: {
                    Label("Blocked users", systemImage: "person.crop.circle.badge.xmark")
                }

                NavigationLink {
                    Text("Account deletion will remove ATHLTH cloud data after confirmation. Health data in Apple Health is managed separately.")
                        .padding()
                        .navigationTitle("Delete Account")
                } label: {
                    Label("Delete account", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }

            if session.currentRole.canAccessControlCenter {
                Section("Admin") {
                    NavigationLink {
                        AdminCenterView()
                    } label: {
                        Label("Control Center", systemImage: "lock.rectangle.stack.fill")
                    }

                    LabeledContent("Account role", value: session.currentRole.title)
                }
            }

            Section("Diagnostics") {
                NavigationLink {
                    CapabilityLabView()
                } label: {
                    Label("Capability Lab", systemImage: "testtube.2")
                }

                LabeledContent("Preview mode", value: session.previewModeEnabled ? "Enabled" : "Disabled")
                LabeledContent("App version", value: "0.1.0")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func integrationRow(
        _ integration: IntegrationKind,
        subtitle: String,
        connected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: integration.systemImage)
                .frame(width: 30)
                .foregroundStyle(connected ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(integration.title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: connected ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(connected ? Color.green : Color.secondary)
        }
    }
}
