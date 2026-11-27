import SwiftUI
import CoreMotion

/// Samples only during an explicit, visible count session. No raw motion
/// samples are retained or sent over the network.
@MainActor
private final class WatchRepCounter: ObservableObject {
    @Published private(set) var count = 0
    @Published private(set) var measuring = false
    @Published private(set) var unavailable = false
    private let motion = CMMotionManager()
    private var detector = ATHLTHRepMotionDetector()
    private var generation = UUID()

    func start() {
        stop()
        count = 0
        detector.reset()
        unavailable = !motion.isDeviceMotionAvailable
        guard !unavailable else { return }
        let id = UUID()
        generation = id
        measuring = true
        motion.deviceMotionUpdateInterval = 0.05
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            guard let data else {
                if error != nil {
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id else { return }
                        self.unavailable = true
                        self.stop()
                    }
                }
                return
            }
            let time = data.timestamp
            let x = data.rotationRate.x, y = data.rotationRate.y, z = data.rotationRate.z
            Task { @MainActor [weak self] in
                guard let self, self.measuring, self.generation == id else { return }
                let next = self.detector.ingest(timestamp: time, x: x, y: y, z: z)
                if next != self.count { self.count = next }
                if next >= 100 { self.stop() }
            }
        }
    }

    func stop() {
        generation = UUID()
        motion.stopDeviceMotionUpdates()
        measuring = false
    }
}

/// The existing set editor remains the only owner of confirmed reps.
/// Capturing or dismissing this sheet cannot complete an exercise.
struct WatchRepCounterButton: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    let snapshot: WatchStrengthSessionSnapshot
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(ATHLTHLocalization.choose(english: "Count reps · beta", norwegian: "Tell reps · beta"), systemImage: "waveform.path")
                .font(.system(size: 9, weight: .medium))
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showing) {
            WatchRepCounterSheet(original: snapshot)
                .environmentObject(workout)
        }
    }
}

private struct WatchRepCounterSheet: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var counter = WatchRepCounter()
    let original: WatchStrengthSessionSnapshot

    private func tr(_ en: String, _ no: String) -> String { ATHLTHLocalization.choose(english: en, norwegian: no) }

    private var sameSet: Bool {
        guard workout.state == .running, let current = workout.strengthSession else { return false }
        return current.workoutID == original.workoutID &&
            current.exerciseIndex == original.exerciseIndex && current.setIndex == original.setIndex &&
            current.setEffortStartedAt == original.setEffortStartedAt &&
            current.setEffortStartedAt != nil && !current.isResting && !current.currentExerciseComplete &&
            current.inputMode != .iPhone && !workout.strengthActionPending
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(tr("Estimated reps", "Estimerte reps")).font(.caption)
                Text(String(counter.count)).font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(tr("Experimental wrist-motion estimate. Some exercises cannot be counted reliably. Keep the watch screen open.", "Eksperimentell telling fra håndleddet. Enkelte øvelser kan ikke telles pålitelig. Hold visningen åpen."))
                    .font(.caption2).foregroundStyle(WatchTheme.muted)
                if counter.unavailable {
                    Text(tr("Motion unavailable. Enter reps manually.", "Bevegelsessensor utilgjengelig. Skriv inn reps manuelt.")).font(.caption2)
                }
                Button(counter.measuring ? tr("Stop counting", "Stopp telling") : tr("Start counting", "Start telling")) {
                    if counter.measuring { counter.stop() } else if sameSet { counter.start() }
                }
                .disabled(!sameSet)
                Button(tr("Use estimate", "Bruk forslag")) {
                    guard sameSet, !counter.measuring, counter.count > 0 else { return }
                    workout.updateStrengthDraft(reps: counter.count)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sameSet || counter.measuring || counter.count == 0)
                Button(tr("Cancel", "Avbryt"), role: .cancel) { dismiss() }
            }
        }
        .onChange(of: sameSet) { _, valid in if !valid { counter.stop(); dismiss() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { counter.stop() } }
        .onDisappear { counter.stop() }
    }
}
