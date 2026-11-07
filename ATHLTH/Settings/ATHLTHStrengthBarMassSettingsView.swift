import SwiftUI

/// The athlete enters plate weight (both sides combined) on a barbell live card.
/// ATHLTH saves total kilograms including the bar; preferences stay account-local.
struct ATHLTHStrengthBarMassSettingsView: View {
    @EnvironmentObject private var session: AppSessionStore

    @State private var barMass = 20.0
    @State private var customEntry = ""
    @FocusState private var enteringCustom: Bool

    private let ink = Color(red: 0.19, green: 0.20, blue: 0.22)
    private let canvas = Color(red: 0.973, green: 0.973, blue: 0.968)

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("Standard bar weight", "Standard stangvekt"))
                        .font(.system(.largeTitle, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Choose the bar you normally train with. You can still change the weight for each exercise and every workout.",
                        "Velg stangen du vanligvis trener med. Du kan fortsatt endre vekten for hver øvelse og hver enkelt økt."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(tr("YOUR DEFAULT", "DIN STANDARD"))
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%g kg", barMass))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(ink)
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4),
                        spacing: 9
                    ) {
                        ForEach([5.0, 10, 15, 20, 25, 30, 0], id: \.self) { value in
                            Button(String(format: "%g kg", value)) {
                                choose(value)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(barMass == value ? .white : ink)
                            .frame(maxWidth: .infinity, minHeight: 47)
                            .background(
                                barMass == value ? ink : canvas,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 12) {
                        TextField(
                            tr("Other weight in kg", "Annen vekt i kg"),
                            text: $customEntry
                        )
                        .keyboardType(.decimalPad)
                        .focused($enteringCustom)
                        .font(.subheadline)
                        .textFieldStyle(.roundedBorder)

                        Button(tr("Save", "Lagre")) {
                            guard let value = Double(
                                customEntry.replacingOccurrences(of: ",", with: ".")
                            ), value.isFinite, (0...40).contains(value) else { return }
                            choose(value)
                            enteringCustom = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ink)
                        .disabled(!isValidCustomMass)
                    }
                }
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 21))

                Label(
                    tr(
                        "Enter the weight of the plates on both sides combined during a set. ATHLTH adds the selected bar once and records the total load.",
                        "Under settet legger du inn vekten av skivene på begge sider til sammen. ATHLTH legger til valgt stangvekt én gang og lagrer totalbelastningen."
                    ),
                    systemImage: "info.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 17))

                Text(tr(
                    "Saved per-exercise bar weights take precedence over this standard. Historical completed sets are never recalculated.",
                    "Stangvekt lagret for en bestemt øvelse overstyrer denne standarden. Historiske fullførte sett beregnes aldri på nytt."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(canvas.ignoresSafeArea())
        .navigationTitle(tr("Bar weight", "Stangvekt"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            barMass = StrengthBarWeightPreferences.defaultMass(
                userID: session.profile.userID
            )
            customEntry = String(format: "%g", barMass)
        }
    }

    private var isValidCustomMass: Bool {
        guard let value = Double(customEntry.replacingOccurrences(of: ",", with: ".")) else {
            return false
        }
        return value.isFinite && (0...40).contains(value)
    }

    private func choose(_ value: Double) {
        barMass = value
        customEntry = String(format: "%g", value)
        StrengthBarWeightPreferences.setDefaultMass(
            value,
            userID: session.profile.userID
        )
    }
}
