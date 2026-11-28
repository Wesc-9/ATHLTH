import Foundation

/// The editor may only enable a trigger when the selected workout can
/// actually provide the target or type of measurement the rule requires.
/// A global template has no selected workout, so its choices remain
/// configurable and are checked against the active workout at delivery.
struct ATHLTHCoachTriggerAvailability: Equatable {
    var isWorkoutSpecific: Bool
    var supportsDistance: Bool
    var supportsOutdoorElevation: Bool
    var hasTimeGoal: Bool
    var hasDistanceGoal: Bool
    var hasPaceGoal: Bool
    var hasZoneGoal: Bool
    var hasStructuredSteps: Bool
    /// Concrete sport when the editor is opened for a known workout.
    /// Nil for global templates and legacy generic quick-start entries.
    var workoutActivity: ATHLTHCoachActivityFilter? = nil

    static let global = Self(
        isWorkoutSpecific: false,
        supportsDistance: true, supportsOutdoorElevation: true,
        hasTimeGoal: true, hasDistanceGoal: true,
        hasPaceGoal: true, hasZoneGoal: true, hasStructuredSteps: true
    )

    static func session(
        hasRoute: Bool, structured: Bool
    ) -> Self {
        // Backward-compatible fallback for older quick-start entry points:
        // never invent a target from the mere presence of the workout editor.
        Self(
            isWorkoutSpecific: true,
            supportsDistance: true, supportsOutdoorElevation: hasRoute,
            hasTimeGoal: false, hasDistanceGoal: hasRoute,
            hasPaceGoal: false, hasZoneGoal: false,
            hasStructuredSteps: structured
        )
    }

    static func running(
        steps: [WatchRunningWorkoutStep],
        hasRoute: Bool,
        isOutdoor: Bool
    ) -> Self {
        let allDistance = !steps.isEmpty && steps.allSatisfy {
            $0.measure == .distance &&
                ($0.distanceMeters ?? 0) > 0
        }
        let durationKnown = !steps.isEmpty && steps.allSatisfy { step in
            switch step.measure {
            case .time:
                return (step.durationSeconds ?? 0) > 0
            case .distance:
                return (step.distanceMeters ?? 0) > 0 &&
                    (step.targetPaceMinSecondsPerKilometer ??
                     step.targetPaceMaxSecondsPerKilometer ?? 0) > 0
            case .open:
                return false
            }
        }
        return Self(
            isWorkoutSpecific: true,
            supportsDistance: true,
            supportsOutdoorElevation: isOutdoor,
            hasTimeGoal: durationKnown,
            hasDistanceGoal: hasRoute || allDistance,
            hasPaceGoal: steps.contains {
                $0.targetPaceMinSecondsPerKilometer != nil ||
                $0.targetPaceMaxSecondsPerKilometer != nil
            },
            hasZoneGoal: steps.contains {
                $0.targetHeartRateZone != nil
            },
            hasStructuredSteps: !steps.isEmpty,
            workoutActivity: .running
        )
    }

    func supports(
        _ trigger: ATHLTHAudioCoachRule.Trigger,
        for activity: ATHLTHCoachActivityFilter
    ) -> Bool {
        guard supports(trigger) else { return false }

        // A planned running workout cannot silently become a strength,
        // cycling or swimming trigger. Intervals are a running sub-mode
        // only when an actual structured recipe is present.
        if let workoutActivity, isWorkoutSpecific,
           activity != .all && activity != workoutActivity {
            let isRunningInterval = activity == .intervals &&
                workoutActivity == .running && hasStructuredSteps
            guard isRunningInterval else { return false }
        }

        if activity == .intervals && !hasStructuredSteps &&
            isWorkoutSpecific { return false }

        // An all-sports selection inside a concrete workout must still obey
        // the actual workout's sport restrictions.
        let effectiveActivity = activity == .all ? (workoutActivity ?? .all) : activity
        if trigger.isStrengthEvent {
            return effectiveActivity == .strength || effectiveActivity == .all
        }
        if trigger.isCadenceCondition {
            return [.all, .running, .walking, .intervals].contains(effectiveActivity)
        }
        if trigger.isGhostCondition {
            return [.all, .running, .walking, .intervals].contains(effectiveActivity) && supportsDistance
        }
        switch effectiveActivity {
        case .strength, .functional:
            switch trigger {
            case .distance, .nearFinishDistance, .workoutDistanceProgress, .elevationGain,
                 .uphillDetected, .slowerThanPreviousWorkout,
                 .paceFasterOverall, .paceFasterLastKilometer,
                 .paceFasterThanTarget, .paceSlowerThanTarget, .paceBackInTarget, .personalRecordConfirmed:
                return false
            default: return true
            }
        case .swimming:
            switch trigger {
            case .elevationGain, .uphillDetected,
                 .slowerThanPreviousWorkout,
                 .paceFasterOverall, .paceFasterLastKilometer,
                 .paceFasterThanTarget, .paceSlowerThanTarget, .paceBackInTarget:
                return false
            default: return true
            }
        case .cycling:
            return trigger != .slowerThanPreviousWorkout &&
                trigger != .paceFasterThanTarget &&
                trigger != .paceSlowerThanTarget && trigger != .paceBackInTarget &&
                trigger != .personalRecordConfirmed
        case .walking:
            return trigger != .slowerThanPreviousWorkout &&
                trigger != .personalRecordConfirmed
        case .all, .running, .intervals:
            return true
        }
    }

    func supports(_ trigger: ATHLTHAudioCoachRule.Trigger) -> Bool {
        guard isWorkoutSpecific else { return true }
        switch trigger {
        case .distance, .nearFinishDistance:
            return supportsDistance &&
                (trigger == .distance || hasDistanceGoal)
        case .nearFinishTime, .workoutTimeProgress: return hasTimeGoal
        case .workoutDistanceProgress: return supportsDistance && hasDistanceGoal
        case .stepTimeProgress, .lastStrengthSet, .strengthSetCompleted, .lastExerciseSet, .strengthRestEnding, .strengthProgressConfirmed: return hasStructuredSteps
        case .ghostAhead, .ghostBehind: return supportsDistance
        case .elevationGain, .uphillDetected: return supportsOutdoorElevation
        case .paceFasterOverall, .paceFasterLastKilometer:
            return supportsDistance
        case .paceFasterThanTarget, .paceSlowerThanTarget, .paceBackInTarget:
            return hasPaceGoal
        case .plannedZoneBelow, .plannedZoneOutside, .plannedZoneBackInTarget:
            return hasZoneGoal
        case .slowerThanPreviousWorkout:
            return supportsDistance
        case .stepStart, .stepEnd, .beforeNextStep,
             .effortStart, .effortEnd, .recoveryStart, .recoveryEnd,
             .activeRecoveryStart, .activeRecoveryEnd,
             .warmupStart, .warmupEnd, .mainStart, .mainEnd,
              .cooldownStart, .cooldownEnd, .beforeMain, .beforeCooldown, .beforeEffort:
            return hasStructuredSteps
        default: return true
        }
    }
}
