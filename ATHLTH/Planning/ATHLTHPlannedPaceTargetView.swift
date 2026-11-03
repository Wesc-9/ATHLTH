import SwiftUI

/// One speed/pace target editor shared by outdoor, indoor and treadmill running.
/// Both units edit the same seconds-per-kilometre target without rounding the
/// stored value when the athlete simply switches the displayed unit.
struct ATHLTHPlannedPaceTargetView: View {
    @Binding var targetPaceSecondsPerKilometer: Double?
    @State private var showsSpeed: Bool
    let defaultPace: Double

    init(
        targetPaceSecondsPerKilometer: Binding<Double?>,
        prefersSpeed: Bool = false,
        defaultPace: Double = 330
    ) {
        _targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer
        _showsSpeed = State(initialValue: prefersSpeed)
        self.defaultPace = defaultPace
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { targetPaceSecondsPerKilometer != nil },
            set: { enabled in
                if enabled {
                    targetPaceSecondsPerKilometer =
                        targetPaceSecondsPerKilometer ?? defaultPace
                } else {
                    targetPaceSecondsPerKilometer = nil
                }
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
                targetPaceSecondsPerKilometer =
                    ATHLTHPlannedTreadmillTargets.pace(forSpeed: value)
            }
        )
    }

    private var pace: Binding<Double> {
        Binding(
            get: { targetPaceSecondsPerKilometer ?? defaultPace },
            set: { targetPaceSecondsPerKilometer = min(max($0, 144), 3_600) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(tr("Target pace / speed", "Måltempo / hastighet"),
                   isOn: isEnabled)
                .tint(ATHLTHTrainDesign.bronze)

            if targetPaceSecondsPerKilometer != nil {
                Picker(tr("Pace unit", "Enhet for tempo"), selection: $showsSpeed) {
                    Text("min/km").tag(false)
                    Text(tr("km/h", "km/t")).tag(true)
                }
                .pickerStyle(.segmented)

                if showsSpeed {
                    Stepper(value: speed, in: 1...25, step: 0.1) {
                        HStack {
                            Text(tr("Speed", "Hastighet"))
                            Spacer()
                            Text(speed.wrappedValue.formatted(
                                .number.precision(.fractionLength(1)))
                                + tr(" km/h", " km/t"))
                                .fontWeight(.semibold)
                        }
                    }
                } else {
                    Stepper(value: pace, in: 144...3_600, step: 5) {
                        let seconds = Int(pace.wrappedValue.rounded())
                        let tail = seconds % 60
                        HStack {
                            Text(tr("Pace", "Tempo"))
                            Spacer()
                            Text("\(seconds / 60):\(tail < 10 ? "0" : "")\(tail) min/km")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }
}
