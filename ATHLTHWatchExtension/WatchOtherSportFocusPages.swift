import SwiftUI

/// First-class Watch workout pages for sports without an interval or set
/// engine. Every number originates in WatchWorkoutManager (HealthKit).
/// This page neither creates a session nor advances a phase.
struct WatchOtherSportFocusPage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    private var measuredDistance: Bool {
        ATHLTHOtherSportLiveResolver.resolve(
            kind: workout.kind,
            distanceMeters: workout.distanceMeters
        ) == .measuredDistance
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Label(
                        workout.kind.title,
                        systemImage: workout.kind.systemImage
                    )
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WatchTheme.liveAction)
                    .lineLimit(1)

                    Spacer(minLength: 0)

                    if workout.state == .paused {
                        Text(ATHLTHLocalization.choose(
                            english: "PAUSED", norwegian: "PAUSE"
                        ))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.warning)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        measuredDistance
                            ? ATHLTHLocalization.choose(
                                english: "RECORDED DISTANCE",
                                norwegian: "MÅLT DISTANSE"
                              )
                            : ATHLTHLocalization.choose(
                                english: "WORKOUT TIME",
                                norwegian: "ØKTTID"
                              )
                    )
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(WatchTheme.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(measuredDistance
                             ? String(format: "%.2f",
                                 max(workout.distanceMeters, 0) / 1_000)
                             : timeText(workout.elapsedTime))
                            .font(.system(size: 41, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.62)
                            .lineLimit(1)

                        if measuredDistance {
                            Text("km")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(WatchTheme.liveAction)
                        }
                    }

                    if measuredDistance {
                        Label(
                            timeText(workout.elapsedTime),
                            systemImage: "clock"
                        )
                        .font(.system(size: 14, weight: .semibold,
                                      design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.textSecondary)
                    } else {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WatchTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .watchSurface(radius: 18)

                HStack(spacing: 7) {
                    metric(
                        label: ATHLTHLocalization.choose(
                            english: "PULSE", norwegian: "PULS"
                        ),
                        value: workout.hasFreshHeartRate
                            ? String(Int(workout.heartRate.rounded()))
                            : "—",
                        unit: "bpm",
                        icon: "heart.fill"
                    )
                    metric(
                        label: ATHLTHLocalization.choose(
                            english: "ENERGY", norwegian: "ENERGI"
                        ),
                        value: workout.activeCalories.isFinite
                            ? String(Int(max(workout.activeCalories, 0).rounded()))
                            : "—",
                        unit: "kcal",
                        icon: "flame.fill"
                    )
                }

                if workout.kind == .hiit {
                    Text(ATHLTHLocalization.choose(
                        english: "Interval rounds appear only when a structured HIIT workout is recorded.",
                        norwegian: "Intervallrunder vises først når en strukturert HIIT-økt registreres."
                    ))
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let error = workout.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 7)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private var subtitle: String {
        switch workout.kind {
        case .hiit:
            return ATHLTHLocalization.choose(
                english: "High-intensity training",
                norwegian: "Høyintensiv trening"
            )
        case .functional:
            return ATHLTHLocalization.choose(
                english: "Functional training",
                norwegian: "Funksjonell trening"
            )
        case .rowing:
            return ATHLTHLocalization.choose(
                english: "Rowing workout",
                norwegian: "Roøkt"
            )
        case .stairClimbing:
            return ATHLTHLocalization.choose(
                english: "Stair climbing", norwegian: "Trappetrening"
            )
        case .yoga:
            return ATHLTHLocalization.choose(
                english: "Yoga practice", norwegian: "Yogaøkt"
            )
        case .cycling:
            return ATHLTHLocalization.choose(
                english: "Cycling workout", norwegian: "Sykkeløkt"
            )
        case .other, .running, .walking, .strength:
            return ATHLTHLocalization.choose(
                english: "Live workout", norwegian: "Aktiv trening"
            )
        }
    }

    private func metric(
        label: String, value: String, unit: String, icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.textSecondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(WatchTheme.muted)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 16)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let value = Int(max(seconds.isFinite ? seconds : 0, 0).rounded(.down))
        if value >= 3600 {
            return String(format: "%d:%02d:%02d",
                          value / 3600, (value % 3600) / 60, value % 60)
        }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

/// A secondary read-only pulse page for non-running workout types.
struct WatchOtherSportPulsePage: View {
    @EnvironmentObject private var workout: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "HEART RATE", norwegian: "PULS"
                    ),
                    systemImage: "heart.fill"
                )
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchTheme.liveHeart)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(workout.hasFreshHeartRate
                             ? String(Int(workout.heartRate.rounded()))
                             : "—")
                            .font(.system(size: 48, weight: .bold,
                                          design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                        Text("bpm")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WatchTheme.muted)
                    }
                    Text(
                        workout.hasFreshHeartRate
                            ? ATHLTHLocalization.choose(
                                english: "CURRENT PULSE",
                                norwegian: "NÅVÆRENDE PULS"
                              )
                            : ATHLTHLocalization.choose(
                                english: "WAITING FOR SENSOR",
                                norwegian: "VENTER PÅ SENSOR"
                              )
                    )
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.textSecondary)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .watchSurface(radius: 18)

                HStack(spacing: 7) {
                    pulseMetric(
                        label: ATHLTHLocalization.choose(
                            english: "AVERAGE", norwegian: "SNITT"
                        ),
                        value: workout.averageHeartRate
                    )
                    pulseMetric(
                        label: ATHLTHLocalization.choose(
                            english: "MAX", norwegian: "MAKS"
                        ),
                        value: workout.maxHeartRate
                    )
                }

                if workout.targetAlertConfiguration?.heartRateEnabled == true,
                   let target = workout.targetAlertConfiguration {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "PULSE TARGET", norwegian: "PULSMÅL"
                            ),
                            systemImage: "target"
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchTheme.liveAction)

                        if let zone = target.heartRateZone {
                            Text(ATHLTHLocalization.choose(
                                english: "Zone \(zone)",
                                norwegian: "Sone \(zone)"
                            ))
                            .font(.system(size: 15, weight: .bold))
                        }

                        let status = ATHLTHRunPulseTargetStatus.resolve(
                            heartRate: workout.hasFreshHeartRate
                                ? workout.heartRate : nil,
                            minimum: target.heartRateMinimumBPM,
                            maximum: target.heartRateMaximumBPM
                        )
                        Text(statusText(status))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .watchSurface(radius: 16)
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 7)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .background(WatchTheme.canvas.ignoresSafeArea())
    }

    private func pulseMetric(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.muted)
            Text(value.map {
                $0.isFinite && $0 > 0 ? String(Int($0.rounded())) : "—"
            } ?? "—")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchSurface(radius: 16)
    }

    private func statusText(_ status: ATHLTHRunPulseTargetStatus) -> String {
        switch status {
        case .unavailable:
            return ATHLTHLocalization.choose(
                english: "Target not configured",
                norwegian: "Pulsmål ikke konfigurert"
            )
        case .waiting:
            return ATHLTHLocalization.choose(
                english: "Waiting for pulse", norwegian: "Venter på puls"
            )
        case .below:
            return ATHLTHLocalization.choose(
                english: "Below zone", norwegian: "Under målsonen"
            )
        case .within:
            return ATHLTHLocalization.choose(
                english: "Within zone", norwegian: "Innenfor målsonen"
            )
        case .above:
            return ATHLTHLocalization.choose(
                english: "Above zone", norwegian: "Over målsonen"
            )
        }
    }
}
