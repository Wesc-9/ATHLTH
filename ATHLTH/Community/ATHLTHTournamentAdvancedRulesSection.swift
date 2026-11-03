import SwiftUI

/// Advanced settings stay collapsed during ordinary tournament creation.
struct ATHLTHTournamentAdvancedRulesSection: View {
    @Binding var rotation: ATHLTHTournamentRotationMode
    @Binding var restDays: Set<Int>
    @Binding var winPoints: Int
    @Binding var drawPoints: Int
    @Binding var allowExtensions: Bool
    @Binding var publicResults: Bool
    @Binding var proof: ATHLTHTournamentProofMode

    @State private var expanded = false

    private let dayNames = ["Man", "Tir", "Ons", "Tor", "Fre", "Lør", "Søn"]

    var body: some View {
        VStack(alignment: .leading,spacing: 15) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                    Text("Avanserte regler")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                .padding(15)
                .background(ATHLTHArenaV3Style.panel())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading,spacing: 12) {
                    Text("Hvordan brukes øvelsene?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    ForEach(ATHLTHTournamentRotationMode.allCases) { option in
                        Button {
                            rotation=option
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: rotation == option
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ATHLTHArenaV3Style.gold)
                                VStack(alignment: .leading,spacing: 3) {
                                    Text(option.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(ATHLTHArenaV3Style.panel())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Hviledager")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHArenaV3Style.ink)
                    HStack(spacing: 5) {
                        ForEach(1...7, id: \.self) { weekday in
                            restDayButton(weekday)
                        }
                    }
                    Text("Øvelser flyttes til neste tilgjengelige treningsdag. Ingen resultater avgjøres automatisk på hviledager.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    VStack(spacing: 12) {
                        HStack {
                            Text("Poeng per seier")
                            Spacer()
                            Stepper(value: $winPoints,in: 1...10) {
                                Text("\(winPoints)")
                                    .font(.headline.monospacedDigit())
                            }
                            .fixedSize()
                        }
                        Divider().opacity(0.4)
                        HStack {
                            Text("Poeng ved uavgjort")
                            Spacer()
                            Stepper(value: $drawPoints,
                                    in: 0...min(3,max(0,winPoints-1))) {
                                Text("\(drawPoints)")
                                    .font(.headline.monospacedDigit())
                            }
                            .fixedSize()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHArenaV3Style.ink)
                    .padding(14)
                    .background(ATHLTHArenaV3Style.panel())
                    .onChange(of: winPoints) { _, points in
                        drawPoints=min(drawPoints,max(0,points-1))
                    }
                    Text("Ved poenglikhet: målforskjell, deretter oppnådde poeng og antall seire. Cup krever alltid en vinner.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)

                    VStack(spacing: 12) {
                        Toggle(isOn: $allowExtensions) {
                            VStack(alignment: .leading,spacing: 3) {
                                Text("Tillat fristutsettelse")
                                Text("Arrangøren kan forlenge uløste oppgjør.")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                        }
                        Divider().opacity(0.4)
                        Toggle(isOn: $publicResults) {
                            VStack(alignment: .leading,spacing: 3) {
                                Text("Offentlig resultatoversikt")
                                Text("Bare tabell og godkjente resultater, aldri lobbychat.")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHArenaV3Style.secondary)
                            }
                        }
                    }
                    .font(.subheadline)
                    .tint(ATHLTHArenaV3Style.gold)
                    .padding(14)
                    .background(ATHLTHArenaV3Style.panel())

                    Label("Resultater registreres med dokumentasjon og må godkjennes av motstanderen. Sensorbasert automatisk verifisering kommer senere.",
                          systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        .fixedSize(horizontal: false,vertical: true)
                }
            }
        }
    }
    private func restDayButton(_ weekday: Int) -> some View {
        let selected = restDays.contains(weekday)
        return Button {
            if selected {
                restDays.remove(weekday)
            } else if restDays.count < 6 {
                restDays.insert(weekday)
            }
        } label: {
            Text(dayNames[weekday - 1])
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(
                    selected ? Color.white : ATHLTHArenaV3Style.ink
                )
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(ATHLTHArenaV3Style.ink)
                    } else {
                        ATHLTHArenaV3Style.panel()
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            dayNames[weekday - 1] +
                (selected ? " hviledag" : " treningsdag")
        )
    }

}
