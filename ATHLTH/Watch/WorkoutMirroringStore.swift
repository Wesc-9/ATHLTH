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
    @Published private(set) var lastCoachMessage: String?
    @Published private(set) var ghostDisableRequestGeneration = 0

    func setAIConversationActive(_ active: Bool) {
        guard aiConversationActive != active else { return }
        aiConversationActive = active
        if active {
            // Never change HealthKit recording or remote Watch cue ownership.
            // Only suspend the local phone voice while the AI has its audio.
            iPhoneAudioCoach.suspendForWatchFallback()
        } else if iPhoneAudioCoachAttached, let snapshot {
            // Align milestones to current progress; old cues must not replay.
            iPhoneAudioCoach.synchronizeOnHandoff(snapshot)
        }
    }

    var mirroredIPhoneCoachAvailable: Bool {
        iPhoneAudioCoachAttached &&
        iPhoneAudioCoach.isEnabled &&
        (snapshot?.kind == .running || snapshot?.kind == .walking)
    }

    var isIPhoneCoachVoiceOwner: Bool {
        mirroredIPhoneCoachAvailable &&
        (snapshot?.supportsAudioCoachVoiceLease != true ||
            hasAcknowledgedVoiceLease)
    }

    var canReplayMirroredCoachMessage: Bool {
        isIPhoneCoachVoiceOwner &&
        iPhoneAudioCoach.canReplayLastCoachMessage
    }

    func replayMirroredCoachMessage() {
        guard canReplayMirroredCoachMessage else { return }
        iPhoneAudioCoach.replayLastCoachMessage()
    }

    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    private let iPhoneAudioCoach =
        MirroredWorkoutAudioCoach()
    private var aiConversationActive = false
    private var iPhoneAudioCoachPreparedAt:
        Date?
    private var iPhoneAudioCoachAttached =
        false
    private var voiceLeaseGenerationID = UUID()
    private var latestVoiceLeaseRequestID: UUID?
    private var lastVoiceLeaseOfferAt: Date?
    private var voiceLeaseAcknowledgedUntil: Date?
    private var voiceLeaseExpiryTask: Task<Void, Never>?

    private var hasAcknowledgedVoiceLease: Bool {
        guard let voiceLeaseAcknowledgedUntil else {
            return false
        }
        return Date() < voiceLeaseAcknowledgedUntil
    }

    private func resetVoiceLease() {
        voiceLeaseExpiryTask?.cancel()
        voiceLeaseExpiryTask = nil
        voiceLeaseGenerationID = UUID()
        latestVoiceLeaseRequestID = nil
        lastVoiceLeaseOfferAt = nil
        voiceLeaseAcknowledgedUntil = nil
        if !aiConversationActive {
            iPhoneAudioCoach.suspendForWatchFallback()
        }
    }

    private func offerVoiceLeaseIfNeeded(
        for snapshot: WatchWorkoutLiveSnapshot
    ) {
        guard iPhoneAudioCoachAttached,
              iPhoneAudioCoach.isEnabled,
              snapshot.supportsAudioCoachVoiceLease == true,
              snapshot.kind == .running ||
                snapshot.kind == .walking,
              snapshot.state == .running ||
                snapshot.state == .paused ||
                snapshot.state == .preparing,
              let startedAt = snapshot.startedAt,
              let session = mirroredSession
        else {
            return
        }

        let now = Date()
        guard abs(now.timeIntervalSince(snapshot.capturedAt)) <= 4,
              lastVoiceLeaseOfferAt.map({
                  now.timeIntervalSince($0) >= 2
              }) ?? true
        else {
            return
        }

        let requestID = UUID()
        let offer = ATHLTHAudioCoachLeaseOffer(
            generationID: voiceLeaseGenerationID,
            requestID: requestID,
            workoutStartedAt: startedAt,
            issuedAt: now
        )
        guard let payload = try? JSONEncoder().encode(offer) else {
            return
        }

        latestVoiceLeaseRequestID = requestID
        lastVoiceLeaseOfferAt = now
        Task { @MainActor in
            try? await session.sendToRemoteWorkoutSession(
                data: payload
            )
        }
    }

    private func receiveVoiceLeaseAcknowledgement(
        _ acknowledgement: ATHLTHAudioCoachLeaseAcknowledgement,
        latestSnapshot: WatchWorkoutLiveSnapshot? = nil
    ) {
        guard iPhoneAudioCoachAttached,
              iPhoneAudioCoach.isEnabled,
              mirroredSession != nil,
              acknowledgement.generationID ==
                voiceLeaseGenerationID,
              acknowledgement.requestID ==
                latestVoiceLeaseRequestID,
              let current = latestSnapshot ?? snapshot,
              current.supportsAudioCoachVoiceLease == true,
              current.state == .running ||
                current.state == .paused ||
                current.state == .preparing,
              let startedAt = current.startedAt,
              abs(startedAt.timeIntervalSince(
                  acknowledgement.workoutStartedAt
              )) <= 1,
              abs(Date().timeIntervalSince(
                  acknowledgement.acknowledgedAt
              )) <= 4
        else {
            return
        }

        let wasActive = hasAcknowledgedVoiceLease
        voiceLeaseAcknowledgedUntil =
            Date().addingTimeInterval(4.5)
        voiceLeaseExpiryTask?.cancel()
        let generationID = voiceLeaseGenerationID
        voiceLeaseExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled,
                  let self,
                  self.voiceLeaseGenerationID == generationID,
                  !self.hasAcknowledgedVoiceLease
            else { return }
            self.voiceLeaseAcknowledgedUntil = nil
            if !self.aiConversationActive {
                self.iPhoneAudioCoach.suspendForWatchFallback()
            }
        }

        if !wasActive {
            iPhoneAudioCoach.synchronizeOnHandoff(current)
        }
    }

    private func sendSpokenEventReceipt(
        event: ATHLTHCoachEvent,
        startedAt: Date
    ) {
        guard iPhoneAudioCoachAttached,
              hasAcknowledgedVoiceLease,
              let session = mirroredSession,
              let currentStart = snapshot?.startedAt,
              abs(currentStart.timeIntervalSince(startedAt)) <= 1
        else { return }

        let receipt = ATHLTHCoachDeliveryReceipt(
            workoutStartedAt: startedAt,
            eventKind: event.kind,
            eventKey: event.key,
            sentAt: Date()
        )
        guard receipt.isValid(for: currentStart),
              let data = try? JSONEncoder().encode(receipt)
        else { return }

        Task { @MainActor in
            try? await session.sendToRemoteWorkoutSession(data: data)
        }
    }

    override init() {
        super.init()

        iPhoneAudioCoach.onLastSpokenCoachMessage = { [weak self] message in
            self?.lastCoachMessage = message
        }
        iPhoneAudioCoach.onSpokenEventAttempt = { [weak self] event, startedAt in
            self?.sendSpokenEventReceipt(
                event: event,
                startedAt: startedAt
            )
        }

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
            clearIPhoneAudioCoach()
            return
        }

        resetVoiceLease()
        iPhoneAudioCoach.prepare(
            configuration
        )
        iPhoneAudioCoachPreparedAt =
            Date()
        iPhoneAudioCoachAttached =
            false
    }

    func clearIPhoneAudioCoach() {
        aiConversationActive = false
        resetVoiceLease()
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

    /// Continue the SAME HealthKit workout on the reversed A–B route.
    /// An explicit workout start token prevents stale mirror commands
    /// redirecting a newer session after Watch reconnect.
    @discardableResult
    func requestRunBackToStart() -> Bool {
        guard let mirroredSession,
              let snapshot,
              snapshot.routeCanReturnToStart == true,
              let startedAt = snapshot.startedAt,
              hasActiveMirroredWorkout else {
            publish {
                self.errorMessage = ATHLTHLocalization.choose(
                    english: "Return guidance is available near the end of the planned route.",
                    norwegian: "Returveiledning er tilgjengelig når du nærmer deg slutten av ruten."
                )
            }
            return false
        }

        guard let data = try? JSONEncoder().encode(
            WatchWorkoutMirrorCommand(
                command: .returnToStart,
                workoutStartedAt: startedAt
            )
        ) else { return false }

        Task {
            do {
                try await mirroredSession.sendToRemoteWorkoutSession(data: data)
            } catch {
                publish { self.errorMessage = error.localizedDescription }
            }
        }
        return true
    }

    /// Advance only the currently shown running phase in the same Watch workout.
    /// A reconnect or double tap cannot turn one request into two skipped phases.
    @discardableResult
    func advanceRunningStep(expectedIndex: Int, startedAt: Date?, startMain: Bool = false) -> Bool {
        guard let mirroredSession,
              let startedAt,
              hasActiveMirroredWorkout,
              snapshot?.state == .running,
              snapshot?.runningStepIndex == expectedIndex,
              snapshot?.runningManualAdvanceRequired == true
        else { return false }

        guard let data = try? JSONEncoder().encode(
            WatchWorkoutMirrorCommand(
                command: .advanceRunningStep,
                workoutStartedAt: startedAt,
                expectedRunningStepIndex: expectedIndex,
                startMainAfterWarmup: startMain
            )
        ) else { return false }

        Task {
            do {
                try await mirroredSession.sendToRemoteWorkoutSession(data: data)
            } catch {
                publish { self.errorMessage = error.localizedDescription }
            }
        }
        return true
    }

    @discardableResult
    func sendTreadmillInclinePercent(
        _ percent: Double
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

        let value =
            min(
                max(
                    (percent * 2).rounded() / 2,
                    0
                ),
                20
            )

        guard let data = try? JSONEncoder().encode(
            WatchWorkoutMirrorCommand(
                command: .setTreadmillIncline,
                treadmillInclinePercent: value
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

    @discardableResult
    func sendTreadmillTargetPaceSecondsPerKilometer(_ seconds: Double) -> Bool {
        guard let mirroredSession, let startedAt = snapshot?.startedAt,
              snapshot?.kind == .running,
              seconds.isFinite, (120...1200).contains(seconds),
              let data = try? JSONEncoder().encode(WatchWorkoutMirrorCommand(
                  command: .setTreadmillTargetPace,
                  treadmillTargetPaceSecondsPerKilometer: seconds,
                  workoutStartedAt: startedAt
              )) else { return false }
        Task {
            do {
                try await mirroredSession.sendToRemoteWorkoutSession(data: data)
            } catch {
                publish { self.errorMessage = error.localizedDescription }
            }
        }
        return true
    }

    /// Append interval steps without creating another HealthKit session.
    /// The Watch validates the startedAt token and performs the append.
    /// This returns only whether the command could be sent, not an ACK.
    @discardableResult
    func appendRunningWorkout(
        _ template: RunningWorkoutTemplate,
        startNow: Bool
    ) -> Bool {
        guard hasActiveMirroredWorkout,
              let snapshot,
              snapshot.kind == .running,
              (snapshot.state == .running || snapshot.state == .paused),
              let startedAt = snapshot.startedAt,
              let mirroredSession else { return false }

        let transfer = watchRunningWorkoutTransfer(from: template)
        // An active structured step must be queued, never replaced.
        guard ATHLTHRunningWorkoutAppendPolicy.canAppend(
            hasInProgressStructuredSteps: snapshot.runningStepTitle != nil,
            startNow: startNow,
            steps: transfer.steps
        ) else { return false }

        let command = WatchWorkoutMirrorCommand(
            command: .appendRunningWorkout,
            workoutStartedAt: startedAt,
            runningWorkoutToAppend: transfer,
            runningWorkoutStartImmediately: startNow,
            commandID: UUID()
        )
        guard let data = try? JSONEncoder().encode(command) else {
            return false
        }

        Task { @MainActor in
            do {
                try await mirroredSession.sendToRemoteWorkoutSession(data: data)
            } catch {
                publish { self.errorMessage = error.localizedDescription }
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
        // A reconnected Watch session can reuse its own last measured data.
        // A different workout must never inherit cached heart rate, calories
        // or distance from the previous session while awaiting live samples.
        let incomingKind = workoutKind(
            for: session.workoutConfiguration.activityType
        )
        let carry = ATHLTHWorkoutMirrorContinuity.mayCarryRecordedMetrics(
            previous: snapshot,
            newKind: incomingKind,
            newStartedAt: session.startDate
        )
        let previous = carry ? snapshot : nil

        session.delegate = self
        mirroredSession = session
        ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive = true
        ATHLTHWatchWorkoutRuntime.lastMirrorDetectedAt = Date()

        let initialSnapshot = WatchWorkoutLiveSnapshot(
            kind: incomingKind,
            state: mirrorState(for: session.state),
            startedAt: session.startDate,
            capturedAt: Date(),
            elapsedTime: elapsedTime(for: session),
            heartRate: previous?.heartRate ?? 0,
            activeCalories: previous?.activeCalories ?? 0,
            distanceMeters: previous?.distanceMeters ?? 0,
            averageHeartRate: previous?.averageHeartRate,
            maxHeartRate: previous?.maxHeartRate,
            routePointCount: previous?.routePointCount ?? 0
        )

        if let preparedAt =
                iPhoneAudioCoachPreparedAt,
           Date()
                .timeIntervalSince(
                    preparedAt
                ) <= 90 {
            iPhoneAudioCoachAttached =
                true
            offerVoiceLeaseIfNeeded(
                for: initialSnapshot
            )
        } else {
            clearIPhoneAudioCoach()
        }

        publish {
            self.snapshot = initialSnapshot
            self.liveViewIsVisible = false
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
        var receipts: [ATHLTHCoachDeliveryReceipt] = []
        var acknowledgements: [ATHLTHAudioCoachLeaseAcknowledgement] = []
        var ghostDisableRequests: [ATHLTHGhostDisableDuringWorkout] = []

        // Decode the whole batch before acting on receipts or lease acks.
        // HealthKit can deliver these alongside the first snapshot for a
        // workout, while the cached snapshot still describes another state.
        for data in incoming {
            if let command = try? JSONDecoder().decode(
                ATHLTHGhostDisableDuringWorkout.self, from: data
            ) {
                ghostDisableRequests.append(command)
                continue
            }
            if let receipt = try? JSONDecoder().decode(
                ATHLTHCoachDeliveryReceipt.self,
                from: data
            ) {
                receipts.append(receipt)
                continue
            }

            if let acknowledgement = try? JSONDecoder().decode(
                ATHLTHAudioCoachLeaseAcknowledgement.self,
                from: data
            ) {
                acknowledgements.append(acknowledgement)
                continue
            }

            if let decoded = try? JSONDecoder().decode(
                WatchWorkoutLiveSnapshot.self,
                from: data
            ) {
                latestSnapshot = decoded
            }
        }

        let currentStart = latestSnapshot?.startedAt ?? snapshot?.startedAt
        if ghostDisableRequests.contains(where: {
            $0.isValid(workoutStart: currentStart)
        }) {
            publish { self.ghostDisableRequestGeneration &+= 1 }
        }

        // Record Watch speech before handling the snapshot: otherwise the
        // iPhone could speak the same structured step while taking ownership.
        if iPhoneAudioCoachAttached {
            for receipt in receipts {
                if let verifiedStart =
                    ATHLTHCoachReceiptAcceptance.verifiedWorkoutStart(
                        for: receipt,
                        latestSnapshot: latestSnapshot,
                        previousSnapshot: snapshot
                    ) {
                    iPhoneAudioCoach.recordWatchSpokenEvent(
                        receipt,
                        verifiedWorkoutStart: verifiedStart
                    )
                }
            }
        }

        for acknowledgement in acknowledgements {
            receiveVoiceLeaseAcknowledgement(
                acknowledgement,
                latestSnapshot: latestSnapshot
            )
        }

        guard let latestSnapshot else { return }

        if iPhoneAudioCoachAttached {
            if aiConversationActive {
                // Already muted when AI conversation began. Never deactivate
                // the audio session again while AI uses the microphone.
            } else if latestSnapshot.supportsAudioCoachVoiceLease != true {
                // Preserve the pre-lease phone speech path while the
                // paired Watch app is still on an older build.
                iPhoneAudioCoach.handle(latestSnapshot)
            } else {
                if hasAcknowledgedVoiceLease {
                    iPhoneAudioCoach.handle(latestSnapshot)
                } else {
                    iPhoneAudioCoach.suspendForWatchFallback()
                }
                offerVoiceLeaseIfNeeded(for: latestSnapshot)
            }
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
            if latestSnapshot.state == .completed ||
                latestSnapshot.state == .failed {
                // The Watch is authoritative for workout state. Once it says
                // the workout has ended, stop presenting the frozen live UI
                // immediately. Keep the completed snapshot in memory long
                // enough for the result/review pipeline to reconcile it.
                self.isPresentationRequested = false
                self.liveViewIsVisible = false
            } else if !self.isUserMinimized {
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

    /// An explicit inactive Watch response also ends a stale live mirror.
    /// Ignore inactive messages from before this workout started.
    func reconcileInactiveWatchActivity(_ activity: WatchWorkoutActivityState) {
        guard !activity.isActive, var current = snapshot,
              hasActiveMirroredWorkout,
              current.startedAt.map({ $0 <= activity.updatedAt })
                ?? (current.capturedAt <= activity.updatedAt)
        else { return }
        current.state = .completed
        current.capturedAt = activity.updatedAt
        snapshot = current
        mirroredSession = nil
        isPresentationRequested = false
        liveViewIsVisible = false
        ATHLTHWatchWorkoutRuntime.isMirroredWorkoutActive = false
        ATHLTHWatchWorkoutRuntime.lastMirrorDetectedAt = Date()
        clearIPhoneAudioCoach()
    }

    func reconcileCompletedWatchWorkout(
        _ result: WatchWorkoutResult
    ) {
        guard var snapshot,
              ATHLTHWorkoutMirrorContinuity.canApplyCompletion(
                snapshot: snapshot, kind: result.kind,
                startedAt: result.startedAt, endedAt: result.endedAt
              )
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
            if !aiConversationActive &&
               (snapshot.supportsAudioCoachVoiceLease != true ||
                hasAcknowledgedVoiceLease) {
                iPhoneAudioCoach.handle(snapshot)
            }
            resetVoiceLease()
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
        isPresentationRequested = false
        liveViewIsVisible = false
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
        let sessionID = ObjectIdentifier(workoutSession)

        Task { @MainActor [weak self] in
            guard let self,
                  ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
                      activeSession: self.mirroredSession.map(ObjectIdentifier.init),
                      incomingSession: sessionID
                  ),
                  let sessionState = HKWorkoutSessionState(rawValue: rawState)
            else {
                return
            }

            let newState = ATHLTHWorkoutMirrorStatePolicy.state(for: sessionState)

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
                if !self.aiConversationActive &&
                   (snapshot.supportsAudioCoachVoiceLease != true ||
                    self.hasAcknowledgedVoiceLease) {
                    self.iPhoneAudioCoach.handle(snapshot)
                }
                self.offerVoiceLeaseIfNeeded(for: snapshot)
            }

            self.connectionText =
                newState == .ending
                    ? ATHLTHLocalization.choose(
                        english: "Saving Apple Watch workout",
                        norwegian: "Lagrer Apple Watch-økten"
                    )
                    : newState == .completed
                        ? ATHLTHLocalization.choose(
                            english: "Workout completed",
                            norwegian: "Økt fullført"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Live from Apple Watch",
                            norwegian: "Direkte fra Apple Watch"
                        )
            if newState == .completed ||
                newState == .failed {
                self.isPresentationRequested = false
                self.liveViewIsVisible = false
            } else if !self.isUserMinimized {
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
        let sessionID = ObjectIdentifier(workoutSession)

        Task { @MainActor [weak self] in
            guard let self,
                  ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
                      activeSession: self.mirroredSession.map(ObjectIdentifier.init),
                      incomingSession: sessionID
                  )
            else { return }

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
        let sessionID = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            guard let self,
                  ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
                      activeSession: self.mirroredSession.map(ObjectIdentifier.init),
                      incomingSession: sessionID
                  )
            else { return }
            self.handle(data)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        let message = error?.localizedDescription
        let sessionID = ObjectIdentifier(workoutSession)

        Task { @MainActor [weak self] in
            guard let self,
                  ATHLTHWorkoutMirrorContinuity.acceptsDelegateCallback(
                      activeSession: self.mirroredSession.map(ObjectIdentifier.init),
                      incomingSession: sessionID
                  )
            else { return }

            self.mirroredSession = nil
            self.clearIPhoneAudioCoach()
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
