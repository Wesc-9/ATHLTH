import SwiftUI

/// Pace is stored canonically in seconds/km; treadmill speed is just another
/// representation of that exact target, not a second independent value.
enum ATHLTHRunningImportPace {
    static func kilometersPerHour(from input: String, treadmill: Bool) -> Double? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if treadmill {
            guard let speed = Double(clean.replacingOccurrences(of: ",", with: ".")),
                  speed.isFinite, (2...30).contains(speed) else { return nil }
            return speed
        }
        let parts = clean.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]),
              (0...30).contains(minutes), (0...59).contains(seconds),
              parts[1].count == 2 else { return nil }
        let pace = Double(minutes * 60 + seconds)
        guard (120...1800).contains(pace) else { return nil }
        return 3600 / pace
    }

    static func text(for pace: Double?, treadmill: Bool) -> String {
        guard let pace, pace.isFinite, (120...1800).contains(pace) else { return "" }
        if treadmill {
            return (3600 / pace).formatted(.number.precision(.fractionLength(0...2)))
        }
        let seconds = Int(pace.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Isolated editor: typing never invalidates the parent workout timeline.
struct ATHLTHRunningPrivateSpeedEditor: View {
    let effortCount: Int
    var environment: RunEnvironment = .treadmill
    var currentPace: Double? = nil
    let onApply: (Double) -> Void

    @State private var typedSpeed = ""
    private var treadmill: Bool { environment == .treadmill }
    private var speed: Double? {
        ATHLTHRunningImportPace.kilometersPerHour(from: typedSpeed, treadmill: treadmill)
    }

    private func refreshInput() {
        typedSpeed = ATHLTHRunningImportPace.text(for: currentPace, treadmill: treadmill)
    }

    var body: some View {
        if effortCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(ATHLTHLocalization.choose(english: "Target pace", norwegian: "Målfart"))
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 6)
                    TextField(treadmill ? "14" : "4:17", text: $typedSpeed)
                        .keyboardType(treadmill ? .decimalPad : .numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 76)
                        .monospacedDigit()
                        .accessibilityIdentifier("athlth-running-private-speed")
                        .accessibilityLabel(treadmill ? "km/t" : "min/km")
                    Text(treadmill ? "km/t" : "min/km").font(.caption)
                    Button(ATHLTHLocalization.choose(english: "Apply", norwegian: "Bruk")) {
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
            .onAppear(perform: refreshInput)
            .onChange(of: environment) { _, _ in refreshInput() }
            .onChange(of: currentPace) { _, _ in refreshInput() }
        }
    }
}
