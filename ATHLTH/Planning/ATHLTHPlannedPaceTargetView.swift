import SwiftUI

/// Both units edit the same seconds-per-kilometre model field. Preferences
/// are presentation-only, shared between outdoor and treadmill planning.
struct ATHLTHPlannedPaceTargetView: View {
    @Binding var targetPaceSecondsPerKilometer: Double?
    @AppStorage("athlth.running.paceUnitPreference.v1") private var preferredUnit = "auto"
    @AppStorage("athlth.running.treadmillInputMode.v1") private var treadmillInputMode = "treadmill"
    @AppStorage("settings.measurement") private var measurementRaw = "metric"
    @Environment(\.locale) private var locale
    let prefersSpeed: Bool
    let defaultPace: Double
    let treadmillDisplay: Bool

    init(
        targetPaceSecondsPerKilometer: Binding<Double?>,
        prefersSpeed: Bool = false,
        defaultPace: Double = 330,
        treadmillDisplay: Bool = false
    ) {
        _targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer
        self.prefersSpeed = prefersSpeed
        self.defaultPace = defaultPace
        self.treadmillDisplay = treadmillDisplay
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var measurement: MeasurementPreference {
        MeasurementPreference(rawValue: measurementRaw) ?? .metric
    }
    private var treadmillMode: Binding<ATHLTHTreadmillInputMode> {
        Binding(
            get: { ATHLTHTreadmillInputMode(rawValue: treadmillInputMode) ?? .treadmill },
            set: { treadmillInputMode = $0.rawValue }
        )
    }
    private var isPaceMode: Bool {
        treadmillDisplay ? treadmillMode.wrappedValue == .pace : !showingSpeed.wrappedValue
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
                ATHLTHPlannedTreadmillTargets.displaySpeed(
                    ATHLTHPlannedTreadmillTargets.speed(
                        forPace: targetPaceSecondsPerKilometer ?? defaultPace
                    ), measurement: measurement
                )
            },
            set: { value in
                guard value.isFinite else { return }
                targetPaceSecondsPerKilometer =
                    ATHLTHPlannedTreadmillTargets.pace(forSpeed:
                        ATHLTHPlannedTreadmillTargets.canonicalSpeed(
                            value, measurement: measurement
                        )
                    )
            }
        )
    }

    private var pace: Binding<Double> {
        Binding(
            get: {
                ATHLTHPlannedTreadmillTargets.displayPace(
                    targetPaceSecondsPerKilometer ?? defaultPace,
                    measurement: measurement
                )
            },
            set: { value in
                guard value.isFinite else { return }
                let canonical = ATHLTHPlannedTreadmillTargets.canonicalPace(
                    value, measurement: measurement
                )
                targetPaceSecondsPerKilometer = min(max(canonical, 144), 3_600)
            }
        )
    }

    private var paceMinutes: Binding<Int> {
        Binding(
            get: { Int(pace.wrappedValue.rounded()) / 60 },
            set: { value in
                let seconds = Int(pace.wrappedValue.rounded()) % 60
                pace.wrappedValue = Double(min(max(value, 0), 95) * 60 + seconds)
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
            Toggle(
                treadmillDisplay ? tr("Treadmill tempo", "Mølletempo")
                    : tr("Target pace / speed", "Måltempo / hastighet"),
                isOn: isEnabled
            )
                .tint(ATHLTHTrainDesign.bronze)

            if targetPaceSecondsPerKilometer != nil {
                if treadmillDisplay {
                    Picker(tr("Treadmill tempo or speed", "Mølletempo eller hastighet"),
                           selection: treadmillMode) {
                        ForEach(ATHLTHTreadmillInputMode.allCases) { mode in
                            Text(mode.title(measurement: measurement)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Picker(tr("Pace unit", "Enhet for tempo"), selection: showingSpeed) {
                        Text(measurement.runningPaceUnit).tag(false)
                        Text(measurement.runningSpeedUnit).tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if !isPaceMode {
                    HStack(spacing: 10) {
                        Text(treadmillDisplay && treadmillMode.wrappedValue == .treadmill
                            ? tr("Treadmill tempo", "Mølletempo")
                            : tr("Speed", "Hastighet"))
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
                        Text(measurement.runningSpeedUnit)
                            .font(.caption)
                        Stepper("", value: speed,
                                in: 1...(measurement == .metric ? 25 : 15.5), step: 0.1)
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
                        Text(measurement.runningPaceUnit)
                            .font(.caption)
                        Stepper("", value: pace,
                                in: 144...(measurement == .metric ? 3_600 : 5_793), step: 5)
                            .labelsHidden()
                            .fixedSize()
                    }
                }

                if let savedPace = targetPaceSecondsPerKilometer, savedPace > 0 {
                    let displaySpeed = ATHLTHPlannedTreadmillTargets.displaySpeed(
                        ATHLTHPlannedTreadmillTargets.speed(forPace: savedPace),
                        measurement: measurement
                    )
                    let displayPace = ATHLTHPlannedTreadmillTargets.displayPace(
                        savedPace, measurement: measurement
                    )
                    let total = Int(displayPace.rounded())
                    let formattedPace = String(
                        format: "%d:%02d", total / 60, total % 60
                    )
                    Text(tr("Equivalent to", "Tilsvarer") + ": " +
                        displaySpeed.formatted(
                            .number.precision(.fractionLength(1)).locale(locale)
                        ) + " " + measurement.runningSpeedUnit + " = " +
                        formattedPace + " " + measurement.runningPaceUnit
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
