import ActivityKit
import Foundation
import WidgetKit

@MainActor
enum ATHLTHSurfaceCoordinator {
    private static var lastWidgetReloadAt: Date?
    private static var lastSnapshotWriteAt: Date?

    static func publishSnapshot(
        health: HealthKitManager,
        session: AppSessionStore,
        goals: GoalStore,
        workout: WatchWorkoutLiveSnapshot?
    ) {
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
        Task {
            await ATHLTHLiveActivityController.shared.sync(
                with: snapshot
            )
        }
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

    private init() {}

    func sync(
        with snapshot: WatchWorkoutLiveSnapshot?
    ) async {
        guard ActivityAuthorizationInfo()
            .areActivitiesEnabled
        else {
            return
        }

        guard let snapshot else {
            return
        }

        let contentState =
            ATHLTHWorkoutActivityAttributes.ContentState(
                phase: snapshot.state.rawValue,
                elapsedTime: snapshot.elapsedTime,
                distanceMeters: snapshot.distanceMeters,
                heartRate: snapshot.heartRate,
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

        switch snapshot.state {
        case .preparing, .running, .paused, .ending:
            if let activity =
                Activity<ATHLTHWorkoutActivityAttributes>
                    .activities.first {
                await activity.update(content)
            } else {
                let attributes =
                    ATHLTHWorkoutActivityAttributes(
                        workoutTitle: snapshot.kind.title,
                        systemImage: snapshot.kind.systemImage,
                        startedAt: snapshot.startedAt
                    )

                do {
                    _ = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                } catch {
                    // Live Activities are a presentation surface only.
                    // A request failure must never affect the workout.
                }
            }

        case .completed, .failed:
            let activities =
                Activity<ATHLTHWorkoutActivityAttributes>
                    .activities

            for activity in activities {
                await activity.end(
                    content,
                    dismissalPolicy: .after(
                        Date().addingTimeInterval(60)
                    )
                )
            }
        }
    }
}
