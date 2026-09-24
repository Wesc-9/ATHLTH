import SwiftUI

struct ATHLTHProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var social: SocialStore

    @State private var selectedFocus: TrainingFocus?
    @State private var trainingFocusVisibility: ProfileVisibility = .privateOnly
    @State private var trainingStatusVisibility: ProfileVisibility = .privateOnly
    @State private var performanceVisibility: ProfileVisibility = .privateOnly
    @State private var trophyVisibility: ProfileVisibility = .privateOnly
    @State private var goalsVisibility: ProfileVisibility = .privateOnly
    @State private var activityVisibility: ProfileVisibility = .privateOnly
    @State private var runningPRVisibility: ProfileVisibility = .privateOnly
    @State private var strengthPRVisibility: ProfileVisibility = .privateOnly
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Make your profile yours")
                        .font(.title2.weight(.bold))

                    Text("Choose how you train, what you want to see on your own profile, and what other people are allowed to see.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(TrainingFocus.allCases) { focus in
                        trainingFocusButton(focus)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Training focus")
            } footer: {
                Text("This personalizes ATHLTH. Your training focus is not shared automatically.")
            }

            Section {
                profileToggle(
                    "Training focus",
                    icon: "bolt.heart.fill",
                    isOn: $settings.showTrainingFocusOnProfile
                )

                profileToggle(
                    "Training status",
                    icon: "figure.run",
                    isOn: $settings.showTrainingStatusOnProfile
                )

                profileToggle(
                    "Current goal",
                    icon: "target",
                    isOn: $settings.showCurrentGoalOnProfile
                )

                profileToggle(
                    "Profile stats",
                    icon: "chart.bar.fill",
                    isOn: $settings.showProfileStatsOnProfile
                )

                profileToggle(
                    "Performance stats",
                    icon: "chart.line.uptrend.xyaxis",
                    isOn: $settings.showPerformanceStatsOnProfile
                )

                profileToggle(
                    "Workout history",
                    icon: "clock.arrow.circlepath",
                    isOn: $settings.showWorkoutHistoryOnProfile
                )
            } header: {
                Text("What I want on my profile")
            } footer: {
                Text("These controls only change your own profile layout. They do not give anyone else access to the data.")
            }

            Section {
                visibilityRow(
                    "Training focus",
                    icon: "bolt.heart.fill",
                    selection: $trainingFocusVisibility
                )

                visibilityRow(
                    "Training status",
                    icon: "figure.run",
                    selection: $trainingStatusVisibility
                )

                visibilityRow(
                    "Performance stats",
                    icon: "chart.line.uptrend.xyaxis",
                    selection: $performanceVisibility
                )

                visibilityRow(
                    "Trophies",
                    icon: "trophy.fill",
                    selection: $trophyVisibility
                )

                visibilityRow(
                    "Goal updates",
                    icon: "target",
                    selection: $goalsVisibility
                )

                visibilityRow(
                    "Recent activity",
                    icon: "clock.fill",
                    selection: $activityVisibility
                )

                visibilityRow(
                    "Running PR updates",
                    icon: "figure.run",
                    selection: $runningPRVisibility
                )

                visibilityRow(
                    "Strength PR updates",
                    icon: "dumbbell.fill",
                    selection: $strengthPRVisibility
                )
            } header: {
                Text("Visible to others")
            } footer: {
                Text("Every section starts Off. Friends limits it to accepted friends. Public makes that section visible to other ATHLTH users who can open your profile.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Save Profile Setup")
                        Spacer()
                        if saving {
                            ProgressView()
                        }
                    }
                }
                .disabled(selectedFocus == nil || saving)
            }
        }
        .navigationTitle("Profile Setup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            selectedFocus = session.onboardingProfile?.trainingFocus
            await social.refresh()
            loadSharingSettings()
        }
    }

    private func trainingFocusButton(_ focus: TrainingFocus) -> some View {
        let selected = selectedFocus == focus

        return Button {
            selectedFocus = focus
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: focus.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            selected
                                ? ATHLTHTheme.accent
                                : Color.primary
                        )

                    Spacer()

                    Image(
                        systemName: selected
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        selected
                            ? ATHLTHTheme.accent
                            : Color.secondary
                    )
                }

                Text(focus.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(focus.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(
                selected
                    ? ATHLTHTheme.accentSoft
                    : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selected
                            ? ATHLTHTheme.accent.opacity(0.36)
                            : Color.primary.opacity(0.05),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func profileToggle(
        _ title: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon)
        }
        .tint(ATHLTHTheme.accent)
    }

    private func visibilityRow(
        _ title: String,
        icon: String,
        selection: Binding<ProfileVisibility>
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))

            Picker(title, selection: selection) {
                Text("Off").tag(ProfileVisibility.privateOnly)
                Text("Friends").tag(ProfileVisibility.friends)
                Text("Public").tag(ProfileVisibility.publicProfile)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 3)
    }

    private func loadSharingSettings() {
        guard let privacy = social.privacy else {
            trainingFocusVisibility = .privateOnly
            trainingStatusVisibility = .privateOnly
            performanceVisibility = .privateOnly
            trophyVisibility = .privateOnly
            goalsVisibility = .privateOnly
            activityVisibility = .privateOnly
            runningPRVisibility = .privateOnly
            strengthPRVisibility = .privateOnly
            return
        }

        trainingFocusVisibility =
            ProfileVisibility(rawValue: privacy.trainingFocusVisibility)
            ?? .privateOnly
        trainingStatusVisibility =
            ProfileVisibility(rawValue: privacy.trainingPresenceVisibility)
            ?? .privateOnly
        performanceVisibility =
            ProfileVisibility(rawValue: privacy.performanceStatsVisibility)
            ?? .privateOnly
        trophyVisibility =
            ProfileVisibility(rawValue: privacy.trophyCabinetVisibility)
            ?? .privateOnly
        goalsVisibility =
            ProfileVisibility(rawValue: privacy.goalsVisibility)
            ?? .privateOnly
        activityVisibility =
            ProfileVisibility(rawValue: privacy.recentActivityVisibility)
            ?? .privateOnly
        runningPRVisibility =
            ProfileVisibility(rawValue: privacy.runningPRsVisibility)
            ?? .privateOnly
        strengthPRVisibility =
            ProfileVisibility(rawValue: privacy.strengthPRsVisibility)
            ?? .privateOnly
    }

    private var broadestProfileVisibility: ProfileVisibility {
        let values = [
            trainingFocusVisibility,
            trainingStatusVisibility,
            performanceVisibility,
            trophyVisibility,
            goalsVisibility,
            activityVisibility,
            runningPRVisibility,
            strengthPRVisibility
        ]

        if values.contains(.publicProfile) {
            return .publicProfile
        }
        if values.contains(.friends) {
            return .friends
        }
        return .privateOnly
    }

    @MainActor
    private func save() async {
        guard let selectedFocus else { return }

        saving = true
        errorMessage = nil
        defer { saving = false }

        session.setTrainingFocus(selectedFocus)
        await social.syncOwnTrainingFocus(selectedFocus)

        if let message = social.errorMessage, !message.isEmpty {
            errorMessage = message
            return
        }

        var privacy = social.privacy
            ?? SocialPrivacySettings.fallback(userID: session.profile.userID)

        privacy.trainingFocusVisibility = trainingFocusVisibility.rawValue
        privacy.trainingPresenceVisibility = trainingStatusVisibility.rawValue
        privacy.performanceStatsVisibility = performanceVisibility.rawValue
        privacy.trophyCabinetVisibility = trophyVisibility.rawValue
        privacy.goalsVisibility = goalsVisibility.rawValue
        privacy.recentActivityVisibility = activityVisibility.rawValue
        privacy.runningPRsVisibility = runningPRVisibility.rawValue
        privacy.strengthPRsVisibility = strengthPRVisibility.rawValue

        privacy.shareTrainingPresence =
            trainingStatusVisibility != .privateOnly
        privacy.sharePerformanceStats =
            performanceVisibility != .privateOnly
        privacy.shareTrophyCabinet =
            trophyVisibility != .privateOnly
        privacy.shareGoals =
            goalsVisibility != .privateOnly
        privacy.shareRecentActivity =
            activityVisibility != .privateOnly
        privacy.shareRunningPRs =
            runningPRVisibility != .privateOnly
        privacy.shareStrengthPRs =
            strengthPRVisibility != .privateOnly

        // Workout totals are part of the performance section.
        privacy.shareWorkoutTotals =
            performanceVisibility != .privateOnly

        privacy.profileVisibility = broadestProfileVisibility.rawValue
        privacy.discoverable =
            broadestProfileVisibility == .publicProfile

        await social.updatePrivacy(privacy)

        if let message = social.errorMessage, !message.isEmpty {
            errorMessage = message
            return
        }

        settings.profileVisibility = broadestProfileVisibility
        settings.defaultActivityVisibility = .privateOnly
        settings.shareTrainingPresence =
            trainingStatusVisibility != .privateOnly
        settings.markProfileSetupCompleted()
        dismiss()
    }
}
