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
