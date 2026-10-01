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
                VStack(spacing: 14) {
                    ATHLTHCard {
                        HStack(
                            alignment: .top,
                            spacing: 12
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Text(session.title)
                                    .font(
                                        .title2
                                            .weight(.bold)
                                    )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            trackingMode == .advanced
                                                ? "Advanced tracking and workout options."
                                                : "A fast setup with only the essentials.",
                                        norwegian:
                                            trackingMode == .advanced
                                                ? "Avansert registrering og flere treningsvalg."
                                                : "Raskt oppsett med bare det viktigste."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            trackingModeButton
                        }
                    }

                    ATHLTHCard {
                        HStack {
                            ATHLTHSectionHeader(
                                title:
                                    ATHLTHLocalization.choose(
                                        english: "Workout device",
                                        norwegian: "Treningsenhet"
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
                                HStack {
                                    Label(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "Train with someone",
                                            norwegian:
                                                "Tren med noen"
                                        ),
                                        systemImage:
                                            "person.2.fill"
                                    )
                                    .font(.headline)
                                    .foregroundStyle(
                                        ATHLTHTheme.accent
                                    )

                                    Spacer()
                                }

                                WorkoutFriendPicker(
                                    selectedFriendIDs:
                                        $selectedFriendIDs
                                )
                                .padding(.top, 8)
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
                    .tint(ATHLTHTheme.accent)
                }
                .padding()
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
                trackingMode == .advanced
                    ? Color.white
                    : ATHLTHTheme.accentDeep
            )
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                trackingMode == .advanced
                    ? ATHLTHTheme.accent
                    : ATHLTHTheme.accentSoft,
                in: Capsule()
            )
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
