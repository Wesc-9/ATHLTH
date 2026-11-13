import Foundation
import SwiftUI
import Supabase

/// Read-only, owner-scoped active workout summary for a second signed-in device.
/// The recording and HealthKit ownership always remain on the source iPhone.
struct ATHLTHCrossDeviceWorkoutSnapshot: Codable, Equatable, Identifiable {
    let sessionID: UUID
    let kind: String
    let title: String
    let startedAt: Date
    let elapsedSeconds: TimeInterval
    let distanceMeters: Double?
    let currentStep: String?
    let nextStep: String?
    let completedSets: Int?
    let totalSets: Int?
    var paused: Bool? = nil
    // Read-only interval metadata. Same semantics as phone and Watch Live Activity.
    var runningIntervalOrdinal: Int? = nil
    var runningIntervalTotal: Int? = nil
    var runningInRecovery: Bool? = nil
    var runningStepRemainingSeconds: TimeInterval? = nil
    var capturedAt: Date? = nil

    // Optional live data; older cross-device snapshots remain decodable.
    // Only the source device can publish these values. iPad never measures.
    var sourceDevice: String? = nil
    var heartRateBPM: Double? = nil
    var activeCalories: Double? = nil
    var currentPaceSecondsPerKilometer: Double? = nil
    var targetPaceSecondsPerKilometer: Double? = nil
    var targetHeartRateZone: Int? = nil
    var runningStepProgress: Double? = nil
    var runningOverallProgress: Double? = nil
    var routeTitle: String? = nil
    var ghostRaceTitle: String? = nil

    var id: UUID { sessionID }
    var symbol: String {
        switch kind {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "strength": return "dumbbell.fill"
        case "hiit": return "figure.highintensity.intervaltraining"
        case "functional": return "figure.cross.training"
        case "rowing": return "figure.rower"
        case "stairClimbing": return "figure.stair.stepper"
        case "yoga": return "figure.yoga"
        default: return "figure.mixed.cardio"
        }
    }
}

private struct ATHLTHCrossDeviceWorkoutRow: Codable {
    let userID: UUID
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    let updatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case snapshot
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}

/// Polling deliberately shares only a compact spectator state; no second
/// HKWorkoutSession, no mirrored GPS track, no public/social presence.
/// Server-side RLS additionally enforces user_id = auth.uid().
@MainActor
final class ATHLTHCrossDeviceWorkoutStore: ObservableObject {
    @Published private(set) var remote: ATHLTHCrossDeviceWorkoutSnapshot?
    @Published private(set) var isExpanded = false

    private let client = SupabaseEnvironment.client
    private var lastPublishedID: UUID?
    private var mirroredStartedAt: Date?
    private var mirroredSessionID: UUID?
    private var lastRemoteExpiry: Date?
    private var hasLoadedRemote = false
    private var foregroundedSinceLastPoll = false
    private var suppressAutoOpenOnNextPoll = false

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
    }

    func didBackground() {
        foregroundedSinceLastPoll = false
        suppressAutoOpenOnNextPoll = true
        isExpanded = false
    }

    func didForeground() {
        foregroundedSinceLastPoll = true
    }

    func clearLocalState() {
        remote = nil
        lastPublishedID = nil
        mirroredStartedAt = nil
        mirroredSessionID = nil
        lastRemoteExpiry = nil
        hasLoadedRemote = false
        foregroundedSinceLastPoll = false
        suppressAutoOpenOnNextPoll = false
        isExpanded = false
        ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
    }

    func track(
        signedIn: Bool,
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore
    ) async {
        guard signedIn else {
            clearLocalState()
            return
        }
        hasLoadedRemote = false
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        while !Task.isCancelled {
            // Do not trust local profile IDs as authorization: every request
            // also requires the active Supabase session to match that ID.
            if client.auth.currentUser?.id == accountID {
                if isPad {
                    await readRemote(accountID: accountID)
                } else {
                    await publishLocal(
                        accountID: accountID, phone: phone,
                        strength: strength, mirroredWatch: mirroredWatch
                    )
                }
            } else {
                remote = nil
                ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
            }

            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                break
            }
        }
    }

    private func liveSnapshot(
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore
    ) -> ATHLTHCrossDeviceWorkoutSnapshot? {
        if let log = strength.activeWorkout {
            let exercise = strength.currentExerciseIndex
            let activeName = log.exercises.indices.contains(exercise)
                ? log.exercises[exercise].exercise.displayName
                : nil
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: log.id,
                kind: "strength",
                title: log.title,
                startedAt: log.startedAt,
                elapsedSeconds: max(0, Date().timeIntervalSince(log.startedAt)),
                distanceMeters: nil,
                currentStep: activeName,
                nextStep: nil,
                completedSets: log.totalCompletedSets,
                totalSets: log.exercises.reduce(0) { $0 + $1.sets.count },
                capturedAt: .now,
                sourceDevice: "iphone"
            )
        }
        if let run = phone.active {
            let index = run.structuredStepIndex ?? 0
            let steps = run.structuredRunningWorkout?.steps ?? []
            let interval = ATHLTHRunningIntervalPosition.resolve(
                steps: steps, currentIndex: index
            )
            let current = steps.indices.contains(index) ? steps[index] : nil
            let remaining = current?.durationSeconds.map { duration in
                max(0, duration - max(0,
                    run.elapsed(at: Date()) -
                        (run.structuredStepStartElapsedTime ?? 0)
                ))
            }
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: run.id,
                kind: run.walking ? "walking" : "running",
                title: run.title,
                startedAt: run.start,
                elapsedSeconds: max(0, run.elapsed(at: Date())),
                distanceMeters: run.distanceMeters.isFinite
                    ? max(0, run.distanceMeters) : nil,
                currentStep: steps.indices.contains(index)
                    ? steps[index].title : nil,
                nextStep: steps.indices.contains(index + 1)
                    ? steps[index + 1].title : nil,
                completedSets: nil,
                totalSets: nil,
                paused: run.resumedAt == nil,
                runningIntervalOrdinal: interval?.ordinal,
                runningIntervalTotal: interval?.total,
                runningInRecovery: interval?.isRecovery,
                runningStepRemainingSeconds: current?.measure == .time
                    ? remaining : nil,
                capturedAt: .now,
                sourceDevice: "iphone",
                currentPaceSecondsPerKilometer:
                    run.currentPaceSecondsPerKilometer,
                targetPaceSecondsPerKilometer:
                    current?.targetPaceMinSecondsPerKilometer,
                targetHeartRateZone: current?.targetHeartRateZone,
                runningStepProgress: {
                    guard let target = current?.durationSeconds,
                          target > 0, let remaining else { return nil }
                    return min(1, max(0, 1 - remaining / target))
                }(),
                routeTitle: run.plannedRouteTitle,
                ghostRaceTitle: run.ghostRaceTitle
            )
        }
        if let watch = mirroredWatch.snapshot,
           watch.state == .preparing ||
           watch.state == .running ||
           watch.state == .paused {
            // Watch remains the only HealthKit sensor/recording source. The
            // iPhone only relays a private summary to the signed-in iPad.
            let startedAt = watch.startedAt ??
                watch.capturedAt.addingTimeInterval(-watch.confirmedActiveDuration)
            if mirroredStartedAt != startedAt || mirroredSessionID == nil {
                mirroredStartedAt = startedAt
                mirroredSessionID = UUID()
            }
            guard let sessionID = mirroredSessionID else { return nil }
            return ATHLTHCrossDeviceWorkoutSnapshot(
                sessionID: sessionID,
                kind: watch.kind.rawValue,
                title: watch.workoutDisplayTitle ?? watch.kind.title,
                startedAt: startedAt,
                elapsedSeconds: watch.confirmedActiveDuration,
                distanceMeters: watch.kind.supportsDistanceMetric &&
                    watch.distanceMeters.isFinite
                    ? max(0, watch.distanceMeters) : nil,
                currentStep: watch.runningStepTitle ?? watch.strengthExerciseName,
                nextStep: watch.runningNextStepTitle ?? watch.strengthNextExerciseName,
                completedSets: nil,
                totalSets: nil,
                paused: watch.state == .paused,
                runningIntervalOrdinal: watch.runningIntervalOrdinal,
                runningIntervalTotal: watch.runningIntervalTotal,
                runningInRecovery: watch.runningInRecovery,
                runningStepRemainingSeconds: watch.runningStepRemainingSeconds,
                capturedAt: watch.capturedAt,
                sourceDevice: "watch",
                heartRateBPM: watch.heartRate > 0
                    ? Double(watch.heartRate) : nil,
                activeCalories: watch.activeCalories > 0
                    ? Double(watch.activeCalories) : nil,
                currentPaceSecondsPerKilometer:
                    watch.currentPaceSecondsPerKilometer,
                targetPaceSecondsPerKilometer:
                    watch.runningStepTargetPaceSecondsPerKilometer,
                targetHeartRateZone: watch.runningStepTargetHeartRateZone,
                runningStepProgress: watch.runningStepProgress,
                runningOverallProgress: watch.runningOverallProgress,
                routeTitle: watch.routeTitle,
                ghostRaceTitle: watch.ghostRaceTitle
            )
        }
        return nil
    }

    private func publishLocal(
        accountID: UUID,
        phone: IPhoneWorkoutStore,
        strength: StrengthWorkoutStore,
        mirroredWatch: WorkoutMirroringStore
    ) async {
        let active = liveSnapshot(
            phone: phone, strength: strength, mirroredWatch: mirroredWatch
        )
        if let active {
            let now = Date()
            let row = ATHLTHCrossDeviceWorkoutRow(
                userID: accountID,
                snapshot: active,
                updatedAt: now,
                expiresAt: now.addingTimeInterval(30)
            )
            do {
                try await client.from("private_active_workout_status")
                    .upsert(row, onConflict: "user_id")
                    .execute()
                lastPublishedID = active.id
            } catch {
                // Never interrupt a locally recorded workout for spectator sync.
            }
        } else if lastPublishedID != nil {
            do {
                try await client.from("private_active_workout_status")
                    .delete()
                    .eq("user_id", value: accountID)
                    .execute()
                lastPublishedID = nil
            } catch {
                // TTL clears an abandoned session when the network returns.
            }
        }
    }

    private func readRemote(accountID: UUID) async {
        do {
            let rows: [ATHLTHCrossDeviceWorkoutRow] = try await client
                .from("private_active_workout_status")
                .select()
                .eq("user_id", value: accountID)
                .limit(1)
                .execute()
                .value
            let row = rows.first
            let next = row.flatMap {
                $0.expiresAt > Date() ? $0.snapshot : nil
            }
            let previous = remote?.id
            if previous != next?.id {
                if foregroundedSinceLastPoll &&
                   !suppressAutoOpenOnNextPoll && next != nil {
                    isExpanded = true
                } else {
                    isExpanded = false
                }
            }
            remote = next
            suppressAutoOpenOnNextPoll = false
            lastRemoteExpiry = next == nil ? nil : row?.expiresAt
            hasLoadedRemote = true
            ATHLTHSurfaceCoordinator.setRemoteWorkout(next.map {
                ATHLTHSurfaceWorkoutSnapshot(
                    title: $0.title,
                    systemImage: $0.symbol,
                    state: $0.paused == true ? "paused" : (
                        $0.kind == "strength" ? "remote_strength" : "running"
                    ),
                    startedAt: $0.startedAt,
                    elapsedTime: $0.elapsedSeconds,
                    distanceMeters: $0.distanceMeters ?? 0,
                    heartRate: 0,
                    updatedAt: row?.updatedAt ?? .now,
                    currentStep: $0.currentStep,
                    nextStep: $0.nextStep,
                    runningIntervalOrdinal: $0.runningIntervalOrdinal,
                    runningIntervalTotal: $0.runningIntervalTotal,
                    runningInRecovery: $0.runningInRecovery,
                    runningStepRemainingSeconds: $0.runningStepRemainingSeconds
                )
            })
        } catch {
            // An offline spectator must not appear permanently live.
            if lastRemoteExpiry.map({ $0 <= Date() }) ?? true {
                remote = nil
                lastRemoteExpiry = nil
                ATHLTHSurfaceCoordinator.setRemoteWorkout(nil)
            }
            hasLoadedRemote = true
        }
    }
}
