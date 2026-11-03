import SwiftUI

/// Both units edit the same seconds-per-kilometre model field. Preferences
/// are presentation-only, shared between outdoor and treadmill planning.
struct ATHLTHPlannedPaceTargetView: View {
    @Binding var targetPaceSecondsPerKilometer: Double?
    @AppStorage("athlth.running.paceUnitPreference.v1") private var preferredUnit = "auto"
    let prefersSpeed: Bool
    let defaultPace: Double

    init(
        targetPaceSecondsPerKilometer: Binding<Double?>,
        prefersSpeed: Bool = false,
        defaultPace: Double = 330
    ) {
        _targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer
        self.prefersSpeed = prefersSpeed
        self.defaultPace = defaultPace
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var showingSpeed: Binding<Bool> {
        Binding(
            get: {
                preferredUnit == "auto" ? prefersSpeed : preferredUnit == "speed"
            },
            set: { preferredUnit = $0 ? "speed" : "pace" }
        )
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { targetPaceSecondsPerKilometer != nil },
            set: { enabled in
                targetPaceSecondsPerKilometer = enabled
                    ? (targetPaceSecondsPerKilometer ?? defaultPace) : nil
            }
        )
    }

    private var speed: Binding<Double> {
        Binding(
            get: {
                ATHLTHPlannedTreadmillTargets.speed(
                    forPace: targetPaceSecondsPerKilometer ?? defaultPace
                )
            },
            set: { value in
                guard value.isFinite else { return }
                targetPaceSecondsPerKilometer =
                    ATHLTHPlannedTreadmillTargets.pace(forSpeed: value)
            }
        )
    }

    private var pace: Binding<Double> {
        Binding(
            get: { targetPaceSecondsPerKilometer ?? defaultPace },
            set: { value in
                guard value.isFinite else { return }
                targetPaceSecondsPerKilometer = min(max(value, 144), 3_600)
            }
        )
    }

    private var paceMinutes: Binding<Int> {
        Binding(
            get: { Int(pace.wrappedValue.rounded()) / 60 },
            set: { value in
                let seconds = Int(pace.wrappedValue.rounded()) % 60
                pace.wrappedValue = Double(min(max(value, 0), 60) * 60 + seconds)
            }
        )
    }

    private var paceSeconds: Binding<Int> {
        Binding(
            get: { Int(pace.wrappedValue.rounded()) % 60 },
            set: { value in
                let minutes = Int(pace.wrappedValue.rounded()) / 60
                pace.wrappedValue = Double(minutes * 60 + min(max(value, 0), 59))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(tr("Target pace / speed", "Måltempo / hastighet"),
                   isOn: isEnabled)
                .tint(ATHLTHTrainDesign.bronze)

            if targetPaceSecondsPerKilometer != nil {
                Picker(tr("Pace unit", "Enhet for tempo"), selection: showingSpeed) {
                    Text("min/km").tag(false)
                    Text(tr("km/h", "km/t")).tag(true)
                }
                .pickerStyle(.segmented)

                if showingSpeed.wrappedValue {
                    HStack(spacing: 10) {
                        Text(tr("Speed", "Hastighet"))
                            .font(.subheadline)
                        Spacer(minLength: 4)
                        TextField(
                            tr("Speed", "Hastighet"), value: speed,
                            format: .number.precision(.fractionLength(1))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 76)
                        .accessibilityLabel(tr("Speed in km/h", "Fart i km/t"))
                        Text(tr("km/h", "km/t"))
                            .font(.caption)
                        Stepper("", value: speed, in: 1...25, step: 0.1)
                            .labelsHidden()
                            .fixedSize()
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(tr("Pace", "Tempo"))
                            .font(.subheadline)
                        Spacer(minLength: 4)
                        TextField(
                            "min", value: paceMinutes,
                            format: .number.grouping(.never)
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 30)
                        .accessibilityLabel(tr("Pace minutes", "Tempominutter"))
                        Text(":")
                        TextField(
                            "sek", value: paceSeconds,
                            format: .number.grouping(.never)
                        )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .frame(width: 28)
                        .accessibilityLabel(tr("Pace seconds", "Temposekunder"))
                        Text("min/km")
                            .font(.caption)
                        Stepper("", value: pace, in: 144...3_600, step: 5)
                            .labelsHidden()
                            .fixedSize()
                    }
                }
            }
        }
    }
}
