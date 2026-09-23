import SwiftUI

struct ATHLTHProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var social: SocialStore

    @State private var selectedFocus: TrainingFocus?
    @State private var shareTrainingPresence = false
    @State private var shareGoals = false
    @State private var shareWorkoutTotals = false
    @State private var shareTrophies = false
    @State private var sharePerformance = false
    @State private var shareRecentActivity = false
    @State private var shareRunningPRs = false
    @State private var shareStrengthPRs = false
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
                shareToggle(
                    "Training now status",
                    icon: "figure.run",
                    isOn: $shareTrainingPresence
                )

                shareToggle(
                    "Goals",
                    icon: "target",
                    isOn: $shareGoals
                )

                shareToggle(
                    "Workout totals",
                    icon: "number.circle.fill",
                    isOn: $shareWorkoutTotals
                )

                shareToggle(
                    "Trophies",
                    icon: "trophy.fill",
                    isOn: $shareTrophies
                )

                shareToggle(
                    "Performance stats",
                    icon: "chart.line.uptrend.xyaxis",
                    isOn: $sharePerformance
                )

                shareToggle(
                    "Recent activity",
                    icon: "clock.fill",
                    isOn: $shareRecentActivity
                )

                shareToggle(
                    "Running PRs",
                    icon: "figure.run",
                    isOn: $shareRunningPRs
                )

                shareToggle(
                    "Strength PRs",
                    icon: "dumbbell.fill",
                    isOn: $shareStrengthPRs
                )
            } header: {
                Text("Visible to others")
            } footer: {
                Text("Everything starts off. Turn on only the profile data you explicitly want to share. Your HealthKit data itself is never exposed to other users.")
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

    private func shareToggle(
        _ title: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon)
        }
        .tint(ATHLTHTheme.accent)
    }

    private func loadSharingSettings() {
        guard let privacy = social.privacy else {
            shareTrainingPresence = false
            shareGoals = false
            shareWorkoutTotals = false
            shareTrophies = false
            sharePerformance = false
            shareRecentActivity = false
            shareRunningPRs = false
            shareStrengthPRs = false
            return
        }

        shareTrainingPresence = privacy.shareTrainingPresence
        shareGoals = privacy.shareGoals
        shareWorkoutTotals = privacy.shareWorkoutTotals
        shareTrophies = privacy.shareTrophyCabinet
        sharePerformance = privacy.sharePerformanceStats
        shareRecentActivity = privacy.shareRecentActivity
        shareRunningPRs = privacy.shareRunningPRs
        shareStrengthPRs = privacy.shareStrengthPRs
    }

    @MainActor
    private func save() async {
        guard let selectedFocus else { return }

        saving = true
        errorMessage = nil
        defer { saving = false }

        session.setTrainingFocus(selectedFocus)

        var privacy = social.privacy
            ?? SocialPrivacySettings.fallback(userID: session.profile.userID)

        privacy.shareTrainingPresence = shareTrainingPresence
        privacy.shareGoals = shareGoals
        privacy.shareWorkoutTotals = shareWorkoutTotals
        privacy.shareTrophyCabinet = shareTrophies
        privacy.sharePerformanceStats = sharePerformance
        privacy.shareRecentActivity = shareRecentActivity
        privacy.shareRunningPRs = shareRunningPRs
        privacy.shareStrengthPRs = shareStrengthPRs

        await social.updatePrivacy(privacy)

        if let message = social.errorMessage, !message.isEmpty {
            errorMessage = message
            return
        }

        settings.shareTrainingPresence = shareTrainingPresence
        settings.markProfileSetupCompleted()
        dismiss()
    }
}
