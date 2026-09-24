import SwiftUI

struct WorkoutStartOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var social: SocialStore

    let session: PlannedSession
    let trainingDeviceProvider: TrainingDeviceProvider
    let watchConnected: Bool
    let linkedSpotifyPlaylist: SpotifyPlaylistReference?
    let spotifyAutoplayEnabled: Bool
    let onStart: (
        WorkoutCaptureDevice,
        StrengthTrackingMode,
        [SocialProfileCard]
    ) -> Void

    @State private var captureDevice: WorkoutCaptureDevice
    @State private var trackingMode: StrengthTrackingMode
    @State private var selectedFriendIDs: Set<UUID> = []

    init(
        session: PlannedSession,
        trainingDeviceProvider: TrainingDeviceProvider,
        watchConnected: Bool,
        defaultCapture: WorkoutCapturePreference,
        defaultTracking: StrengthTrackingPreference,
        linkedSpotifyPlaylist: SpotifyPlaylistReference?,
        spotifyAutoplayEnabled: Bool,
        onStart: @escaping (
            WorkoutCaptureDevice,
            StrengthTrackingMode,
            [SocialProfileCard]
        ) -> Void
    ) {
        self.session = session
        self.trainingDeviceProvider = trainingDeviceProvider
        self.watchConnected = watchConnected
        self.linkedSpotifyPlaylist = linkedSpotifyPlaylist
        self.spotifyAutoplayEnabled = spotifyAutoplayEnabled
        self.onStart = onStart

        let initialDevice: WorkoutCaptureDevice
        switch defaultCapture {
        case .appleWatch
            where trainingDeviceProvider == .appleWatch && watchConnected:
            initialDevice = .appleWatch
        case .automatic
            where trainingDeviceProvider == .appleWatch && watchConnected:
            initialDevice = .appleWatch
        default:
            initialDevice = .iPhone
        }

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
                                subtitle: "Works without Apple Watch. Start and finish the workout in ATHLTH.",
                                icon: "iphone",
                                selected: captureDevice == .iPhone
                            ) {
                                captureDevice = .iPhone
                            }

                            if trainingDeviceProvider == .appleWatch {
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
                            } else if trainingDeviceProvider == .garmin {
                                optionRow(
                                    title: "Garmin",
                                    subtitle: "Garmin sync is prepared, but workout authorization is pending Garmin approval. Use iPhone/manual capture for now.",
                                    icon: "watch.analog",
                                    selected: false,
                                    disabled: true
                                ) {}
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

                    ATHLTHCard {
                        WorkoutFriendPicker(
                            selectedFriendIDs: $selectedFriendIDs
                        )
                    }

                    ATHLTHCard {
                        Label(deviceInfoTitle, systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.accent)

                        Text(deviceInfoDetail)
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
                            selectedFriends
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

    private var deviceInfoTitle: String {
        switch trainingDeviceProvider {
        case .appleWatch:
            return "Apple Watch is optional"
        case .garmin:
            return "Garmin sync is pending"
        case .none:
            return "No watch required"
        }
    }

    private var deviceInfoDetail: String {
        switch trainingDeviceProvider {
        case .appleWatch:
            return "You can still record this strength workout on iPhone if Apple Watch is unavailable."
        case .garmin:
            return "Until Garmin authorization is available, ATHLTH keeps the full strength log on iPhone. Garmin-derived metrics will plug into the same data model later."
        case .none:
            return "Strength workouts are recorded safely on iPhone. Missing wearable metrics stay empty instead of blocking or crashing the workout."
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
