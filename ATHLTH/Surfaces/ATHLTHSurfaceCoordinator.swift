import ActivityKit
import Foundation
import WidgetKit

@MainActor
enum ATHLTHSurfaceCoordinator {
    private static var lastWidgetReloadAt: Date?
    private static var lastSnapshotWriteAt: Date?
    private static var accountSurfacesEnabled = false
    private static var accountGeneration: UInt64 = 0

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
            snapshot.state == .paused ||
            snapshot.state == .ending {
            activeWorkout = ATHLTHSurfaceWorkoutSnapshot(
                title: snapshot.kind.title,
                systemImage: snapshot.kind.systemImage,
                state: snapshot.state.rawValue,
                startedAt: snapshot.startedAt,
                elapsedTime: snapshot.elapsedTime,
                distanceMeters: snapshot.distanceMeters,
                heartRate: snapshot.heartRate,
                updatedAt: snapshot.capturedAt
            )
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
            primaryGoalProgress: goal?.progress,
            activeWorkout: activeWorkout,
            updatedAt: Date()
        )

        let previous =
            ATHLTHSurfaceSharedStore.load()

        let workoutTransition =
            previous.activeWorkout?.state !=
                surfaceSnapshot.activeWorkout?.state ||
            (previous.activeWorkout == nil) !=
                (surfaceSnapshot.activeWorkout == nil)

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

        let shouldReloadForAge =
            lastWidgetReloadAt.map {
                Date().timeIntervalSince($0) >= 300
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
                    $0.state == .paused ||
                    $0.state == .ending
                } == true
            ATHLTHAliveController.workoutDidChange(
                isActive: workoutIsActive
            )
        }
    }

    static func clearAccountSurfaces() {
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
    private var lastSessionIdentity: ATHLTHLiveActivitySessionIdentity?
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
            lastSessionIdentity = nil
            return
        }

        let identity = ATHLTHLiveActivitySessionIdentity(
            systemImage: snapshot.kind.systemImage,
            startedAt: snapshot.startedAt,
            fallbackTitle: snapshot.workoutDisplayTitle ??
                snapshot.kind.title
        )

        // A delayed completion from the previous session cannot finish the
        // Live Activity of a newly started workout.
        if (snapshot.state == .completed || snapshot.state == .failed),
           let previous = lastSessionIdentity,
           !previous.matches(identity) {
            return
        }

        if lastSessionIdentity.map({ !$0.matches(identity) }) ?? true {
            lastUpdateAt = nil
            lastPhase = nil
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
        let updateIsDue =
            lastUpdateAt.map {
                Date().timeIntervalSince($0) >= 5
            } ?? true

        if !phaseChanged &&
            !updateIsDue &&
            snapshot.state != .completed &&
            snapshot.state != .failed {
            return
        }

        lastPhase = snapshot.state
        lastUpdateAt = Date()

        // Read each Activity only once. Filtering into a second array
        // aliases non-Sendable ActivityKit handles across suspension points
        // under Swift 6 strict concurrency.
        let activities =
            Activity<ATHLTHWorkoutActivityAttributes>.activities

        switch snapshot.state {
        case .preparing, .running, .paused, .ending:
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

        case .completed, .failed:
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
                        dismissalPolicy: .after(
                            Date().addingTimeInterval(60)
                        )
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
