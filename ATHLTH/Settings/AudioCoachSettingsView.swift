import SwiftUI

struct ATHLTHAudioCoachSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        ScrollView {
            ATHLTHPlusFeatureGate(
                feature: .audioCoach,
                title: "Audio Coach is part of ATHLTH+",
                message:
                    "Unlock spoken workout updates, route progress and structured workout guidance."
            ) {
                VStack(spacing: 16) {
                    defaultsCard
                    triggerCard
                    contentCard
                    routeCard
                    structuredWorkoutCard
                    languageCard
                }
            }
            .padding()
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Audio Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultsCard: some View {
        settingsCard(
            title: "Defaults",
            subtitle:
                "These settings are preselected whenever you start a supported workout."
        ) {
            Toggle(
                "Enable by default",
                isOn: $settings.audioCoachEnabledByDefault
            )
        }
    }

    private var triggerCard: some View {
        settingsCard(
            title: "When to speak",
            subtitle:
                "Choose one or both recurring triggers. Structured workout step changes can also speak automatically."
        ) {
            Toggle(
                "Every distance interval",
                isOn: $settings.audioCoachDistanceTriggerEnabled
            )

            if settings.audioCoachDistanceTriggerEnabled {
                pickerRow("Distance interval") {
                    Picker(
                        "Distance interval",
                        selection:
                            $settings.audioCoachDistanceIntervalKilometers
                    ) {
                        Text("0.5 km").tag(0.5)
                        Text("1 km").tag(1.0)
                        Text("2 km").tag(2.0)
                        Text("5 km").tag(5.0)
                    }
                    .pickerStyle(.menu)
                }
            }

            Divider()

            Toggle(
                "Every time interval",
                isOn: $settings.audioCoachTimeTriggerEnabled
            )

            if settings.audioCoachTimeTriggerEnabled {
                pickerRow("Time interval") {
                    Picker(
                        "Time interval",
                        selection:
                            $settings.audioCoachTimeIntervalMinutes
                    ) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var contentCard: some View {
        settingsCard(
            title: "Workout updates",
            subtitle:
                "Choose exactly what recurring Audio Coach updates should include."
        ) {
            Toggle(
                "Distance",
                isOn: $settings.audioCoachAnnounceDistance
            )
            Toggle(
                "Elapsed time",
                isOn: $settings.audioCoachAnnounceElapsedTime
            )
            Toggle(
                "Average pace",
                isOn: $settings.audioCoachAnnounceAveragePace
            )
            Toggle(
                "Current time",
                isOn: $settings.audioCoachAnnounceClockTime
            )
            Toggle(
                "Heart rate",
                isOn: $settings.audioCoachAnnounceHeartRate
            )
        }
    }

    private var routeCard: some View {
        settingsCard(
            title: "Route progress",
            subtitle:
                "Used when the workout has a known ATHLTH route."
        ) {
            Toggle(
                "Remaining distance",
                isOn:
                    $settings.audioCoachAnnounceRemainingRouteDistance
            )
            Toggle(
                "Estimated time remaining",
                isOn:
                    $settings
                        .audioCoachAnnounceEstimatedRemainingRouteTime
            )
        }
    }

    private var structuredWorkoutCard: some View {
        settingsCard(
            title: "Structured workouts",
            subtitle:
                "Guidance for intervals, tempo blocks and other running workout steps."
        ) {
            Toggle(
                "Announce current / next step",
                isOn:
                    $settings.audioCoachAnnounceCurrentWorkoutStep
            )
            Toggle(
                "Remaining time in step",
                isOn:
                    $settings.audioCoachAnnounceRemainingStepTime
            )
            Toggle(
                "Remaining distance in step",
                isOn:
                    $settings.audioCoachAnnounceRemainingStepDistance
            )
        }
    }

    private var languageCard: some View {
        settingsCard(
            title: "Voice",
            subtitle:
                "The selected language is used for Audio Coach speech on Apple Watch."
        ) {
            pickerRow("Language") {
                Picker(
                    "Language",
                    selection: $settings.audioCoachLanguage
                ) {
                    ForEach(
                        WatchAudioCoachLanguage.allCases,
                        id: \.rawValue
                    ) { language in
                        Text(language.title)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            Text(
                "System uses the Apple Watch language when an appropriate voice is available."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pickerRow<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            trailing()
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(18)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.05),
                lineWidth: 1
            )
        }
    }
}
