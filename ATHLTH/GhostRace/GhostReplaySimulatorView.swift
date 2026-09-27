import SwiftUI

@MainActor
final class GhostReplaySimulatorStore: ObservableObject {
    enum ReplayState: Equatable {
        case idle
        case ready
        case running
        case paused
        case completed

        var title: String {
            switch self {
            case .idle: return "Idle"
            case .ready: return "Ready"
            case .running: return "Running"
            case .paused: return "Paused"
            case .completed: return "Completed"
            }
        }
    }

    @Published private(set) var snapshot: WatchWorkoutLiveSnapshot?
    @Published private(set) var state: ReplayState = .idle
    @Published var playbackSpeed: Double = 20
    @Published var runnerSpeedMultiplier: Double = 1.03

    private var replayTask: Task<Void, Never>?
    private var elapsedTime: TimeInterval = 0

    deinit {
        replayTask?.cancel()
    }

    func markReady() {
        stopTask()
        elapsedTime = 0
        snapshot = nil
        state = .ready
    }

    func start(
        reference: GhostRaceReference,
        ghostRace: GhostRaceStore
    ) {
        stopTask()

        elapsedTime = 0
        state = .running

        replayTask = Task { @MainActor [weak self, weak ghostRace] in
            guard let self,
                  let ghostRace
            else {
                return
            }

            var previousTick = Date()

            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .milliseconds(100)
                )

                guard !Task.isCancelled else {
                    return
                }

                guard self.state != .paused else {
                    previousTick = Date()
                    continue
                }

                guard self.state == .running else {
                    return
                }

                let now = Date()
                let realDelta = max(
                    now.timeIntervalSince(previousTick),
                    0
                )
                previousTick = now

                let replayDelta =
                    realDelta *
                    max(self.playbackSpeed, 1)

                self.elapsedTime =
                    min(
                        self.elapsedTime + replayDelta,
                        max(
                            reference.durationSeconds,
                            1
                        )
                    )

                let runnerReferenceTime =
                    min(
                        self.elapsedTime *
                            max(
                                self.runnerSpeedMultiplier,
                                0.5
                            ),
                        max(
                            reference.durationSeconds,
                            0
                        )
                    )

                let runnerPoint =
                    Self.point(
                        at: runnerReferenceTime,
                        in: reference
                    )

                let completed =
                    self.elapsedTime >=
                        reference.durationSeconds ||
                    runnerPoint.cumulativeMeters >=
                        reference.routeDistanceMeters *
                        0.995

                let newSnapshot =
                    WatchWorkoutLiveSnapshot(
                        kind: .running,
                        state:
                            completed
                                ? .completed
                                : .running,
                        startedAt:
                            Date().addingTimeInterval(
                                -self.elapsedTime
                            ),
                        capturedAt: Date(),
                        elapsedTime:
                            self.elapsedTime,
                        heartRate:
                            148 +
                            sin(
                                self.elapsedTime / 45
                            ) * 8,
                        activeCalories:
                            self.elapsedTime /
                            60 * 9.5,
                        distanceMeters:
                            runnerPoint
                                .cumulativeMeters,
                        averageHeartRate: 151,
                        maxHeartRate: 166,
                        routePointCount:
                            max(
                                runnerPoint.id + 1,
                                1
                            ),
                        currentLatitude:
                            runnerPoint.latitude,
                        currentLongitude:
                            runnerPoint.longitude,
                        routeProgressPercent:
                            reference
                                .routeDistanceMeters >
                                0
                                ? (
                                    runnerPoint
                                        .cumulativeMeters /
                                    reference
                                        .routeDistanceMeters
                                ) * 100
                                : nil
                    )

                self.snapshot =
                    newSnapshot
                ghostRace.update(
                    with: newSnapshot
                )

                if completed {
                    self.state = .completed
                    self.replayTask = nil
                    return
                }
            }
        }
    }

    func togglePause() {
        switch state {
        case .running:
            state = .paused
            if var snapshot {
                snapshot.state = .paused
                snapshot.capturedAt = Date()
                self.snapshot = snapshot
            }
        case .paused:
            state = .running
            if var snapshot {
                snapshot.state = .running
                snapshot.capturedAt = Date()
                self.snapshot = snapshot
            }
        default:
            break
        }
    }

    func reset(
        ghostRace: GhostRaceStore
    ) {
        stopTask()
        elapsedTime = 0
        snapshot = nil
        state = .idle
        ghostRace.cancel()
    }

    private func stopTask() {
        replayTask?.cancel()
        replayTask = nil
    }

    private static func point(
        at elapsedTime: TimeInterval,
        in reference: GhostRaceReference
    ) -> GhostRacePoint {
        guard reference.points.count > 1 else {
            return reference.points[0]
        }

        let target =
            min(
                max(elapsedTime, 0),
                max(
                    reference.durationSeconds,
                    0
                )
            )

        var low = 0
        var high =
            reference.points.count - 1

        while low < high {
            let mid =
                (low + high + 1) / 2

            if reference.points[mid]
                .elapsedTime <= target {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return reference.points[low]
    }
}

struct GhostReplaySimulatorView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore

    @StateObject private var ghostRace =
        GhostRaceStore()
    @StateObject private var replay =
        GhostReplaySimulatorStore()

    @State private var runs: [WorkoutSummary] = []
    @State private var selectedWorkoutID: UUID?
    @State private var selectedWorkout: WorkoutSummary?
    @State private var loading = false
    @State private var preparing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                warningCard
                sourceCard
                controlsCard

                if let snapshot =
                        replay.snapshot {
                    GhostRaceLivePanel(
                        snapshot: snapshot
                    )
                    .environmentObject(
                        ghostRace
                    )
                } else if ghostRace.reference != nil {
                    ATHLTHCard {
                        ContentUnavailableView(
                            "Replay ready",
                            systemImage:
                                "play.circle.fill",
                            description: Text(
                                "Start the simulator to replay this route without going outside."
                            )
                        )
                        .frame(minHeight: 160)
                    }
                }
            }
            .padding()
            .padding(.bottom, 36)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(
            "Ghost Replay Simulator"
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadRuns()
        }
        .onDisappear {
            replay.reset(
                ghostRace: ghostRace
            )
        }
        .alert(
            "Ghost Replay",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { visible in
                    if !visible {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var warningCard: some View {
        ATHLTHCard {
            HStack(
                alignment: .top,
                spacing: 12
            ) {
                Image(
                    systemName:
                        "wrench.and.screwdriver.fill"
                )
                .foregroundStyle(.orange)

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text("Internal developer tool")
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )

                    Text(
                        "This replays a saved GPS workout through the Ghost Race engine. It never starts HealthKit, Apple Watch or a real workout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var sourceCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 13
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Reference run")
                            .font(.headline)

                        Text(
                            "Choose an outdoor run from Apple Health."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if loading ||
                        preparing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Picker(
                    "Reference run",
                    selection:
                        Binding(
                            get: {
                                selectedWorkoutID
                            },
                            set: { newValue in
                                selectedWorkoutID =
                                    newValue

                                Task {
                                    await prepareSelectedRun()
                                }
                            }
                        )
                ) {
                    Text("Choose run")
                        .tag(UUID?.none)

                    ForEach(runs.prefix(40)) {
                        workout in
                        Text(
                            runTitle(workout)
                        )
                        .tag(
                            Optional(workout.id)
                        )
                    }
                }
                .pickerStyle(.menu)

                if let selectedWorkout {
                    HStack(spacing: 16) {
                        Label(
                            selectedWorkout
                                .distanceKilometers
                                .map {
                                    String(
                                        format:
                                            "%.2f km",
                                        $0
                                    )
                                } ??
                                "No distance",
                            systemImage:
                                "location.fill"
                        )

                        Label(
                            durationText(
                                selectedWorkout
                                    .duration
                            ),
                            systemImage:
                                "stopwatch.fill"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var controlsCard: some View {
        ATHLTHCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Replay controls")
                            .font(.headline)

                        Text(
                            "Change playback speed and simulate a runner who is faster or slower than the ghost."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(replay.state.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(
                            replay.state == .running
                                ? ATHLTHTheme.vitality
                                : .secondary
                        )
                }

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    HStack {
                        Text("Playback")
                        Spacer()
                        Text(
                            String(
                                format: "%.0f×",
                                replay.playbackSpeed
                            )
                        )
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value:
                            $replay.playbackSpeed,
                        in: 5...60,
                        step: 5
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    HStack {
                        Text("Virtual runner")
                        Spacer()
                        Text(
                            relativeRunnerText
                        )
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value:
                            $replay
                                .runnerSpeedMultiplier,
                        in: 0.85...1.15,
                        step: 0.01
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        startReplay()
                    } label: {
                        Label(
                            replay.state == .completed
                                ? "Replay again"
                                : "Start replay",
                            systemImage:
                                "play.fill"
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .tint(
                        ATHLTHTheme.vitality
                    )
                    .disabled(
                        ghostRace.reference ==
                            nil ||
                        workoutMirroring
                            .hasActiveMirroredWorkout ||
                        replay.state ==
                            .running
                    )

                    if replay.state ==
                            .running ||
                        replay.state ==
                            .paused {
                        Button {
                            replay.togglePause()
                        } label: {
                            Image(
                                systemName:
                                    replay.state ==
                                    .paused
                                        ? "play.fill"
                                        : "pause.fill"
                            )
                            .frame(
                                width: 36,
                                height: 36
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        replay.reset(
                            ghostRace: ghostRace
                        )
                        selectedWorkoutID =
                            nil
                        selectedWorkout =
                            nil
                    } label: {
                        Image(
                            systemName:
                                "arrow.counterclockwise"
                        )
                        .frame(
                            width: 36,
                            height: 36
                        )
                    }
                    .buttonStyle(.bordered)
                }

                if workoutMirroring
                    .hasActiveMirroredWorkout {
                    Label(
                        "Simulator is locked while a real mirrored workout is active.",
                        systemImage:
                            "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var relativeRunnerText: String {
        let percent =
            Int(
                (
                    (
                        replay
                            .runnerSpeedMultiplier -
                        1
                    ) * 100
                ).rounded()
            )

        if percent == 0 {
            return "Same speed"
        }

        if percent > 0 {
            return "\(percent)% faster"
        }

        return "\(abs(percent))% slower"
    }

    private func startReplay() {
        guard let reference =
                ghostRace.reference
        else {
            return
        }

        replay.start(
            reference: reference,
            ghostRace: ghostRace
        )
    }

    @MainActor
    private func loadRuns() async {
        loading = true
        defer {
            loading = false
        }

        let history =
            (try? await health
                .workoutHistory()) ??
            health.workouts

        runs =
            history
                .filter {
                    $0.activity == .running &&
                    ($0.distanceMeters ?? 0) >=
                        250
                }
                .sorted {
                    $0.startDate >
                    $1.startDate
                }
    }

    @MainActor
    private func prepareSelectedRun() async {
        guard let selectedWorkoutID,
              let workout =
                runs.first(
                    where: {
                        $0.id ==
                        selectedWorkoutID
                    }
                )
        else {
            return
        }

        guard !workoutMirroring
            .hasActiveMirroredWorkout
        else {
            errorMessage =
                "Finish the real mirrored workout before using the replay simulator."
            return
        }

        preparing = true
        defer {
            preparing = false
        }

        replay.reset(
            ghostRace: ghostRace
        )

        let detail =
            await health.workoutDetail(
                for: workout
            )

        do {
            try ghostRace.prepare(
                workoutID: workout.id,
                title:
                    workout.activity.rawValue,
                activity:
                    workout.activity,
                startedAt:
                    workout.startDate,
                duration:
                    workout.duration,
                distanceMeters:
                    workout.distanceMeters,
                route:
                    detail.route
            )

            selectedWorkout = workout
            replay.markReady()
        } catch {
            selectedWorkout = nil
            errorMessage =
                error.localizedDescription
        }
    }

    private func runTitle(
        _ workout: WorkoutSummary
    ) -> String {
        let distance =
            workout.distanceKilometers
                .map {
                    String(
                        format:
                            "%.1f km",
                        $0
                    )
                } ??
            "Run"

        return
            "\(workout.startDate.formatted(date: .abbreviated, time: .shortened)) · \(distance)"
    }

    private func durationText(
        _ seconds: TimeInterval
    ) -> String {
        let value =
            max(
                Int(seconds.rounded()),
                0
            )
        let hours = value / 3_600
        let minutes =
            (value % 3_600) / 60
        let remainder =
            value % 60

        if hours > 0 {
            return String(
                format:
                    "%d:%02d:%02d",
                hours,
                minutes,
                remainder
            )
        }

        return String(
            format:
                "%d:%02d",
            minutes,
            remainder
        )
    }
}
