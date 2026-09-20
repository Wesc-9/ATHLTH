import SwiftUI

struct WorkoutStartOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    let session: PlannedSession
    let watchConnected: Bool
    let linkedSpotifyPlaylist: SpotifyPlaylistReference?
    let spotifyAutoplayEnabled: Bool
    let onStart: (WorkoutCaptureDevice, StrengthTrackingMode) -> Void

    @State private var captureDevice: WorkoutCaptureDevice
    @State private var trackingMode: StrengthTrackingMode

    init(
        session: PlannedSession,
        watchConnected: Bool,
        defaultCapture: WorkoutCapturePreference,
        defaultTracking: StrengthTrackingPreference,
        linkedSpotifyPlaylist: SpotifyPlaylistReference?,
        spotifyAutoplayEnabled: Bool,
        onStart: @escaping (WorkoutCaptureDevice, StrengthTrackingMode) -> Void
    ) {
        self.session = session
        self.watchConnected = watchConnected
        self.linkedSpotifyPlaylist = linkedSpotifyPlaylist
        self.spotifyAutoplayEnabled = spotifyAutoplayEnabled
        self.onStart = onStart

        let initialDevice: WorkoutCaptureDevice
        switch defaultCapture {
        case .appleWatch where watchConnected:
            initialDevice = .appleWatch
        case .automatic where watchConnected:
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

                            optionRow(
                                title: "Apple Watch",
                                subtitle: watchConnected
                                    ? "Record the continuous workout on Apple Watch."
                                    : "Connect Apple Watch in Settings to use this option.",
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

                    if let playlist = linkedSpotifyPlaylist {
                        ATHLTHCard {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.title2)
                                    .foregroundStyle(.green)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Spotify")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(playlist.name)
                                        .font(.headline)
                                    Text(
                                        spotifyAutoplayEnabled
                                            ? "Starts automatically with this workout."
                                            : "Linked to the plan, but autoplay is off."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                    }

                    ATHLTHCard {
                        Label("Apple Watch is optional", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("Detailed strength tracking is optional too. HealthKit metrics can be linked later when available, while ATHLTH keeps the strength log separate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }

                    Button {
                        onStart(captureDevice, trackingMode)
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
                    .tint(.green)
                }
                .padding()
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
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
                    .foregroundStyle(disabled ? Color.secondary : Color.green)
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
                    .foregroundStyle(selected ? Color.green : Color.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}
