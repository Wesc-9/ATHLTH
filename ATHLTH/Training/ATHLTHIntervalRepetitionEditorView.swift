import SwiftUI

/// Each repetition has its own work target and the recovery immediately after
/// it. This editor modifies only that one repetition, never the block default.
struct ATHLTHIntervalRepetitionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let repetition: Int
    let totalRepetitions: Int
    let environment: RunEnvironment
    let onSave: (RunningRepetitionOverride) -> Void
    private let originalWork: RunningStepTarget
    private let originalRecovery: RunningStepTarget?

    @State private var measure: RunningMeasureKind
    @State private var workSeconds: Int
    @State private var workMeters: Int
    @State private var paceEnabled: Bool
    @State private var paceSeconds: Int
    @State private var paceAsSpeed: Bool
    @State private var targetSpeedKmh: Double
    @State private var inclineEnabled: Bool
    @State private var inclinePercent: Double
    @State private var recoveryInclineEnabled: Bool
    @State private var recoveryInclinePercent: Double
    @State private var recoverySpeedEnabled: Bool
    @State private var recoverySpeedKmh: Double
    @State private var recoveryPaceSeconds: Int
    @State private var recoveryZoneEnabled: Bool
    @State private var recoveryZone: Int
    @State private var heartRateEnabled: Bool
    @State private var heartRateZone: Int
    @State private var recoveryEnabled: Bool
    @State private var recoveryMeasure: RunningMeasureKind
    @State private var recoverySeconds: Int
    @State private var recoveryMeters: Int
    @State private var customGhostEnabled: Bool
    @State private var customGhostPaceSeconds: Int
    @State private var notes: String

    init(block: RunningWorkoutBlock,
         repetition: Int,
         environment: RunEnvironment = .outdoor,
         onSave: @escaping (RunningRepetitionOverride) -> Void) {
        self.repetition = repetition
        self.totalRepetitions = max(block.repetitions, 1)
        self.environment = environment
        self.onSave = onSave
        let selected = block.override(for: repetition)
        let work = block.resolvedWork(at: repetition)
        let recovery = block.resolvedRecovery(after: repetition)
        self.originalWork = work
        self.originalRecovery = recovery
        _measure = State(initialValue: work.measure)
        _workSeconds = State(initialValue: max(1, Int(work.durationSeconds ?? 240)))
        _workMeters = State(initialValue: max(1, Int(work.distanceMeters ?? 1000)))
        _paceEnabled = State(initialValue: work.intensity.paceMinSecondsPerKilometer != nil)
        _paceSeconds = State(initialValue: Int(work.intensity.paceMinSecondsPerKilometer ?? 300))
        _paceAsSpeed = State(initialValue: environment == .treadmill)
        _targetSpeedKmh = State(initialValue:
            3_600 / max(work.intensity.paceMinSecondsPerKilometer ?? 300, 1))
        _inclineEnabled = State(initialValue: work.treadmillInclinePercent != nil)
        _inclinePercent = State(initialValue: work.treadmillInclinePercent ?? 0)
        _recoveryInclineEnabled = State(initialValue: recovery?.treadmillInclinePercent != nil)
        _recoveryInclinePercent = State(initialValue: recovery?.treadmillInclinePercent ?? 0)
        let recoveryPace = recovery?.intensity.paceMinSecondsPerKilometer
        _recoverySpeedEnabled = State(initialValue: recoveryPace != nil)
        _recoverySpeedKmh = State(initialValue:
            3_600 / max(recoveryPace ?? 600, 1))
        _recoveryPaceSeconds = State(initialValue: Int(recoveryPace ?? 600))
        _recoveryZoneEnabled = State(initialValue: recovery?.intensity.heartRateZone != nil)
        _recoveryZone = State(initialValue: recovery?.intensity.heartRateZone ?? 2)
        _heartRateEnabled = State(initialValue: work.intensity.heartRateZone != nil)
        _heartRateZone = State(initialValue: work.intensity.heartRateZone ?? 4)
        _recoveryEnabled = State(initialValue: recovery != nil)
        _recoveryMeasure = State(initialValue: recovery?.measure ?? .time)
        _recoverySeconds = State(initialValue: max(1, Int(recovery?.durationSeconds ?? 120)))
        _recoveryMeters = State(initialValue: max(1, Int(recovery?.distanceMeters ?? 200)))
        _customGhostEnabled = State(initialValue: selected?.ghostPaceSecondsPerKilometer != nil)
        _customGhostPaceSeconds = State(initialValue: Int(selected?.ghostPaceSecondsPerKilometer ?? 300))
        _notes = State(initialValue: selected?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("Effort target", "Dragets mål"), selection: $measure) {
                        Text(tr("Time", "Tid")).tag(RunningMeasureKind.time)
                        Text(tr("Distance", "Distanse")).tag(RunningMeasureKind.distance)
                        Text(tr("Open", "Åpen")).tag(RunningMeasureKind.open)
                    }
                    .pickerStyle(.segmented)
                    if measure == .time {
                        Stepper(tr("Work time", "Dragtid") + ": " + clock(workSeconds),
                                value: $workSeconds, in: 1...21600, step: 1)
                    } else if measure == .distance {
                        Stepper("\(workMeters) m", value: $workMeters, in: 1...100000, step: 1)
                    }

                    Toggle(tr("Target pace", "Måltempo"), isOn: $paceEnabled)
                    if paceEnabled {
                        Picker(tr("Set target using", "Angi målet som"), selection: $paceAsSpeed) {
                            Text(tr("Speed (km/h)", "Hastighet (km/t)")).tag(true)
                            Text(tr("Pace (min/km)", "Tempo (min/km)")).tag(false)
                        }
                        .pickerStyle(.segmented)
                        if paceAsSpeed {
                            Stepper(
                                String(format: "%.1f km/t", targetSpeedKmh),
                                value: $targetSpeedKmh, in: 1...40, step: 0.1
                            )
                        } else {
                            Stepper(paceLabel(paceSeconds), value: $paceSeconds,
                                    in: 60...3600, step: 1)
                        }
                    }

                    Toggle(tr("Treadmill incline target", "Målstigning på mølle"), isOn: $inclineEnabled)
                    if inclineEnabled {
                        Stepper(String(format: "%.1f %%", inclinePercent),
                                value: $inclinePercent, in: 0...15, step: 0.5)
                    }

                    Toggle(tr("Target HR zone", "Målsone for puls"), isOn: $heartRateEnabled)
                    if heartRateEnabled {
                        Stepper(tr("Zone", "Sone") + " \(heartRateZone)",
                                value: $heartRateZone, in: 1...5)
                    }

                    Toggle(tr("Individual Ghost pace", "Eget Ghost-tempo for dette draget"),
                           isOn: $customGhostEnabled)
                    if customGhostEnabled {
                        Stepper(paceLabel(customGhostPaceSeconds),
                                value: $customGhostPaceSeconds, in: 150...1200, step: 5)
                    }
                } header: {
                    Text(tr("Effort", "Drag") + " \(repetition)")
                }

                if repetition < totalRepetitions {
                    Section {
                        Toggle(tr("Include recovery", "Ta med pause"), isOn: $recoveryEnabled)
                        if recoveryEnabled {
                            Picker(tr("Recovery goal", "Pause etter draget"), selection: $recoveryMeasure) {
                                Text(tr("Time", "Tid")).tag(RunningMeasureKind.time)
                                Text(tr("Distance", "Distanse")).tag(RunningMeasureKind.distance)
                                Text(tr("Open", "Åpen")).tag(RunningMeasureKind.open)
                            }
                            .pickerStyle(.segmented)
                            if recoveryMeasure == .time {
                                Stepper(clock(recoverySeconds),
                                        value: $recoverySeconds, in: 1...3600, step: 1)
                            } else if recoveryMeasure == .distance {
                                Stepper("\(recoveryMeters) m",
                                        value: $recoveryMeters, in: 1...10000, step: 1)
                            }
                            Toggle(tr("Target recovery speed", "Målhastighet i pausen"),
                                   isOn: $recoverySpeedEnabled)
                            if recoverySpeedEnabled {
                                if environment == .treadmill {
                                    Stepper(
                                        String(format: "%.1f km/t", recoverySpeedKmh),
                                        value: $recoverySpeedKmh, in: 2...20, step: 0.1
                                    )
                                } else {
                                    Stepper(paceLabel(recoveryPaceSeconds),
                                            value: $recoveryPaceSeconds,
                                            in: 60...3600, step: 1)
                                }
                            }
                            Toggle(tr("Recovery incline", "Stigning i pausen"),
                                   isOn: $recoveryInclineEnabled)
                            if recoveryInclineEnabled {
                                Stepper(String(format: "%.1f %%", recoveryInclinePercent),
                                        value: $recoveryInclinePercent, in: 0...15, step: 0.5)
                            }
                            Toggle(tr("Target recovery zone", "Målsone i pausen"),
                                   isOn: $recoveryZoneEnabled)
                            if recoveryZoneEnabled {
                                Stepper(tr("Zone", "Sone") + " \(recoveryZone)",
                                        value: $recoveryZone, in: 1...5)
                            }
                        }
                    } header: {
                        Text(tr("Recovery after effort", "Pause etter drag") + " \(repetition)")
                    } footer: {
                        Text(tr("Changing recovery 3 affects only the third pause.",
                                "Hvis du forlenger pause 3, endres ingen av de andre pausene."))
                    }
                }

                Section(tr("Personal instructions", "Egne instruksjoner")) {
                    TextField(tr("e.g. Start conservatively", "F.eks. Start kontrollert"),
                              text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(tr("Edit effort", "Rediger drag") + " \(repetition)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save", "Lagre")) {
                        let targetPace: Double? = paceEnabled
                            ? (paceAsSpeed
                                ? 3_600 / max(targetSpeedKmh, 0.1)
                                : Double(paceSeconds))
                            : nil
                        let intensity = RunningIntensityTarget(
                            kind: paceEnabled ? .pace : heartRateEnabled ? .heartRateZone : .easy,
                            paceMinSecondsPerKilometer: targetPace,
                            paceMaxSecondsPerKilometer: targetPace,
                            heartRateZone: heartRateEnabled ? heartRateZone : nil,
                            rpe: nil
                        )
                        var work = measure == .time
                            ? RunningStepTarget.time(Double(workSeconds), intensity: intensity)
                            : measure == .distance
                            ? RunningStepTarget.distance(Double(workMeters), intensity: intensity) : .open
                        work.intensity = intensity
                        work.treadmillInclinePercent = inclineEnabled ? inclinePercent : nil
                        work = ATHLTHRunningTargetEditing.preservingAdditionalTargets(from: originalWork, in: work)
                        let recoveryPace: Double? = recoverySpeedEnabled
                            ? (environment == .treadmill
                                ? 3_600 / max(recoverySpeedKmh, 0.1)
                                : Double(recoveryPaceSeconds)) : nil
                        let recoveryIntensity = RunningIntensityTarget(
                            kind: recoverySpeedEnabled ? .pace :
                                (recoveryZoneEnabled ? .heartRateZone : .easy),
                            paceMinSecondsPerKilometer: recoveryPace,
                            paceMaxSecondsPerKilometer: recoveryPace,
                            heartRateZone: recoveryZoneEnabled ? recoveryZone : nil,
                            rpe: nil
                        )
                        var recovery: RunningStepTarget? = recoveryEnabled &&
                            repetition < totalRepetitions
                            ? (recoveryMeasure == .time
                                ? .time(Double(recoverySeconds), intensity: recoveryIntensity)
                                : recoveryMeasure == .distance
                                ? .distance(Double(recoveryMeters), intensity: recoveryIntensity) : .open)
                            : nil
                        if recovery != nil {
                            recovery?.intensity = recoveryIntensity
                            recovery?.treadmillInclinePercent = recoveryInclineEnabled
                                ? recoveryInclinePercent : nil
                        }
                        if let editedRecovery = recovery {
                            recovery = ATHLTHRunningTargetEditing.preservingAdditionalTargets(
                                from: originalRecovery, in: editedRecovery)
                        }
                        onSave(RunningRepetitionOverride(
                            repetition: repetition,
                            work: work,
                            recovery: recovery,
                            skipRecovery: repetition < totalRepetitions ? !recoveryEnabled : nil,
                            ghostPaceSecondsPerKilometer:
                                customGhostEnabled ? Double(customGhostPaceSeconds) : nil,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? nil : String(notes.prefix(220))
                        ))
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: paceAsSpeed) { _, speed in
            if speed {
                targetSpeedKmh = 3_600 / Double(max(paceSeconds, 1))
            } else {
                paceSeconds = Int((3_600 / max(targetSpeedKmh, 0.1)).rounded())
            }
        }
        .tint(ATHLTHTrainDesign.bronze)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private func paceLabel(_ seconds: Int) -> String { clock(seconds) + "/km" }
}
