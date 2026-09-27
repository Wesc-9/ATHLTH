import Combine
import Foundation
@preconcurrency import HealthKit

@MainActor
final class WorkoutMirroringStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchWorkoutLiveSnapshot?
    @Published private(set) var connectionText = "Waiting for Apple Watch"
    @Published private(set) var errorMessage: String?
    @Published var isPresentationRequested = false

    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?

    override init() {
        super.init()

        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor [weak self] in
                self?.attach(session)
            }
        }
    }

    var hasActiveMirroredWorkout: Bool {
        guard let state = snapshot?.state else { return false }
        return state == .preparing ||
            state == .running ||
            state == .paused ||
            state == .ending
    }

    func sendCommand(_ command: WatchWorkoutCommand) {
        guard let mirroredSession else {
            publish {
                self.errorMessage = "The mirrored Apple Watch workout is not connected."
            }
            return
        }

        guard let data = try? JSONEncoder().encode(
            WatchWorkoutMirrorCommand(command: command)
        ) else {
            return
        }

        Task {
            do {
                try await mirroredSession.sendToRemoteWorkoutSession(data: data)
            } catch {
                publish {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func dismissSummary() {
        guard !hasActiveMirroredWorkout else { return }

        publish {
            self.isPresentationRequested = false
            self.snapshot = nil
            self.errorMessage = nil
            self.connectionText = "Waiting for Apple Watch"
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        session.delegate = self
        mirroredSession = session

        let initialSnapshot = WatchWorkoutLiveSnapshot(
            kind: workoutKind(for: session.workoutConfiguration.activityType),
            state: mirrorState(for: session.state),
            startedAt: session.startDate,
            capturedAt: Date(),
            elapsedTime: elapsedTime(for: session),
            heartRate: snapshot?.heartRate ?? 0,
            activeCalories: snapshot?.activeCalories ?? 0,
            distanceMeters: snapshot?.distanceMeters ?? 0,
            averageHeartRate: snapshot?.averageHeartRate,
            maxHeartRate: snapshot?.maxHeartRate,
            routePointCount: snapshot?.routePointCount ?? 0
        )

        publish {
            self.snapshot = initialSnapshot
            self.connectionText = "Live from Apple Watch"
            self.errorMessage = nil
            self.isPresentationRequested = true
        }
    }

    private func handle(_ incoming: [Data]) {
        var latestSnapshot: WatchWorkoutLiveSnapshot?

        for data in incoming {
            if let decoded = try? JSONDecoder().decode(
                WatchWorkoutLiveSnapshot.self,
                from: data
            ) {
                latestSnapshot = decoded
            }
        }

        guard let latestSnapshot else { return }

        publish {
            self.snapshot = latestSnapshot
            self.connectionText = latestSnapshot.state == .completed
                ? "Workout completed"
                : "Live from Apple Watch"
            self.isPresentationRequested = true
        }
    }

    private func elapsedTime(for session: HKWorkoutSession) -> TimeInterval {
        guard let startDate = session.startDate else { return 0 }
        let endDate = session.endDate ?? Date()
        return max(0, endDate.timeIntervalSince(startDate))
    }

    private func workoutKind(
        for activityType: HKWorkoutActivityType
    ) -> WatchWorkoutKind {
        switch activityType {
        case .running:
            return .running
        case .walking:
            return .walking
        case .traditionalStrengthTraining:
            return .strength
        case .functionalStrengthTraining:
            return .functional
        case .highIntensityIntervalTraining:
            return .hiit
        case .cycling:
            return .cycling
        case .rowing:
            return .rowing
        case .stairClimbing:
            return .stairClimbing
        case .yoga:
            return .yoga
        default:
            return .other
        }
    }

    private func mirrorState(
        for state: HKWorkoutSessionState
    ) -> WatchWorkoutMirrorState {
        switch state {
        case .running:
            return .running
        case .paused:
            return .paused
        case .ended, .stopped:
            return .completed
        case .prepared, .notStarted:
            return .preparing
        @unknown default:
            return .preparing
        }
    }

    private func publish(_ changes: () -> Void) {
        changes()
    }
}

extension WorkoutMirroringStore: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let rawState = toState.rawValue
        let startedAt = workoutSession.startDate
        let endedAt = workoutSession.endDate

        Task { @MainActor [weak self] in
            guard let self,
                  let sessionState = HKWorkoutSessionState(rawValue: rawState)
            else {
                return
            }

            let newState = self.mirrorState(for: sessionState)

            guard var snapshot = self.snapshot else { return }
            snapshot.state = newState
            snapshot.startedAt = startedAt ?? snapshot.startedAt

            if let start = startedAt {
                let end = endedAt ?? Date()
                snapshot.elapsedTime = max(
                    0,
                    end.timeIntervalSince(start)
                )
            }

            self.snapshot = snapshot
            self.connectionText = newState == .completed
                ? "Workout completed"
                : "Live from Apple Watch"
            self.isPresentationRequested = true

            if newState == .completed {
                self.mirroredSession = nil
            }
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.errorMessage = message

            if var snapshot = self.snapshot {
                snapshot.state = .failed
                self.snapshot = snapshot
            }

            self.connectionText = "Mirroring error"
            self.isPresentationRequested = true
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor [weak self] in
            self?.handle(data)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        let message = error?.localizedDescription

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.mirroredSession = nil
            self.connectionText = "Reconnecting to Apple Watch"

            if let message {
                self.errorMessage = message
            }
        }
    }
}
