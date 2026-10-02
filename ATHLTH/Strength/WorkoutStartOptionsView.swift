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
        // A workout started from iPhone stays on iPhone unless the user
        // explicitly chooses Apple Watch in this sheet.
        let initialDevice: WorkoutCaptureDevice =
            .iPhone

        _captureDevice = State(initialValue: initialDevice)
        _trackingMode = State(
            initialValue: defaultTracking == .advanced ? .advanced : .simple
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    strengthIntroCard

                    ATHLTHCard {
                        HStack(spacing: 8) {
                            RoundedRectangle(
                                cornerRadius: 2,
                                style: .continuous
                            )
                            .fill(
                                ATHLTHTheme
                                    .premiumGold
                            )
                            .frame(
                                width: 4,
                                height: 26
                            )

                            Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Workout device",
                                    norwegian:
                                        "Treningsenhet"
                                )
                            )
                            .font(
                                .title3.weight(
                                    .bold
                                )
                            )

                            Spacer()
                        }

                        HStack(spacing: 10) {
                            deviceTile(
                                title: "iPhone",
                                icon: "iphone",
                                selected:
                                    captureDevice == .iPhone,
                                disabled: false
                            ) {
                                captureDevice = .iPhone
                            }

                            deviceTile(
                                title: "Apple Watch",
                                icon: "applewatch",
                                selected:
                                    captureDevice == .appleWatch,
                                disabled: !watchConnected
                            ) {
                                captureDevice =
                                    .appleWatch
                            }
                        }
                        .padding(.top, 10)

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "This choice applies only to this workout.",
                                norwegian:
                                    "Valget gjelder bare denne økten."
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    }

                    if trackingMode == .advanced {
                        VStack(spacing: 12) {
                            if captureDevice == .appleWatch {
                                AudioCoachSetupCard(
                                    draft:
                                        $audioCoachDraft,
                                    showRouteOptions: false,
                                    showStructuredOptions:
                                        false
                                )
                            }

                            ATHLTHCard {
                                WorkoutFriendPicker(
                                    selectedFriendIDs:
                                        $selectedFriendIDs
                                )
                            }
                        }
                        .transition(
                            .opacity
                                .combined(
                                    with: .move(
                                        edge: .top
                                    )
                                )
                        )
                    }

                    Button {
                        let selectedFriends =
                            trackingMode == .advanced
                                ? social.trainingPartners
                                    .filter {
                                        selectedFriendIDs
                                            .contains(
                                                $0.userID
                                            )
                                    }
                                : []

                        onStart(
                            captureDevice,
                            trackingMode,
                            selectedFriends,
                            trackingMode == .advanced &&
                                captureDevice ==
                                .appleWatch
                                ? audioCoachDraft
                                    .configuration()
                                : .disabled
                        )
                        dismiss()
                    } label: {
                        Label(
                            captureDevice == .appleWatch
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Start with Apple Watch",
                                    norwegian:
                                        "Start med Apple Watch"
                                )
                                : ATHLTHLocalization.choose(
                                    english:
                                        "Start on iPhone",
                                    norwegian:
                                        "Start på iPhone"
                                ),
                            systemImage:
                                captureDevice ==
                                .appleWatch
                                    ? "applewatch"
                                    : "play.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(ATHLTHTheme.vitality)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .animation(
                    .easeInOut(duration: 0.18),
                    value: trackingMode
                )
            }
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english: "Start Workout",
                    norwegian: "Start økt"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !audioCoachLoaded {
                    audioCoachDraft.load(
                        from: settings
                    )
                    audioCoachLoaded = true
                }

                if social.trainingPartners.isEmpty {
                    await social.refresh()
                }
            }
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var strengthIntroCard: some View {
        ZStack {
            Image(
                "StrengthPostWorkoutHero"
            )
            .resizable()
            .scaledToFill()
            .frame(height: 118)
            .clipped()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.68),
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(
                alignment: .top,
                spacing: 12
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(session.title)
                        .font(
                            .title2.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.82
                        )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                trackingMode == .advanced
                                    ? "Detailed tracking, exercise by exercise."
                                    : "Fast setup. Add the exercises you want next.",
                            norwegian:
                                trackingMode == .advanced
                                    ? "Detaljert registrering, øvelse for øvelse."
                                    : "Raskt oppsett. Legg til øvelsene du ønsker på neste side."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        Color.white.opacity(
                            0.84
                        )
                    )
                    .lineLimit(2)
                }

                Spacer(minLength: 6)

                trackingModeButton
            }
            .padding(16)
        }
        .frame(height: 118)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    0.22
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.08
                ),
            radius: 16,
            y: 8
        )
    }

    private var trackingModeButton: some View {
        Button {
            trackingMode =
                trackingMode == .advanced
                    ? .simple
                    : .advanced
        } label: {
            HStack(spacing: 6) {
                Image(
                    systemName:
                        trackingMode == .advanced
                            ? "slider.horizontal.3"
                            : "bolt.fill"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .semibold
                    )
                )

                Text(
                    trackingMode == .advanced
                        ? ATHLTHLocalization.choose(
                            english: "Advanced",
                            norwegian: "Avansert"
                        )
                        : "Basic"
                )
                .font(
                    .caption
                        .weight(.bold)
                )
            }
            .foregroundStyle(
                Color.white
            )
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                trackingMode == .advanced
                    ? ATHLTHTheme.vitality
                    : Color.black.opacity(
                        0.34
                    ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.white.opacity(
                            0.24
                        ),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english:
                    "Switch strength setup mode",
                norwegian:
                    "Bytt oppsettsmodus for styrke"
            )
        )
    }

    @ViewBuilder
    private func deviceTile(
        title: String,
        icon: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 20,
                            weight: .semibold
                        )
                    )

                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .lineLimit(1)

                Image(
                    systemName:
                        selected
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .font(.caption)
            }
            .foregroundStyle(
                disabled
                    ? Color.secondary
                    : selected
                        ? Color.white
                        : ATHLTHTheme
                            .primaryText
            )
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(
                disabled
                    ? Color.primary.opacity(0.03)
                    : selected
                        ? ATHLTHTheme.accent
                        : ATHLTHTheme.accentSoft
                            .opacity(0.48),
                in: RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
                .stroke(
                    selected && !disabled
                        ? ATHLTHTheme.accent
                        : Color.primary
                            .opacity(0.06),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.56 : 1)
    }

}
