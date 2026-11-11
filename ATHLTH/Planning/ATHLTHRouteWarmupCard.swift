import SwiftUI

/// A small, optional section in the existing Quick Run setup flow.
struct ATHLTHRouteWarmupCard: View {
    @Binding var configuration: ATHLTHRouteWarmupConfiguration

    private let durations = [0, 5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        ATHLTHPlanSurface(density: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $configuration.enabled) {
                    Label {
                        Text(ATHLTHLocalization.choose(
                            english: "Warm-up",
                            norwegian: "Oppvarming"
                        ))
                        .font(.headline)
                    } icon: {
                        Image(systemName: "figure.run")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    }
                }
                .tint(ATHLTHPlanDesign.accentInk)

                if configuration.enabled {
                    Divider()

                    HStack {
                        Text(ATHLTHLocalization.choose(
                            english: "Duration",
                            norwegian: "Varighet"
                        ))
                        .font(.subheadline)
                        Spacer()
                        Picker(
                            ATHLTHLocalization.choose(
                                english: "Duration",
                                norwegian: "Varighet"
                            ),
                            selection: $configuration.durationMinutes
                        ) {
                            ForEach(durations, id: \.self) { minutes in
                                Text(minutes == 0
                                    ? ATHLTHLocalization.choose(
                                        english: "Open", norwegian: "Fri"
                                    )
                                    : ATHLTHLocalization.format(
                                        english: "%d min",
                                        norwegian: "%d min",
                                        minutes
                                    )
                                )
                                .tag(minutes)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider().opacity(0.55)

                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Target warm-up pace",
                            norwegian: "Måltempo for oppvarming"
                        ),
                        isOn: Binding(
                            get: { configuration.targetPaceSecondsPerKilometer != nil },
                            set: {
                                configuration.targetPaceSecondsPerKilometer =
                                    $0 ? 360 : nil
                            }
                        )
                    )
                    .font(.subheadline)
                    .tint(ATHLTHPlanDesign.accentInk)
                    if let selected = configuration.targetPaceSecondsPerKilometer {
                        Stepper(value: Binding(
                            get: {
                                configuration.targetPaceSecondsPerKilometer ?? selected
                            },
                            set: {
                                configuration.targetPaceSecondsPerKilometer = $0
                            }
                        ), in: 180...900, step: 5) {
                            Text(String(format: "%d:%02d min/km",
                                Int(selected) / 60, Int(selected) % 60))
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.medium))
                    }

                    Toggle(
                        ATHLTHLocalization.choose(
                            english: "Warm-up heart-rate zone",
                            norwegian: "Pulssone i oppvarming"
                        ),
                        isOn: Binding(
                            get: { configuration.targetHeartRateZone != nil },
                            set: { configuration.targetHeartRateZone = $0 ? 2 : nil }
                        )
                    )
                    .font(.subheadline)
                    .tint(ATHLTHPlanDesign.accentInk)
                    if let zone = configuration.targetHeartRateZone {
                        Stepper(
                            ATHLTHLocalization.choose(
                                english: "Zone", norwegian: "Sone"
                            ) + " \(zone)",
                            value: Binding(
                                get: { configuration.targetHeartRateZone ?? zone },
                                set: { configuration.targetHeartRateZone = $0 }
                            ),
                            in: 1...5
                        )
                        .font(.subheadline.weight(.medium))
                    }

                    if configuration.durationMinutes > 0 {
                        Toggle(
                            ATHLTHLocalization.choose(
                                english: "Start route automatically",
                                norwegian: "Start ruten automatisk"
                            ),
                            isOn: $configuration.autoStartMain
                        )
                        .font(.subheadline)
                        .tint(ATHLTHPlanDesign.accentInk)
                    }

                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var explanation: String {
        if configuration.durationMinutes == 0 {
            return ATHLTHLocalization.choose(
                english: "Warm up as long as you need. Tap Start main to begin following the route.",
                norwegian: "Varm opp så lenge du ønsker. Trykk Start hoveddel for å begynne å følge ruten."
            )
        }
        if configuration.autoStartMain {
            return ATHLTHLocalization.choose(
                english: "The route begins automatically when the warm-up timer ends.",
                norwegian: "Ruten starter automatisk når oppvarmingstiden er over."
            )
        }
        return ATHLTHLocalization.choose(
            english: "When you are ready, tap Start main on iPhone or Apple Watch.",
            norwegian: "Når du er klar, trykker du Start hoveddel på iPhone eller Apple Watch."
        )
    }
}
