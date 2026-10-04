import Combine
import Foundation
@preconcurrency import HealthKit

@MainActor
enum ATHLTHWatchWorkoutRuntime {
    static var isMirroredWorkoutActive = false
    static var lastMirrorDetectedAt: Date?
}

@MainActor
final class WorkoutMirroringStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchWorkoutLiveSnapshot?
    @Published private(set) var connectionText =
        ATHLTHLocalization.choose(
            english: "Waiting for Apple Watch",
            norwegian: "Venter på Apple Watch"
        )
    @Published private(set) var errorMessage: String?
    @Published var isPresentationRequested = false
    @Published private(set) var isUserMinimized = false
    @Published private(set) var liveViewIsVisible = false
    @Published private(set) var presentationGeneration = 0

    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private let iPhoneAudioCoach =
        MirroredWorkoutAudioCoach()
    private var iPhoneAudioCoachPreparedAt:
        Date?
    private var iPhoneAudioCoachAttached =
        false

    override init() {
        super.init()

        guard ATHLTHDeviceRole
            .supportsDirectAppleWatch
        else {
            return
        }

        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor [weak self] in
                self?.attach(session)
            }
        }
    }

    func prepareIPhoneAudioCoach(
        _ configuration:
            WatchAudioCoachConfiguration
    ) {
        guard configuration.enabled else {
            iPhoneAudioCoach.stop()
            iPhoneAudioCoachPreparedAt = nil
            iPhoneAudioCoachAttached = false
            return
        }

        iPhoneAudioCoach.prepare(
            configuration
        )
        iPhoneAudioCoachPreparedAt =
            Date()
        iPhoneAudioCoachAttached =
            false
    }

    func clearIPhoneAudioCoach() {
        iPhoneAudioCoach.stop()
        iPhoneAudioCoachPreparedAt = nil
        iPhoneAudioCoachAttached = false
    }

    var hasActiveMirroredWorkout: Bool {
        guard let state = snapshot?.state else { return false }
        return state == .preparing ||
            state == .running ||
            state == .paused ||
            state == .ending
    }

    @discardableResult
    func sendCommand(
        _ command: WatchWorkoutCommand
    ) -> Bool {
        guard let mirroredSession else {
            publish {
                self.errorMessage =
                    ATHLTHLocalization.choose(
                        english:
                            "The mirrored Apple Watch workout is reconnecting.",
                        norwegian:
                            "Den speilede Apple Watch-økten kobler til på nytt."
                    )
            }
            return false
        }

        guard let data = try? JSONEncoder().encode(
            WatchWorkoutMirrorCommand(
                command: command
            )
        ) else {
            return false
        }

        Task {
            do {
                try await mirroredSession
                    .sendToRemoteWorkoutSession(
                        data: data
                    )
            } catch {
                publish {
                    self.errorMessage =
                        error.localizedDescription
                }
            }
        }

        return true
    }

    func liveViewDidAppear() {
        liveViewIsVisible = true
    }

    func liveViewDidDisappear() {
        liveViewIsVisible = false
    }

    func presentWorkout() {
        guard snapshot != nil else {
            return
        }

        isUserMinimized = false
        presentationGeneration &+= 1
        isPresentationRequested = true
    }

    func minimizeWorkout() {
        guard hasActiveMirroredWorkout else {
            return
        }

        isUserMinimized = true
        isPresentationRequested = false
        liveViewIsVisible = false
    }

    func dismissSummary() {
        guard !hasActiveMirroredWorkout else { return }

        ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive = false
        clearIPhoneAudioCoach()

        publish {
            self.isPresentationRequested = false
            self.isUserMinimized = false
            self.liveViewIsVisible = false
            self.snapshot = nil
            self.errorMessage = nil
            self.connectionText =
                ATHLTHLocalization.choose(
                    english: "Waiting for Apple Watch",
                    norwegian: "Venter på Apple Watch"
                )
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        session.delegate = self
        mirroredSession = session
        ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive = true
        ATHLTHWatchWorkoutRuntime.lastMirrorDetectedAt = Date()

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

        if let preparedAt =
                iPhoneAudioCoachPreparedAt,
           Date()
                .timeIntervalSince(
                    preparedAt
                ) <= 90 {
            iPhoneAudioCoachAttached =
                true
            iPhoneAudioCoach.handle(
                initialSnapshot
            )
        } else {
            clearIPhoneAudioCoach()
        }

        publish {
            self.snapshot = initialSnapshot
            self.isUserMinimized = false
            self.connectionText =
                ATHLTHLocalization.choose(
                    english: "Live from Apple Watch",
                    norwegian: "Direkte fra Apple Watch"
                )
            self.errorMessage = nil
            self.presentationGeneration &+= 1
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

        if iPhoneAudioCoachAttached {
            iPhoneAudioCoach.handle(
                latestSnapshot
            )
        }

        publish {
            self.snapshot = latestSnapshot
            self.connectionText =
                latestSnapshot.state == .completed
                    ? ATHLTHLocalization.choose(
                        english:
                            "Workout completed",
                        norwegian:
                            "Økt fullført"
                    )
                    : latestSnapshot.state == .failed
                        ? ATHLTHLocalization.choose(
                            english:
                                "Workout connection ended",
                            norwegian:
                                "Økttilkoblingen ble avsluttet"
                        )
                        : ATHLTHLocalization.choose(
                            english:
                                "Live from Apple Watch",
                            norwegian:
                                "Direkte fra Apple Watch"
                        )
            if !self.isUserMinimized {
                self.isPresentationRequested = true
            }
        }

        if latestSnapshot.state == .completed ||
            latestSnapshot.state == .failed {
            mirroredSession = nil
            ATHLTHWatchWorkoutRuntime
                .isMirroredWorkoutActive =
                false
            ATHLTHWatchWorkoutRuntime
                .lastMirrorDetectedAt =
                Date()
        }
    }

    func reconcileCompletedWatchWorkout(
        _ result: WatchWorkoutResult
    ) {
        guard var snapshot,
              snapshot.kind == result.kind,
              let mirroredStartedAt =
                snapshot.startedAt,
              abs(
                mirroredStartedAt
                    .timeIntervalSince(
                        result.startedAt
                    )
              ) < 180
        else {
            return
        }

        snapshot.state = .completed
        snapshot.capturedAt = Date()
        snapshot.elapsedTime =
            result.duration
        snapshot.heartRate =
            result.averageHeartRate ??
            snapshot.heartRate
        snapshot.activeCalories =
            max(
                result.activeCalories,
                snapshot.activeCalories
            )
        snapshot.distanceMeters =
            max(
                result.distanceMeters,
                snapshot.distanceMeters
            )
        snapshot.averageHeartRate =
            result.averageHeartRate ??
            snapshot.averageHeartRate
        snapshot.maxHeartRate =
            result.maxHeartRate ??
            snapshot.maxHeartRate
        snapshot.routePointCount =
            max(
                result.routePointCount,
                snapshot.routePointCount
            )

        if iPhoneAudioCoachAttached {
            iPhoneAudioCoach.handle(
                snapshot
            )
            iPhoneAudioCoachAttached =
                false
            iPhoneAudioCoachPreparedAt =
                nil
        }

        self.snapshot = snapshot
        mirroredSession = nil
        connectionText =
            ATHLTHLocalization.choose(
                english:
                    "Workout completed",
                norwegian:
                    "Økt fullført"
            )
        isPresentationRequested = true
        ATHLTHWatchWorkoutRuntime
            .isMirroredWorkoutActive = false
        ATHLTHWatchWorkoutRuntime
            .lastMirrorDetectedAt = Date()
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

            if self.iPhoneAudioCoachAttached {
                self.iPhoneAudioCoach.handle(
                    snapshot
                )
            }

            self.connectionText =
                newState == .completed
                    ? ATHLTHLocalization.choose(
                        english: "Workout completed",
                        norwegian: "Økt fullført"
                    )
                    : ATHLTHLocalization.choose(
                        english: "Live from Apple Watch",
                        norwegian: "Direkte fra Apple Watch"
                    )
            if !self.isUserMinimized {
                self.isPresentationRequested = true
            }

            if newState == .completed {
                self.mirroredSession = nil
                ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive = false
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

            self.connectionText =
                ATHLTHLocalization.choose(
                    english: "Mirroring error",
                    norwegian: "Feil ved speiling"
                )
            if !self.isUserMinimized {
                self.isPresentationRequested = true
            }
            self.clearIPhoneAudioCoach()
            ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive = false
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
            ATHLTHWatchWorkoutRuntime
                .lastMirrorDetectedAt =
                Date()
            self.connectionText =
                ATHLTHLocalization.choose(
                    english: "Reconnecting to Apple Watch",
                    norwegian: "Kobler til Apple Watch på nytt"
                )

            if let message {
                self.errorMessage = message
            }
        }
    }
}
