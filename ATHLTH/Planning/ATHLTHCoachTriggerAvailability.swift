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
            hasStructuredSteps: !steps.isEmpty
        )
    }

    func supports(_ trigger: ATHLTHAudioCoachRule.Trigger) -> Bool {
        guard isWorkoutSpecific else { return true }
        switch trigger {
        case .distance, .nearFinishDistance:
            return supportsDistance &&
                (trigger == .distance || hasDistanceGoal)
        case .nearFinishTime: return hasTimeGoal
        case .elevationGain, .uphillDetected: return supportsOutdoorElevation
        case .paceFasterOverall, .paceFasterLastKilometer:
            return supportsDistance
        case .paceFasterThanTarget, .paceSlowerThanTarget:
            return hasPaceGoal
        case .plannedZoneBelow, .plannedZoneOutside:
            return hasZoneGoal
        case .slowerThanPreviousWorkout:
            return supportsDistance
        case .stepStart, .stepEnd, .beforeNextStep,
             .effortStart, .effortEnd, .recoveryStart, .recoveryEnd,
             .activeRecoveryStart, .activeRecoveryEnd,
             .warmupStart, .warmupEnd, .mainStart, .mainEnd,
             .cooldownStart, .cooldownEnd, .beforeMain, .beforeCooldown:
            return hasStructuredSteps
        default: return true
        }
    }
}
