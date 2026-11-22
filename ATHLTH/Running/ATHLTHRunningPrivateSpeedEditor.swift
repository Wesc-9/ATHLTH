import SwiftUI

/// Isolated, low-frequency editor. Typing a digit never invalidates the
/// parent workout timeline, exercise artwork or the Spotify picker.
struct ATHLTHRunningPrivateSpeedEditor: View {
    let effortCount: Int
    let onApply: (Double) -> Void

    @State private var typedSpeed = ""

    private var speed: Double? {
        let normalized = typedSpeed.replacingOccurrences(of: ",", with: ".")
        guard let number = Double(normalized),
              number.isFinite, (2...30).contains(number) else { return nil }
        return number
    }

    var body: some View {
        if effortCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(ATHLTHLocalization.choose(
                        english: "Target speed", norwegian: "Målfart"
                    ))
                    .font(.subheadline.weight(.medium))
                    Spacer(minLength: 6)
                    TextField("14", text: $typedSpeed)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .accessibilityIdentifier("athlth-running-private-speed")
                    Text("km/t").font(.caption)
                    Button(ATHLTHLocalization.choose(
                        english: "Apply to all", norwegian: "Bruk"
                    )) {
                        guard let speed else { return }
                        onApply(speed)
                    }
                    .disabled(speed == nil)
                    .buttonStyle(.bordered)
                    .tint(ATHLTHPlanDesign.accentInk)
                }
                Text(ATHLTHLocalization.choose(
                    english: "Applies to \(effortCount) work intervals. Warm-up, recovery and cool-down remain unchanged.",
                    norwegian: "Gjelder alle \(effortCount) drag. Oppvarming, pauser og nedjogging endres ikke."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
