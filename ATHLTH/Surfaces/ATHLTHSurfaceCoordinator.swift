import ActivityKit
import Foundation
import WidgetKit

@MainActor
enum ATHLTHSurfaceCoordinator {
    private static var lastWidgetReloadAt: Date?
    private static var lastSnapshotWriteAt: Date?
    private static var accountSurfacesEnabled = false
    private static var accountGeneration: UInt64 = 0
    private static var remoteWorkout: ATHLTHSurfaceWorkoutSnapshot?
    private static var lastRemoteWidgetReloadAt: Date?

    /// The remote activity is presentation-only; the owner device records
    /// the workout. Never start a HealthKit workout on the spectator iPad.
    static func setRemoteWorkout(_ workout: ATHLTHSurfaceWorkoutSnapshot?) {
        let previous = remoteWorkout
        remoteWorkout = workout
        var shared = ATHLTHSurfaceSharedStore.load()
        guard shared.activeWorkout == nil ||
              previous != nil else { return }
        shared.activeWorkout = workout
        shared.updatedAt = Date()
        ATHLTHSurfaceSharedStore.save(shared)
        let changedSession = previous?.startedAt != workout?.startedAt ||
            previous?.state != workout?.state ||
            previous?.currentStep != workout?.currentStep ||
            previous?.runningIntervalOrdinal != workout?.runningIntervalOrdinal ||
            previous?.runningInRecovery != workout?.runningInRecovery ||
            (previous == nil) != (workout == nil)
        let stale = lastRemoteWidgetReloadAt.map {
            Date().timeIntervalSince($0) >= 20
        } ?? true
        if changedSession || stale {
            WidgetCenter.shared.reloadTimelines(ofKind: "ATHLTHHomeWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ATHLTHLockScreenWidget")
            lastRemoteWidgetReloadAt = Date()
        }
    }

    static func publishSnapshot(
        health: HealthKitManager,
        session: AppSessionStore,
        goals: GoalStore,
        workout: WatchWorkoutLiveSnapshot?
    ) {
        guard session.signedIn else {
            clearAccountSurfaces()
            return
        }
        accountSurfacesEnabled = true
        let next = nextWorkout(
            in: session.activePlan,
            referenceDate: Date()
        )

        let activeWorkout: ATHLTHSurfaceWorkoutSnapshot?

        if let snapshot = workout,
           snapshot.state == .preparing ||
            snapshot.state == .running ||
            snapshot.state == .paused {
            activeWorkout = ATHLTHSurfaceWorkoutSnapshot(
                title: snapshot.kind.title,
                systemImage: snapshot.kind.systemImage,
                state: snapshot.state.rawValue,
                startedAt: snapshot.startedAt,
                elapsedTime: snapshot.elapsedTime,
                distanceMeters: snapshot.distanceMeters,
                heartRate: snapshot.heartRate,
                updatedAt: snapshot.capturedAt,
                currentStep: snapshot.runningStepTitle ?? snapshot.strengthExerciseName,
                nextStep: snapshot.runningNextStepTitle ?? snapshot.strengthNextExerciseName,
                runningIntervalOrdinal: snapshot.runningIntervalOrdinal,
                runningIntervalTotal: snapshot.runningIntervalTotal,
                runningInRecovery: snapshot.runningInRecovery,
                runningStepRemainingSeconds: snapshot.runningStepRemainingSeconds,
                strengthRestEndsAt: snapshot.strengthRestEndsAt,
                strengthSetIndex: snapshot.strengthSetIndex,
                strengthSetCount: snapshot.strengthSetCount
            )
        } else if let remoteWorkout,
                  Date().timeIntervalSince(remoteWorkout.updatedAt) < 35 {
            activeWorkout = remoteWorkout
        } else {
            activeWorkout = nil
        }

        let goal = goals.primaryGoal

        let surfaceSnapshot = ATHLTHSurfaceSnapshot(
            recoveryScore: health.recovery.score,
            recoveryState: health.recovery.state.title,
            nextWorkoutTitle: next?.session.title,
            nextWorkoutDate: next?.date,
            primaryGoalTitle: goal?.title,
            primaryGoalProgress: goal.map {
                ATHLTHGoalProgressPolicy.progress(
                    for: $0,
                    profile: ATHLTHTrainingProfile.load(userID: session.profile.userID),
                    latestBodyWeightKilograms: health.personalDetails.weightKilograms
                )
            },
            activeWorkout: activeWorkout,
            updatedAt: Date()
        )

        let previous =
            ATHLTHSurfaceSharedStore.load()

        let workoutTransition =
            previous.activeWorkout?.state != surfaceSnapshot.activeWorkout?.state ||
            previous.activeWorkout?.currentStep != surfaceSnapshot.activeWorkout?.currentStep ||
            previous.activeWorkout?.runningIntervalOrdinal != surfaceSnapshot.activeWorkout?.runningIntervalOrdinal ||
            previous.activeWorkout?.runningInRecovery != surfaceSnapshot.activeWorkout?.runningInRecovery ||
            (previous.activeWorkout == nil) != (surfaceSnapshot.activeWorkout == nil)

        let surfaceChanged =
            previous.recoveryScore !=
                surfaceSnapshot.recoveryScore ||
            previous.recoveryState !=
                surfaceSnapshot.recoveryState ||
            previous.nextWorkoutTitle !=
                surfaceSnapshot.nextWorkoutTitle ||
            previous.nextWorkoutDate !=
                surfaceSnapshot.nextWorkoutDate ||
            previous.primaryGoalTitle !=
                surfaceSnapshot.primaryGoalTitle ||
            previous.primaryGoalProgress !=
                surfaceSnapshot.primaryGoalProgress

        let shouldWriteLiveSnapshot =
            surfaceSnapshot.activeWorkout != nil &&
            (
                lastSnapshotWriteAt.map {
                    Date().timeIntervalSince($0) >= 3
                } ?? true
            )

        if surfaceChanged ||
            workoutTransition ||
            surfaceSnapshot.activeWorkout == nil ||
            shouldWriteLiveSnapshot {
            ATHLTHSurfaceSharedStore.save(surfaceSnapshot)
            lastSnapshotWriteAt = Date()
        }

        // Native timers continue ticking without new data, but distance,
        // heart rate and step labels need periodic WidgetKit refreshes.
        // Throttle to protect battery and avoid excessive reload requests.
        let refreshSeconds: TimeInterval =
            surfaceSnapshot.activeWorkout == nil ? 300 : 45
        let shouldReloadForAge =
            lastWidgetReloadAt.map {
                Date().timeIntervalSince($0) >= refreshSeconds
            } ?? true

        if surfaceChanged ||
            workoutTransition ||
            shouldReloadForAge {
            WidgetCenter.shared.reloadTimelines(
                ofKind: "ATHLTHHomeWidget"
            )
            WidgetCenter.shared.reloadTimelines(
                ofKind: "ATHLTHLockScreenWidget"
            )
            lastWidgetReloadAt = Date()
        }
    }

    static func syncLiveActivity(
        with snapshot: WatchWorkoutLiveSnapshot?
    ) {
        // WatchConnectivity completion can arrive while the tab observer
        // is suspended. Immediately clear the matching Home/Lock Screen
        // widget snapshot as well as ending its ActivityKit presentation.
        if let snapshot,
           ATHLTHLiveActivityStopPolicy.shouldDismiss(snapshot.state) {
            clearFinishedWidgetWorkout(matching: snapshot)
        }
        let generation = accountGeneration
        Task {
            guard generation == accountGeneration else { return }
            await ATHLTHLiveActivityController.shared.sync(
                with: accountSurfacesEnabled ? snapshot : nil
            )
            guard generation == accountGeneration else { return }
            let workoutIsActive = accountSurfacesEnabled &&
                snapshot.map {
                    $0.state == .preparing ||
                    $0.state == .running ||
                    $0.state == .paused
                } == true
            ATHLTHAliveController.workoutDidChange(
                isActive: workoutIsActive
            )
        }
    }

    private static func clearFinishedWidgetWorkout(
        matching finished: WatchWorkoutLiveSnapshot
    ) {
        var stored = ATHLTHSurfaceSharedStore.load()
        guard let active = stored.activeWorkout else { return }

        // Never clear a new iPhone or Watch workout just because a delayed
        // completion receipt from a previous Watch session arrived.
        let storedIdentity = ATHLTHLiveActivitySessionIdentity(
            systemImage: active.systemImage,
            startedAt: active.startedAt,
            fallbackTitle: active.title
        )
        let finishedIdentity = ATHLTHLiveActivitySessionIdentity(
            systemImage: finished.kind.systemImage,
            startedAt: finished.startedAt,
            fallbackTitle: finished.kind.title
        )
        guard storedIdentity.matches(finishedIdentity) else { return }

        stored.activeWorkout = nil
        stored.updatedAt = Date()
        ATHLTHSurfaceSharedStore.save(stored)
        lastSnapshotWriteAt = Date()
        WidgetCenter.shared.reloadTimelines(
            ofKind: "ATHLTHHomeWidget"
        )
        WidgetCenter.shared.reloadTimelines(
            ofKind: "ATHLTHLockScreenWidget"
        )
        lastWidgetReloadAt = Date()
    }

    /// WatchConnectivity can deliver a durable workout result independently
    /// of the mirrored HealthKit session and without an active tab view.
    /// Close the matching lock-screen activity at receipt time.
    static func completedWatchWorkoutDidArrive(
        _ result: WatchWorkoutResult
    ) {
        syncLiveActivity(
            with: WatchWorkoutLiveSnapshot(
                kind: result.kind,
                state: .completed,
                startedAt: result.startedAt,
                capturedAt: result.endedAt,
                elapsedTime: result.duration,
                heartRate: result.averageHeartRate ?? 0,
                activeCalories: result.activeCalories,
                distanceMeters: result.distanceMeters,
                averageHeartRate: result.averageHeartRate,
                maxHeartRate: result.maxHeartRate,
                routePointCount: result.routePointCount
            )
        )
    }

    static func clearAccountSurfaces() {
        remoteWorkout = nil
        lastRemoteWidgetReloadAt = nil
        accountSurfacesEnabled = false
        accountGeneration &+= 1
        ATHLTHSurfaceSharedStore.save(.empty)
        lastWidgetReloadAt = nil
        lastSnapshotWriteAt = nil
        WidgetCenter.shared.reloadTimelines(ofKind: "ATHLTHHomeWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "ATHLTHLockScreenWidget")
        syncLiveActivity(with: nil)
    }

    private static func nextWorkout(
        in plan: TrainingPlan?,
        referenceDate: Date
    ) -> (session: PlannedSession, date: Date)? {
        guard let plan else {
            return nil
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        var candidates: [(PlannedSession, Date)] = []

        for week in plan.weeks {
            for day in week.days {
                for session in day.sessions {
                    if let scheduledStart = session.scheduledStart {
                        if scheduledStart >= today {
                            candidates.append((session, scheduledStart))
                        }
                        continue
                    }

                    guard let planStart = plan.startDate else {
                        continue
                    }

                    let dayOffset =
                        max(week.weekNumber - 1, 0) * 7 +
                        max(day.dayIndex - 1, 0)

                    guard let date = calendar.date(
                        byAdding: .day,
                        value: dayOffset,
                        to: calendar.startOfDay(for: planStart)
                    ),
                    date >= today
                    else {
                        continue
                    }

                    candidates.append((session, date))
                }
            }
        }

        return candidates.min { lhs, rhs in
            lhs.1 < rhs.1
        }
    }

}

@MainActor
private final class ATHLTHLiveActivityController {
    static let shared = ATHLTHLiveActivityController()

    private var lastUpdateAt: Date?
    private var lastPhase: WatchWorkoutMirrorState?
    private var lastStrengthPresentationKey: String?
    private var lastSessionIdentity: ATHLTHLiveActivitySessionIdentity?
    /// Never re-create an already stopped Watch session from a delayed
    /// .running snapshot delivered after the terminal result.
    private var lastFinishedSessionIdentity: ATHLTHLiveActivitySessionIdentity?
    private var syncRevision: UInt64 = 0

    private init() {}

    func sync(
        with snapshot: WatchWorkoutLiveSnapshot?
    ) async {
        syncRevision &+= 1
        let revision = syncRevision

        guard let snapshot else {
            await endExistingActivities()
            // A newer workout may have started while ActivityKit was
            // dismissing the previous Live Activity. Do not erase the
            // newer session's controller state after this suspension.
            guard revision == syncRevision else { return }
            lastPhase = nil
            lastUpdateAt = nil
            lastStrengthPresentationKey = nil
            lastSessionIdentity = nil
            return
        }
        guard ActivityAuthorizationInfo()
            .areActivitiesEnabled
        else {
            return
        }

        let surfaceConfiguration =
            snapshot.liveSurfaceConfiguration ??
            ATHLTHLiveWorkoutPreferencesStore.load()

        if !surfaceConfiguration.dynamicIslandEnabled {
            await endExistingActivities()
            guard revision == syncRevision else { return }
            lastPhase = nil
            lastUpdateAt = nil
            lastStrengthPresentationKey = nil
            lastSessionIdentity = nil
            return
        }

        let identity = ATHLTHLiveActivitySessionIdentity(
            systemImage: snapshot.kind.systemImage,
            startedAt: snapshot.startedAt,
            fallbackTitle: snapshot.workoutDisplayTitle ??
                snapshot.kind.title
        )

        // The Watch's .ending means recording has stopped and only saving
        // remains. End the lock-screen timer immediately, not after the
        // completion import/summary pipeline finishes.
        let isTerminal = ATHLTHLiveActivityStopPolicy.shouldDismiss(
            snapshot.state
        )

        // A late Watch snapshot must never resurrect an already closed
        // ActivityKit session, even if it arrives after a completion receipt.
        if !isTerminal,
           !ATHLTHLiveActivityStopPolicy.mayStart(
                identity: identity,
                lastStopped: lastFinishedSessionIdentity
           ) {
            return
        }

        // A delayed completion from a previous session cannot finish the
        // Live Activity of a newly started workout.
        if isTerminal,
           let previous = lastSessionIdentity,
           !previous.matches(identity) {
            return
        }

        if lastSessionIdentity.map({ !$0.matches(identity) }) ?? true {
            lastUpdateAt = nil
            lastPhase = nil
            lastStrengthPresentationKey = nil
        }

        let storedLiveContext =
            ATHLTHLiveWorkoutContextStore.load()
        let snapshotLiveContext =
            snapshot.liveSurfaceContext

        let liveContext: ATHLTHLiveWorkoutContext
        if snapshotLiveContext?.challenge != nil ||
            snapshotLiveContext?.liveShare?.isSharing == true {
            liveContext = snapshotLiveContext ?? storedLiveContext
        } else {
            liveContext = storedLiveContext
        }

        let contentState =
            ATHLTHWorkoutActivityAttributes.ContentState(
                phase: snapshot.state.rawValue,
                workoutDisplayTitle: snapshot.workoutDisplayTitle,
                elapsedTime: snapshot.elapsedTime,
                distanceMeters: snapshot.distanceMeters,
                heartRate: snapshot.heartRate,
                currentPaceSecondsPerKilometer:
                    snapshot.currentPaceSecondsPerKilometer,
                routeProgressPercent:
                    snapshot.routeProgressPercent,
                routeRemainingMeters:
                    snapshot.routeRemainingMeters,
                routeDeviationMeters:
                    snapshot.routeDeviationMeters,
                routeDeviationThresholdMeters:
                    snapshot.routeDeviationThresholdMeters,
                runningStepTitle:
                    snapshot.runningStepTitle,
                runningStepIndex:
                    snapshot.runningStepIndex,
                runningStepCount:
                    snapshot.runningStepCount,
                runningIntervalOrdinal: snapshot.runningIntervalOrdinal,
                runningIntervalTotal: snapshot.runningIntervalTotal,
                runningInRecovery: snapshot.runningInRecovery,
                runningStepProgress:
                    snapshot.runningStepProgress,
                runningNextStepTitle:
                    snapshot.runningNextStepTitle,
                runningStepRemainingSeconds:
                    snapshot.runningStepRemainingSeconds,
                runningStepRemainingMeters:
                    snapshot.runningStepRemainingMeters,
                heartRateTargetZone:
                    snapshot.heartRateTargetZone,
                heartRateTargetMinimumBPM:
                    snapshot.heartRateTargetMinimumBPM,
                heartRateTargetMaximumBPM:
                    snapshot.heartRateTargetMaximumBPM,
                heartRateTargetStatus:
                    snapshot.heartRateTargetStatus,
                ghostRaceTitle:
                    snapshot.ghostRaceTitle,
                ghostDistanceDeltaMeters:
                    snapshot.ghostDistanceDeltaMeters,
                ghostTimeDeltaSeconds:
                    snapshot.ghostTimeDeltaSeconds,
                strengthExerciseName:
                    snapshot.strengthExerciseName,
                strengthSetIndex:
                    snapshot.strengthSetIndex,
                strengthSetCount:
                    snapshot.strengthSetCount,
                strengthReps:
                    snapshot.strengthReps,
                strengthWeightKilograms:
                    snapshot.strengthWeightKilograms,
                strengthRestEndsAt:
                    snapshot.strengthRestEndsAt,
                strengthNextExerciseName:
                    snapshot.strengthNextExerciseName,
                strengthTimedSetTargetSeconds:
                    snapshot.strengthTimedSetTargetSeconds,
                strengthTimedSetSecondsAtSnapshot:
                    snapshot.strengthTimedSetSecondsAtSnapshot,
                strengthTimedSetResumedAt:
                    snapshot.strengthTimedSetResumedAt,
                workoutKindRaw: snapshot.kind.rawValue,
                surfaceConfiguration:
                    surfaceConfiguration,
                liveContext:
                    liveContext,
                updatedAt: snapshot.capturedAt
            )

        let content = ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(90)
        )

        let phaseChanged =
            lastPhase != snapshot.state
        let strengthPresentationKey: String? = snapshot.kind == .strength
            ? [
                snapshot.strengthExerciseName ?? "",
                String(snapshot.strengthSetIndex ?? -1),
                String(snapshot.strengthSetCount ?? -1),
                String(snapshot.strengthRestEndsAt?.timeIntervalSince1970 ?? -1),
                snapshot.strengthNextExerciseName ?? "",
                String(snapshot.strengthTimedSetResumedAt?.timeIntervalSince1970 ?? -1)
              ].joined(separator: "|")
            : nil
        let strengthChanged =
            lastStrengthPresentationKey != strengthPresentationKey
        let updateIsDue =
            lastUpdateAt.map {
                Date().timeIntervalSince($0) >= 5
            } ?? true

        // Keep the five-second throttle for pulse/elapsed samples but never
        // delay a completed set, change of exercise or new rest countdown.
        if !phaseChanged &&
            !strengthChanged &&
            !updateIsDue &&
            !isTerminal {
            return
        }

        lastPhase = snapshot.state
        lastStrengthPresentationKey = strengthPresentationKey
        lastUpdateAt = Date()

        // Read each Activity only once. Filtering into a second array
        // aliases non-Sendable ActivityKit handles across suspension points
        // under Swift 6 strict concurrency.
        let activities =
            Activity<ATHLTHWorkoutActivityAttributes>.activities

        switch snapshot.state {
        case .preparing, .running, .paused:
            // Only the matching session can be reused. Close obsolete or
            // duplicate activities without retaining copied handle arrays.
            var reusedExistingActivity = false
            for activity in activities {
                let matches = identity.matches(
                    ATHLTHLiveActivitySessionIdentity(
                        systemImage: activity.attributes.systemImage,
                        startedAt: activity.attributes.startedAt,
                        fallbackTitle: activity.attributes.workoutTitle
                    )
                )

                if matches && !reusedExistingActivity {
                    reusedExistingActivity = true
                    await activity.update(content)
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                guard revision == syncRevision else { return }
            }

            lastSessionIdentity = identity
            if !reusedExistingActivity {
                let attributes = ATHLTHWorkoutActivityAttributes(
                    workoutTitle: identity.fallbackTitle,
                    systemImage: identity.systemImage,
                    startedAt: identity.startedAt
                )
                do {
                    _ = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                } catch {
                    // Live Activities are presentation only. Recording is
                    // still owned exclusively by the workout engine.
                }
            }

        case .ending, .completed, .failed:
            // Ending is authoritative for the lock-screen timer. Set the
            // stopped-session guard *before* any ActivityKit await; a new
            // snapshot may arrive while an older activity is being dismissed.
            lastFinishedSessionIdentity = identity

            // Match by Watch session identity, not its display title.
            // Delayed completion must not close a different active workout.
            for activity in activities {
                let matches = identity.matches(
                    ATHLTHLiveActivitySessionIdentity(
                        systemImage: activity.attributes.systemImage,
                        startedAt: activity.attributes.startedAt,
                        fallbackTitle: activity.attributes.workoutTitle
                    )
                )
                if matches {
                    await activity.end(
                        content,
                        dismissalPolicy: .immediate
                    )
                    guard revision == syncRevision else { return }
                }
            }
            lastSessionIdentity = nil
            lastPhase = nil
            lastUpdateAt = nil
        }
    }

    private func endExistingActivities() async {
        let activities =
            Activity<ATHLTHWorkoutActivityAttributes>
                .activities

        for activity in activities {
            await activity.end(
                nil,
                dismissalPolicy: .immediate
            )
        }
    }
}
