import SwiftUI

/// A dedicated heart-rate screen for the active run/walk pager.
/// Reads HealthKit-derived data from the existing WatchWorkoutManager.
struct WatchRunHeartRateDetailPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @ScaledMetric(relativeTo: .largeTitle) private var pulseSize: CGFloat = 48

    private var spokenNorwegian: Bool {
        ATHLTHLocalization.choose(english: "en", norwegian: "no") == "no"
    }

    private var target: WatchWorkoutTargetAlertConfiguration? {
        workout.targetAlertConfiguration?.heartRateEnabled == true
            ? workout.targetAlertConfiguration : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "HEART RATE", norwegian: "PULS"
                    ),
                    systemImage: "heart.fill"
                )
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WatchTheme.liveHeart)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(bpm(workout.hasFreshHeartRate ? workout.heartRate : nil))
                            .font(.system(
                                size: pulseSize, weight: .bold, design: .rounded
                            ))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("bpm")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WatchTheme.muted)
                    }

                    Text(workout.hasFreshHeartRate
                         ? ATHLTHLocalization.choose(
                            english: "CURRENT PULSE",
                            norwegian: "NÅVÆRENDE PULS"
                         )
                         : ATHLTHLocalization.choose(
                            english: "WAITING FOR SENSOR",
                            norwegian: "VENTER PÅ SENSOR"
                         ))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .watchSurface(radius: 17)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Current heart rate", norwegian: "Nåværende puls"
                ))
                .accessibilityValue(
                    ATHLTHWorkoutAccessibleMetric.pulse(
                        workout.heartRate,
                        isFresh: workout.hasFreshHeartRate,
                        norwegian: spokenNorwegian
                    )
                )

                HStack(spacing: 7) {
                    readout(
                        label: ATHLTHLocalization.choose(
                            english: "AVERAGE", norwegian: "SNITT"
                        ),
                        value: bpm(workout.averageHeartRate)
                    )
                    readout(
                        label: ATHLTHLocalization.choose(
                            english: "MAXIMUM", norwegian: "MAKS"
                        ),
                        value: bpm(workout.maxHeartRate)
                    )
                }

                if let target {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "target")
                            Text(ATHLTHLocalization.choose(
                                english: "HEART-RATE TARGET",
                                norwegian: "PULSMÅL"
                            ))
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.accentDeep)

                        if let zone = target.heartRateZone {
                            Text(ATHLTHLocalization.choose(
                                english: "Zone \(zone)",
                                norwegian: "Sone \(zone)"
                            ))
                            .font(.system(size: 18, weight: .bold))
                        }

                        if let low = target.heartRateMinimumBPM,
                           let high = target.heartRateMaximumBPM {
                            Text("\(Int(low.rounded()))–\(Int(high.rounded())) bpm")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                        }

                        let guidance = ATHLTHRunPulseTargetStatus.resolve(
                            heartRate: workout.hasFreshHeartRate
                                ? workout.heartRate : nil,
                            minimum: target.heartRateMinimumBPM,
                            maximum: target.heartRateMaximumBPM
                        )
                        Label(
                            guidanceText(guidance),
                            systemImage: guidance == .within
                                ? "checkmark.circle.fill"
                                : guidance == .below || guidance == .above
                                    ? "exclamationmark.circle.fill"
                                    : "waveform.path.ecg"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            guidance == .within
                                ? WatchTheme.liveAction
                                : guidance == .below || guidance == .above
                                    ? WatchTheme.warning
                                    : WatchTheme.muted
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .watchSurface(radius: 17)
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private func readout(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.textSecondary)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text("bpm")
                .font(.system(size: 9))
                .foregroundStyle(WatchTheme.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 16)
    }

    private func guidanceText(_ status: ATHLTHRunPulseTargetStatus)
        -> String {
        switch status {
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "Target not configured",
                norwegian: "Pulsmål ikke konfigurert"
            )
        case .waiting:
            return ATHLTHLocalization.choose(
                english: "Waiting for heart rate",
                norwegian: "Venter på puls"
            )
        case .below:
            return ATHLTHLocalization.choose(
                english: "Below target zone",
                norwegian: "Under målsonen"
            )
        case .within:
            return ATHLTHLocalization.choose(
                english: "Within target zone",
                norwegian: "Innenfor målsonen"
            )
        case .above:
            return ATHLTHLocalization.choose(
                english: "Above target zone",
                norwegian: "Over målsonen"
            )
        }
    }

    private func bpm(_ value: Double?) -> String {
        guard let value, value.isFinite && value > 0 else { return "—" }
        return String(Int(value.rounded()))
    }
}

/// Audio Coach is reachable as a first-class active-running page, instead
/// of requiring the user to find its controls inside the stop/pause screen.
struct WatchRunAudioCoachDetailPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    "AUDIO COACH",
                    systemImage: "waveform"
                )
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WatchTheme.accentDeep)

                HStack(spacing: 9) {
                    Image(systemName:
                        workout.audioCoachConfiguration.enabled
                            ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .font(.system(size: 23))
                    .foregroundStyle(WatchTheme.liveAction)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.audioCoachConfiguration.enabled
                            ? ATHLTHLocalization.choose(
                                english: "Coach active",
                                norwegian: "Coach aktiv"
                              )
                            : ATHLTHLocalization.choose(
                                english: "Coach off",
                                norwegian: "Coach av"
                              ))
                            .font(.system(size: 15, weight: .bold))
                        Text(ATHLTHLocalization.choose(
                            english: "Voice guidance during training",
                            norwegian: "Stemmeveiledning under trening"
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.muted)
                        .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .watchSurface(radius: 17)

                Button {
                    workout.setAudioCoachEnabled(
                        !workout.audioCoachConfiguration.enabled
                    )
                } label: {
                    Label(workout.audioCoachConfiguration.enabled
                        ? ATHLTHLocalization.choose(
                            english: "Disable coach", norwegian: "Slå av coach")
                        : ATHLTHLocalization.choose(
                            english: "Enable coach", norwegian: "Slå på coach"),
                        systemImage: "waveform"
                    )
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.liveAction)

                if workout.audioCoachConfiguration.enabled {
                    HStack(spacing: 7) {
                        Button {
                            workout.setCoachSpeechPaused(
                                !workout.coachSpeechPaused
                            )
                        } label: {
                            Label(
                                workout.coachSpeechPaused
                                    ? ATHLTHLocalization.choose(
                                        english: "Resume voice",
                                        norwegian: "Tale på")
                                    : ATHLTHLocalization.choose(
                                        english: "Pause voice",
                                        norwegian: "Pause tale"),
                                systemImage:
                                    workout.coachSpeechPaused
                                        ? "play.fill" : "pause.fill"
                            )
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            workout.announceCoachStatusNow()
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Status", norwegian: "Status"
                                ),
                                systemImage: "waveform"
                            )
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                        .disabled(workout.coachSpeechPaused)
                    }

                    if let message = workout.lastCoachMessage,
                       !message.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "LAST MESSAGE",
                                norwegian: "SISTE BESKJED"
                            ))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(WatchTheme.muted)
                            Text(message)
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                workout.replayLastCoachMessage()
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Play again",
                                        norwegian: "Spill av igjen"
                                    ),
                                    systemImage: "arrow.counterclockwise"
                                )
                                .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                            .disabled(!workout.canReplayLastCoachMessage)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .watchSurface(radius: 16)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(WatchTheme.canvas.ignoresSafeArea())
    }
}
