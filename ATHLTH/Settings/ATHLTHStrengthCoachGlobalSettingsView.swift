import SwiftUI

/// Strength Audio Coach defaults shared by planned and quick strength sessions.
/// Existing per-session configuration still takes precedence once training starts.
struct ATHLTHStrengthCoachGlobalSettingsView: View {
    @State private var configuration = StrengthAdvancedConfiguration.savedDefaults()

    private let ink = Color(red: 0.18, green: 0.19, blue: 0.21)
    private let border = Color(red: 0.89, green: 0.89, blue: 0.88)
    private let canvas = Color(red: 0.975, green: 0.976, blue: 0.976)

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Strength coaching", "Styrkeveiledning"))
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Make each set easier to follow without looking at the screen.",
                        "Følg sett, pauser og neste øvelse uten å måtte se på skjermen."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                group {
                    Toggle(
                        tr("Speak during strength workouts", "Bruk stemme under styrketrening"),
                        isOn: $configuration.audioCoach.enabled
                    )
                    .tint(ink)

                    Text(tr(
                        "ATHLTH announces relevant events on the device recording the workout. Your music volume should return after speech.",
                        "ATHLTH varsler om relevante hendelser på enheten som registrerer økten. Musikkvolumet skal tilbake etter talemeldingen."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                group {
                    Text(tr("SET & EXERCISE", "SETT OG ØVELSE"))
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)

                    Toggle(
                        tr("Set completed", "Sett fullført"),
                        isOn: $configuration.audioCoach.announceSetComplete
                    )
                    Toggle(
                        tr("Next exercise and goal", "Neste øvelse og mål"),
                        isOn: $configuration.audioCoach.announceNextExercise
                    )
                    Toggle(
                        tr("Next set, reps and weight", "Neste sett, repetisjoner og vekt"),
                        isOn: Binding(
                            get: {
                                configuration.audioCoach.shouldAnnounceNextSetDetails
                            },
                            set: {
                                configuration.audioCoach.announceNextSetDetails = $0
                            }
                        )
                    )
                }

                group {
                    Text(tr("REST & COUNTDOWN", "PAUSE OG NEDTELLING"))
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)

                    Toggle(
                        tr("Tell me when rest begins", "Varsle når pausen starter"),
                        isOn: $configuration.audioCoach.announceRestStarted
                    )
                    Toggle(
                        tr("Countdown before rest ends", "Nedtelling før pausen er ferdig"),
                        isOn: $configuration.audioCoach.announceRestCountdown
                    )
                    if configuration.audioCoach.announceRestCountdown {
                        Stepper(
                            value: $configuration.audioCoach.restCountdownSeconds,
                            in: 3...30
                        ) {
                            Text(tr("Speak", "Si fra") +
                                 " \(configuration.audioCoach.restCountdownSeconds) " +
                                 tr("seconds before", "sekunder før"))
                        }
                    }
                    Toggle(
                        tr("Tell me when rest is over", "Si fra når pausen er ferdig"),
                        isOn: $configuration.audioCoach.announceRestComplete
                    )
                    Toggle(
                        tr("Haptic feedback", "Haptiske varsler"),
                        isOn: $configuration.restCues.hapticsEnabled
                    )
                }

                group {
                    Text(tr("VOICE & FREQUENCY", "STEMME OG HYPPIGHET"))
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Toggle(
                        tr("Lower music when speaking", "Demp musikk mens coachen snakker"),
                        isOn: $configuration.audioCoach.duckOtherAudio
                    )
                    Toggle(
                        tr("Workout progress updates", "Oppdateringer om øktfremdrift"),
                        isOn: Binding(
                            get: {
                                configuration.audioCoach.shouldAnnounceExerciseProgress
                            },
                            set: {
                                configuration.audioCoach.announceExerciseProgress = $0
                            }
                        )
                    )
                    Toggle(
                        tr("Periodic workout status", "Regelmessig øktstatus"),
                        isOn: $configuration.audioCoach.announceWorkoutStatus
                    )
                    if configuration.audioCoach.announceWorkoutStatus {
                        Picker(
                            tr("Every", "Hvert"),
                            selection: $configuration.audioCoach.workoutStatusIntervalMinutes
                        ) {
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                        .pickerStyle(.menu)
                    }
                }

                Text(tr(
                    "These are default settings. You can change Audio Coach for an individual workout before starting.",
                    "Dette er standardinnstillinger. Du kan tilpasse Audio Coach for den enkelte økten før start."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .background(canvas.ignoresSafeArea())
        .navigationTitle(tr("Strength Audio Coach", "Audio Coach · styrke"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: configuration) { _, newValue in
            newValue.saveAsDefaults()
        }
    }

    private func group<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(19)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(border))
    }
}
