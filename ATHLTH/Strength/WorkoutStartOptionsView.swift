import SwiftUI

struct WorkoutStartOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore

    let session: PlannedSession
    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let onStart: (
        WorkoutCaptureDevice,
        StrengthTrackingMode,
        [SocialProfileCard],
        WatchAudioCoachConfiguration
    ) -> Void

    @State private var captureDevice: WorkoutCaptureDevice
    @State private var trackingMode: StrengthTrackingMode
    @State private var selectedFriendIDs: Set<UUID> = []
    @State private var audioCoachDraft = AudioCoachDraft()
    @State private var audioCoachLoaded = false

    init(
        session: PlannedSession,
        trainingDeviceProvider: TrainingDeviceProvider,
        watchConnected: Bool,
        defaultCapture: WorkoutCapturePreference,
        defaultTracking: StrengthTrackingPreference,
        onStart: @escaping (
            WorkoutCaptureDevice,
            StrengthTrackingMode,
            [SocialProfileCard],
            WatchAudioCoachConfiguration
        ) -> Void
    ) {
        self.session = session
        self.trainingDeviceProvider = trainingDeviceProvider
        self.watchConnected = watchConnected
        self.onStart = onStart

        // Workout capture is chosen for this workout only.
        // Legacy Settings preferences must not silently decide the device.
        let initialDevice: WorkoutCaptureDevice =
            watchConnected ? .appleWatch : .iPhone

        _captureDevice = State(initialValue: initialDevice)
        _trackingMode = State(
            initialValue: defaultTracking == .advanced ? .advanced : .simple
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHCard {
                        Text(session.title)
                            .font(.title2.weight(.bold))
                        Text("Choose how you want to record this workout.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Workout device")

                        VStack(spacing: 10) {
                            optionRow(
                                title: "iPhone",
                                subtitle: "Record and finish this workout directly in ATHLTH. Keep your iPhone with you.",
                                icon: "iphone",
                                selected: captureDevice == .iPhone
                            ) {
                                captureDevice = .iPhone
                            }

                            optionRow(
                                title: "Apple Watch",
                                subtitle: watchConnected
                                    ? "Record the continuous workout on Apple Watch."
                                    : "Finish Apple Watch setup in Settings to use this option.",
                                icon: "applewatch",
                                selected: captureDevice == .appleWatch,
                                disabled: !watchConnected
                            ) {
                                captureDevice = .appleWatch
                            }
                        }
                        .padding(.top, 12)
                    }

                    ATHLTHCard {
                        ATHLTHSectionHeader(title: "Strength tracking")

                        VStack(spacing: 10) {
                            optionRow(
                                title: "Simple",
                                subtitle: "Only start, duration and finish. No sets, reps, weight or rest required.",
                                icon: "play.circle.fill",
                                selected: trackingMode == .simple
                            ) {
                                trackingMode = .simple
                            }

                            optionRow(
                                title: "Advanced",
                                subtitle: "Track exercises, sets, reps, weight, RPE and optional rest timers.",
                                icon: "list.bullet.clipboard.fill",
                                selected: trackingMode == .advanced
                            ) {
                                trackingMode = .advanced
                            }
                        }
                        .padding(.top, 12)
                    }

                    if captureDevice == .appleWatch {
                        AudioCoachSetupCard(
                            draft: $audioCoachDraft,
                            showRouteOptions: false,
                            showStructuredOptions: false
                        )
                    }

                    ATHLTHCard {
                        WorkoutFriendPicker(
                            selectedFriendIDs: $selectedFriendIDs
                        )
                    }

                    ATHLTHCard {
                        Label("Choose for each workout", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.accent)

                        Text("This device choice applies only to the workout you are about to start. You can choose differently next time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }

                    Button {
                        let selectedFriends = social.friends.filter {
                            selectedFriendIDs.contains($0.userID)
                        }
                        onStart(
                            captureDevice,
                            trackingMode,
                            selectedFriends,
                            audioCoachDraft.configuration()
                        )
                        dismiss()
                    } label: {
                        Label(
                            captureDevice == .appleWatch ? "Start with Apple Watch" : "Start on iPhone",
                            systemImage: captureDevice == .appleWatch ? "applewatch" : "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.accent)
                }
                .padding()
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !audioCoachLoaded {
                    audioCoachDraft.load(from: settings)
                    audioCoachLoaded = true
                }

                if social.friends.isEmpty {
                    await social.refresh()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionRow(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(disabled ? Color.secondary : ATHLTHTheme.accent)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? ATHLTHTheme.accent : Color.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}
