import Foundation
import SwiftUI

/// One source of truth for how a completed workout is presented.
///
/// This deliberately does not replace the Watch / iPhone recording engines:
/// they own active recording, HealthKit writes, sync and deduplication. The
/// experience engine only resolves which place/route UI is appropriate after
/// looking at the workout's recorded environment and actual GPS evidence.
enum ATHLTHWorkoutLocationMode: Equatable {
    case indoorCheckIn
    case recordedGPSMap
    case missingGPS
    case noLocation
}

enum ATHLTHWorkoutExperienceEngine {
    static func locationMode(
        activity: WorkoutActivity,
        isIndoor: Bool?,
        hasRecordedGPS: Bool
    ) -> ATHLTHWorkoutLocationMode {
        // Indoor always wins: do not turn treadmill/indoor movement into a GPS
        // route if Apple Health contains incidental position samples.
        if isIndoor == true {
            return .indoorCheckIn
        }

        // A real saved GPS route or location, whatever the sport, is map data
        // only when the workout is NOT explicitly indoor.
        if hasRecordedGPS {
            return .recordedGPSMap
        }

        if isIndoor == nil {
            switch activity {
            case .strength, .hiit, .rowing, .elliptical,
                 .stairClimbing, .yoga, .coreTraining:
                return .indoorCheckIn
            default: break
            }
        }

        // An outdoor GPS sport should explain when no route was recorded.
        // Never synthesize a map, route geometry or location from distance.
        switch activity {
        case .running, .walking, .cycling, .hiking, .swimming:
            return .missingGPS
        default:
            return .noLocation
        }
    }

    static func locationMode(
        workout: SocialPublishableWorkout,
        hasRecordedGPS: Bool
    ) -> ATHLTHWorkoutLocationMode {
        locationMode(
            activity: workout.activity,
            isIndoor: workout.isIndoor,
            hasRecordedGPS: hasRecordedGPS
        )
    }
}

/// Shared place-or-map section for run, strength and the historical detail
/// route. Underlying recording technology remains sport-specific.
/// A recorded track is supplied by each caller; this view NEVER requests GPS.
struct ATHLTHWorkoutLocationSection<RecordedMap: View>: View {
    let workout: SocialPublishableWorkout
    let hasRecordedGPS: Bool
    @ViewBuilder let recordedMap: () -> RecordedMap

    private var locationMode: ATHLTHWorkoutLocationMode {
        ATHLTHWorkoutExperienceEngine.locationMode(
            workout: workout,
            hasRecordedGPS: hasRecordedGPS
        )
    }

    var body: some View {
        Group {
            switch locationMode {
            case .indoorCheckIn:
                WorkoutPlaceCheckInSection(workoutID: workout.id)
            case .recordedGPSMap:
                recordedMap()
            case .missingGPS:
                ATHLTHPlanSurface {
                    HStack(spacing: 13) {
                        Image(systemName: "map")
                            .font(.title3)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            .frame(width: 45, height: 45)
                            .background(
                                ATHLTHPlanDesign.warmSurface,
                                in: RoundedRectangle(cornerRadius: 14)
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "GPS route unavailable",
                                norwegian: "GPS-rute mangler"
                            ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                            Text(ATHLTHLocalization.choose(
                                english: "No recorded route was saved for this outdoor workout.",
                                norwegian: "Det finnes ingen lagret GPS-rute for denne utendørsøkten."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    }
                }
            case .noLocation:
                EmptyView()
            }
        }
    }
}
