import SwiftUI

enum ProfileRecordGroup:
    String,
    CaseIterable,
    Identifiable
{
    case running
    case strength
    case appleHealth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running",
                norwegian: "Løping"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .appleHealth:
            return ATHLTHLocalization.choose(
                english: "Apple Health",
                norwegian: "Apple Health"
            )
        }
    }

    var icon: String {
        switch self {
        case .running:
            return "figure.run"
        case .strength:
            return "dumbbell.fill"
        case .appleHealth:
            return "heart.fill"
        }
    }
}

enum ProfileFeaturedRecordKind:
    String,
    CaseIterable,
    Identifiable,
    Hashable
{
    case fastest400M
    case fastest800M
    case fastest1K
    case fastestMile
    case fastest3K
    case fastest5K
    case fastest10K
    case fastest15K
    case fastest10Mile
    case fastestHalfMarathon
    case fastestMarathon
    case longestRun

    // Exercise-specific strength records shown in the profile picker.
    case strengthBenchPress
    case strengthBackSquat
    case strengthDeadlift
    case strengthShoulderPress
    case strengthPullUps
    case strengthDips
    case strengthChinUps
    case strengthFrontSquat

    case strengthHeaviestSet
    case strengthEstimatedOneRM
    case strengthWorkoutVolume
    case strengthBestRepPR
    case longestStrengthWorkout

    case longestRide
    case longestWalkOrHike
    case longestSwim
    case longestWorkout
    case longestHIITWorkout
    case longestRowingWorkout
    case longestEllipticalWorkout
    case longestStairClimbingWorkout
    case longestYogaWorkout
    case longestCoreWorkout
    case mostActiveCalories
    case mostStepsInWorkout

    static let showcaseLimit = 4
    static let storageKey =
        "athlth.profile.featuredPersonalRecords.v1"

    static let defaultSelection:
        [ProfileFeaturedRecordKind] = [
            .fastest5K,
            .fastest10K,
            .fastestHalfMarathon,
            .longestRun
        ]

    var id: String { rawValue }

    var group: ProfileRecordGroup {
        switch self {
        case .fastest400M,
             .fastest800M,
             .fastest1K,
             .fastestMile,
             .fastest3K,
             .fastest5K,
             .fastest10K,
             .fastest15K,
             .fastest10Mile,
             .fastestHalfMarathon,
             .fastestMarathon,
             .longestRun:
            return .running

        case .strengthBenchPress,
             .strengthBackSquat,
             .strengthDeadlift,
             .strengthShoulderPress,
             .strengthPullUps,
             .strengthDips,
             .strengthChinUps,
             .strengthFrontSquat,
             .strengthHeaviestSet,
             .strengthEstimatedOneRM,
             .strengthWorkoutVolume,
             .strengthBestRepPR,
             .longestStrengthWorkout:
            return .strength

        case .longestRide,
             .longestWalkOrHike,
             .longestSwim,
             .longestWorkout,
             .longestHIITWorkout,
             .longestRowingWorkout,
             .longestEllipticalWorkout,
             .longestStairClimbingWorkout,
             .longestYogaWorkout,
             .longestCoreWorkout,
             .mostActiveCalories,
             .mostStepsInWorkout:
            return .appleHealth
        }
    }

    var healthKind: HealthPersonalRecordKind? {
        switch self {
        case .fastest400M:
            return .fastest400M
        case .fastest800M:
            return .fastest800M
        case .fastest1K:
            return .fastest1K
        case .fastestMile:
            return .fastestMile
        case .fastest3K:
            return .fastest3K
        case .fastest5K:
            return .fastest5K
        case .fastest10K:
            return .fastest10K
        case .fastest15K:
            return .fastest15K
        case .fastest10Mile:
            return .fastest10Mile
        case .fastestHalfMarathon:
            return .fastestHalfMarathon
        case .fastestMarathon:
            return .fastestMarathon
        case .longestRun:
            return .longestRun
        case .longestStrengthWorkout:
            return .longestStrengthWorkout
        case .longestRide:
            return .longestRide
        case .longestWalkOrHike:
            return .longestWalkOrHike
        case .longestSwim:
            return .longestSwim
        case .longestWorkout:
            return .longestWorkout
        case .longestHIITWorkout:
            return .longestHIITWorkout
        case .longestRowingWorkout:
            return .longestRowingWorkout
        case .longestEllipticalWorkout:
            return .longestEllipticalWorkout
        case .longestStairClimbingWorkout:
            return .longestStairClimbingWorkout
        case .longestYogaWorkout:
            return .longestYogaWorkout
        case .longestCoreWorkout:
            return .longestCoreWorkout
        case .mostActiveCalories:
            return .mostActiveCalories
        case .mostStepsInWorkout:
            return .mostStepsInWorkout
        case .strengthBenchPress,
             .strengthBackSquat,
             .strengthDeadlift,
             .strengthShoulderPress,
             .strengthPullUps,
             .strengthDips,
             .strengthChinUps,
             .strengthFrontSquat,
             .strengthHeaviestSet,
             .strengthEstimatedOneRM,
             .strengthWorkoutVolume,
             .strengthBestRepPR:
            return nil
        }
    }

    var title: String {
        switch self {
        case .fastest400M:
            return ATHLTHLocalization.choose(
                english: "Fastest 400 m",
                norwegian: "Raskeste 400 m"
            )
        case .fastest800M:
            return ATHLTHLocalization.choose(
                english: "Fastest 800 m",
                norwegian: "Raskeste 800 m"
            )
        case .fastest1K:
            return ATHLTHLocalization.choose(
                english: "Fastest 1K",
                norwegian: "Raskeste 1 km"
            )
        case .fastestMile:
            return ATHLTHLocalization.choose(
                english: "Fastest mile",
                norwegian: "Raskeste mile"
            )
        case .fastest3K:
            return ATHLTHLocalization.choose(
                english: "Fastest 3K",
                norwegian: "Raskeste 3 km"
            )
        case .fastest5K:
            return ATHLTHLocalization.choose(
                english: "Fastest 5K",
                norwegian: "Raskeste 5 km"
            )
        case .fastest10K:
            return ATHLTHLocalization.choose(
                english: "Fastest 10K",
                norwegian: "Raskeste 10 km"
            )
        case .fastest15K:
            return ATHLTHLocalization.choose(
                english: "Fastest 15K",
                norwegian: "Raskeste 15 km"
            )
        case .fastest10Mile:
            return ATHLTHLocalization.choose(
                english: "Fastest 10 miles",
                norwegian: "Raskeste 10 miles"
            )
        case .fastestHalfMarathon:
            return ATHLTHLocalization.choose(
                english: "Half marathon",
                norwegian: "Halvmaraton"
            )
        case .fastestMarathon:
            return ATHLTHLocalization.choose(
                english: "Marathon",
                norwegian: "Maraton"
            )
        case .longestRun:
            return ATHLTHLocalization.choose(
                english: "Longest run",
                norwegian: "Lengste løpetur"
            )
        case .strengthBenchPress:
            return ATHLTHLocalization.choose(
                english: "Bench press",
                norwegian: "Benkpress"
            )
        case .strengthBackSquat:
            return ATHLTHLocalization.choose(
                english: "Back squat",
                norwegian: "Knebøy"
            )
        case .strengthDeadlift:
            return ATHLTHLocalization.choose(
                english: "Deadlift",
                norwegian: "Markløft"
            )
        case .strengthShoulderPress:
            return ATHLTHLocalization.choose(
                english: "Shoulder press",
                norwegian: "Skulderpress"
            )
        case .strengthPullUps:
            return "Pullups"
        case .strengthDips:
            return "Dips"
        case .strengthChinUps:
            return "Chins"
        case .strengthFrontSquat:
            return ATHLTHLocalization.choose(
                english: "Front squat",
                norwegian: "Frontbøy"
            )
        case .strengthHeaviestSet:
            return ATHLTHLocalization.choose(
                english: "Heaviest set",
                norwegian: "Tyngste sett"
            )
        case .strengthEstimatedOneRM:
            return ATHLTHLocalization.choose(
                english: "Estimated 1RM",
                norwegian: "Estimert 1RM"
            )
        case .strengthWorkoutVolume:
            return ATHLTHLocalization.choose(
                english: "Best workout volume",
                norwegian: "Høyeste øktvolum"
            )
        case .strengthBestRepPR:
            return ATHLTHLocalization.choose(
                english: "Best rep PR",
                norwegian: "Beste repetisjons-PR"
            )
        case .longestStrengthWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest strength workout",
                norwegian: "Lengste styrkeøkt"
            )
        case .longestRide:
            return ATHLTHLocalization.choose(
                english: "Longest ride",
                norwegian: "Lengste sykkeltur"
            )
        case .longestWalkOrHike:
            return ATHLTHLocalization.choose(
                english: "Longest walk / hike",
                norwegian: "Lengste gåtur / fjelltur"
            )
        case .longestSwim:
            return ATHLTHLocalization.choose(
                english: "Longest swim",
                norwegian: "Lengste svømmetur"
            )
        case .longestWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest workout",
                norwegian: "Lengste økt"
            )
        case .longestHIITWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest HIIT workout",
                norwegian: "Lengste HIIT-økt"
            )
        case .longestRowingWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest rowing workout",
                norwegian: "Lengste roøkt"
            )
        case .longestEllipticalWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest elliptical workout",
                norwegian: "Lengste ellipseøkt"
            )
        case .longestStairClimbingWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest stair workout",
                norwegian: "Lengste trappeøkt"
            )
        case .longestYogaWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest yoga workout",
                norwegian: "Lengste yogaøkt"
            )
        case .longestCoreWorkout:
            return ATHLTHLocalization.choose(
                english: "Longest core workout",
                norwegian: "Lengste kjernestyrkeøkt"
            )
        case .mostActiveCalories:
            return ATHLTHLocalization.choose(
                english: "Most active calories",
                norwegian: "Flest aktive kalorier"
            )
        case .mostStepsInWorkout:
            return ATHLTHLocalization.choose(
                english: "Most steps in a workout",
                norwegian: "Flest steg i én økt"
            )
        }
    }

    var shortTitle: String {
        switch self {
        case .fastest400M:
            return "400 m"
        case .fastest800M:
            return "800 m"
        case .fastest1K:
            return "1 km"
        case .fastestMile:
            return "Mile"
        case .fastest3K:
            return "3 km"
        case .fastest5K:
            return "5 km"
        case .fastest10K:
            return "10 km"
        case .fastest15K:
            return "15 km"
        case .fastest10Mile:
            return "10 mi"
        case .fastestHalfMarathon:
            return ATHLTHLocalization.choose(
                english: "Half",
                norwegian: "Halv"
            )
        case .fastestMarathon:
            return ATHLTHLocalization.choose(
                english: "Marathon",
                norwegian: "Maraton"
            )
        case .longestRun:
            return ATHLTHLocalization.choose(
                english: "Run",
                norwegian: "Løp"
            )
        case .strengthBenchPress:
            return ATHLTHLocalization.choose(
                english: "Bench",
                norwegian: "Benkpress"
            )
        case .strengthBackSquat:
            return ATHLTHLocalization.choose(
                english: "Squat",
                norwegian: "Knebøy"
            )
        case .strengthDeadlift:
            return ATHLTHLocalization.choose(
                english: "Deadlift",
                norwegian: "Markløft"
            )
        case .strengthShoulderPress:
            return ATHLTHLocalization.choose(
                english: "Shoulder",
                norwegian: "Skulder"
            )
        case .strengthPullUps:
            return "Pullups"
        case .strengthDips:
            return "Dips"
        case .strengthChinUps:
            return "Chins"
        case .strengthFrontSquat:
            return ATHLTHLocalization.choose(
                english: "Front squat",
                norwegian: "Frontbøy"
            )
        case .strengthHeaviestSet:
            return ATHLTHLocalization.choose(
                english: "Heaviest",
                norwegian: "Tyngst"
            )
        case .strengthEstimatedOneRM:
            return "1RM"
        case .strengthWorkoutVolume:
            return ATHLTHLocalization.choose(
                english: "Volume",
                norwegian: "Volum"
            )
        case .strengthBestRepPR:
            return "Rep-PR"
        case .longestStrengthWorkout:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        case .longestRide:
            return ATHLTHLocalization.choose(
                english: "Ride",
                norwegian: "Sykkel"
            )
        case .longestWalkOrHike:
            return ATHLTHLocalization.choose(
                english: "Walk / hike",
                norwegian: "Tur"
            )
        case .longestSwim:
            return ATHLTHLocalization.choose(
                english: "Swim",
                norwegian: "Svøm"
            )
        case .longestWorkout:
            return ATHLTHLocalization.choose(
                english: "Workout",
                norwegian: "Økt"
            )
        case .longestHIITWorkout:
            return "HIIT"
        case .longestRowingWorkout:
            return ATHLTHLocalization.choose(
                english: "Rowing",
                norwegian: "Roing"
            )
        case .longestEllipticalWorkout:
            return ATHLTHLocalization.choose(
                english: "Elliptical",
                norwegian: "Ellipse"
            )
        case .longestStairClimbingWorkout:
            return ATHLTHLocalization.choose(
                english: "Stairs",
                norwegian: "Trapp"
            )
        case .longestYogaWorkout:
            return "Yoga"
        case .longestCoreWorkout:
            return ATHLTHLocalization.choose(
                english: "Core",
                norwegian: "Kjerne"
            )
        case .mostActiveCalories:
            return ATHLTHLocalization.choose(
                english: "Calories",
                norwegian: "Kalorier"
            )
        case .mostStepsInWorkout:
            return ATHLTHLocalization.choose(
                english: "Steps",
                norwegian: "Steg"
            )
        }
    }

    var icon: String {
        switch self {
        case .fastest400M:
            return "4.circle.fill"
        case .fastest800M:
            return "8.circle.fill"
        case .fastest1K:
            return "1.circle.fill"
        case .fastestMile:
            return "m.circle.fill"
        case .fastest3K:
            return "3.circle.fill"
        case .fastest5K:
            return "5.circle.fill"
        case .fastest10K:
            return "10.circle.fill"
        case .fastest15K:
            return "15.circle.fill"
        case .fastest10Mile:
            return "figure.run.circle.fill"
        case .fastestHalfMarathon:
            return "figure.run"
        case .fastestMarathon:
            return "flag.checkered"
        case .longestRun:
            return "point.topleft.down.to.point.bottomright.curvepath"
        case .strengthBenchPress,
             .strengthBackSquat,
             .strengthDeadlift,
             .strengthShoulderPress,
             .strengthFrontSquat,
             .strengthHeaviestSet,
             .longestStrengthWorkout:
            return "dumbbell.fill"
        case .strengthPullUps:
            return "figure.climbing"
        case .strengthDips:
            return "figure.strengthtraining.functional"
        case .strengthChinUps:
            return "figure.strengthtraining.traditional"
        case .strengthEstimatedOneRM:
            return "bolt.fill"
        case .strengthWorkoutVolume:
            return "chart.bar.fill"
        case .strengthBestRepPR:
            return "repeat"
        case .longestRide:
            return "figure.outdoor.cycle"
        case .longestWalkOrHike:
            return "figure.hiking"
        case .longestSwim:
            return "figure.pool.swim"
        case .longestWorkout:
            return "clock.fill"
        case .longestHIITWorkout:
            return "figure.highintensity.intervaltraining"
        case .longestRowingWorkout:
            return "figure.rower"
        case .longestEllipticalWorkout:
            return "figure.elliptical"
        case .longestStairClimbingWorkout:
            return "figure.stair.stepper"
        case .longestYogaWorkout:
            return "figure.yoga"
        case .longestCoreWorkout:
            return "figure.core.training"
        case .mostActiveCalories:
            return "flame.fill"
        case .mostStepsInWorkout:
            return "shoeprints.fill"
        }
    }

    var tint: Color {
        switch self {
        case .fastest400M:
            return .mint
        case .fastest800M:
            return .teal
        case .fastest1K:
            return .blue
        case .fastestMile:
            return .cyan
        case .fastest3K:
            return .indigo
        case .fastest5K:
            return .green
        case .fastest10K:
            return .orange
        case .fastest15K:
            return .pink
        case .fastest10Mile:
            return .purple
        case .fastestHalfMarathon:
            return .pink
        case .fastestMarathon:
            return .indigo
        case .longestRun:
            return .purple
        case .strengthBenchPress:
            return .blue
        case .strengthBackSquat:
            return .mint
        case .strengthDeadlift:
            return .indigo
        case .strengthShoulderPress:
            return .yellow
        case .strengthPullUps:
            return .pink
        case .strengthDips:
            return .cyan
        case .strengthChinUps:
            return .orange
        case .strengthFrontSquat:
            return .purple
        case .strengthHeaviestSet:
            return .blue
        case .strengthEstimatedOneRM:
            return .green
        case .strengthWorkoutVolume:
            return .indigo
        case .strengthBestRepPR:
            return .orange
        case .longestStrengthWorkout:
            return .mint
        case .longestRide:
            return .green
        case .longestWalkOrHike:
            return .brown
        case .longestSwim:
            return .cyan
        case .longestWorkout:
            return .indigo
        case .longestHIITWorkout:
            return .red
        case .longestRowingWorkout:
            return .teal
        case .longestEllipticalWorkout:
            return .purple
        case .longestStairClimbingWorkout:
            return .orange
        case .longestYogaWorkout:
            return .mint
        case .longestCoreWorkout:
            return .blue
        case .mostActiveCalories:
            return .orange
        case .mostStepsInWorkout:
            return .green
        }
    }

    func displayValue(
        healthRecords: [HealthPersonalRecord],
        stats: ProfilePerformanceStats?,
        strengthRecords: [StrengthPersonalRecord] = [],
        strengthRepRecords: [StrengthRepPersonalRecord] = []
    ) -> String {
        if let healthKind,
           let record = healthRecords.first(
                where: {
                    $0.kind == healthKind
                }
           ) {
            return record.formattedValue
        }

        switch self {
        case .fastest1K:
            return stats?
                .fastestOneKilometer?
                .formattedTime ?? "—"
        case .fastest5K:
            return stats?
                .fastestFiveKilometers?
                .formattedTime ?? "—"
        case .fastestMarathon:
            return stats?
                .fastestMarathon?
                .formattedTime ?? "—"
        case .longestRun:
            guard let meters =
                    stats?.longestRunMeters,
                  meters > 0
            else {
                return "—"
            }

            let kilometers =
                meters / 1_000

            return kilometers >= 100
                ? String(
                    format: "%.1f km",
                    kilometers
                )
                : String(
                    format: "%.2f km",
                    kilometers
                )

        case .strengthBenchPress,
             .strengthBackSquat,
             .strengthDeadlift,
             .strengthShoulderPress,
             .strengthPullUps,
             .strengthDips,
             .strengthChinUps,
             .strengthFrontSquat:
            return strengthExerciseDisplayValue(
                strengthRecords:
                    strengthRecords,
                strengthRepRecords:
                    strengthRepRecords
            )

        case .strengthHeaviestSet:
            return strengthRecords
                .filter {
                    $0.kind == .heaviestSet
                }
                .max {
                    $0.score < $1.score
                }?
                .value ?? "—"

        case .strengthEstimatedOneRM:
            return strengthRecords
                .filter {
                    $0.kind ==
                        .estimatedOneRepMax
                }
                .max {
                    $0.score < $1.score
                }?
                .value ?? "—"

        case .strengthWorkoutVolume:
            return strengthRecords
                .filter {
                    $0.kind == .workoutVolume
                }
                .max {
                    $0.score < $1.score
                }?
                .value ?? "—"

        case .strengthBestRepPR:
            return strengthRepRecords
                .max {
                    if $0.weightKilograms ==
                        $1.weightKilograms {
                        return $0.reps < $1.reps
                    }
                    return $0.weightKilograms <
                        $1.weightKilograms
                }?
                .value ?? "—"

        case .fastest400M,
             .fastest800M,
             .fastestMile,
             .fastest3K,
             .fastest10K,
             .fastest15K,
             .fastest10Mile,
             .fastestHalfMarathon,
             .longestStrengthWorkout,
             .longestRide,
             .longestWalkOrHike,
             .longestSwim,
             .longestWorkout,
             .longestHIITWorkout,
             .longestRowingWorkout,
             .longestEllipticalWorkout,
             .longestStairClimbingWorkout,
             .longestYogaWorkout,
             .longestCoreWorkout,
             .mostActiveCalories,
             .mostStepsInWorkout:
            return "—"
        }
    }

    private func strengthExerciseDisplayValue(
        strengthRecords: [StrengthPersonalRecord],
        strengthRepRecords: [StrengthRepPersonalRecord]
    ) -> String {
        func normalized(_ value: String) -> String {
            value
                .folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                )
                .lowercased()
        }

        func matches(_ value: String) -> Bool {
            let value = normalized(value)

            switch self {
            case .strengthBenchPress:
                return value.contains("bench press") ||
                    value.contains("benkpress")
            case .strengthBackSquat:
                let isSquat =
                    value.contains("back squat") ||
                    value.contains("knebøy") ||
                    value.contains("kneboy") ||
                    value == "squat"
                return isSquat &&
                    !value.contains("front")
            case .strengthDeadlift:
                return value.contains("deadlift") ||
                    value.contains("markløft") ||
                    value.contains("markloft")
            case .strengthShoulderPress:
                return value.contains("shoulder press") ||
                    value.contains("overhead press") ||
                    value.contains("military press") ||
                    value.contains("skulderpress")
            case .strengthPullUps:
                return value.contains("pullup") ||
                    value.contains("pull-up") ||
                    value.contains("pull up")
            case .strengthDips:
                return value == "dip" ||
                    value.contains("dips")
            case .strengthChinUps:
                return value.contains("chinup") ||
                    value.contains("chin-up") ||
                    value.contains("chin up") ||
                    value == "chins"
            case .strengthFrontSquat:
                return value.contains("front squat") ||
                    value.contains("frontbøy") ||
                    value.contains("frontboy")
            default:
                return false
            }
        }

        let isRepFirst =
            self == .strengthPullUps ||
            self == .strengthDips ||
            self == .strengthChinUps

        let matchingRepRecords =
            strengthRepRecords.filter { record in
                matches(record.exerciseName)
            }

        let matchingStrengthRecords =
            strengthRecords.filter { record in
                record.kind == .heaviestSet &&
                    matches(record.title)
            }

        if isRepFirst,
           let repRecord = matchingRepRecords.max(
               by: { lhs, rhs in
                   if lhs.reps == rhs.reps {
                       return lhs.weightKilograms <
                           rhs.weightKilograms
                   }
                   return lhs.reps < rhs.reps
               }
           ) {
            if repRecord.weightKilograms > 0 {
                return repRecord.value
            }

            return "\(repRecord.reps) reps"
        }

        if let record = matchingStrengthRecords.max(
            by: { lhs, rhs in
                lhs.score < rhs.score
            }
        ) {
            return record.value
        }

        if let repRecord = matchingRepRecords.max(
            by: { lhs, rhs in
                lhs.weightKilograms < rhs.weightKilograms
            }
        ) {
            return repRecord.value
        }

        return "—"
    }

    static func decodedSelection(
        from raw: String
    ) -> [ProfileFeaturedRecordKind] {
        if raw == "-" {
            return []
        }

        let decoded =
            raw
                .split(separator: ",")
                .compactMap {
                    ProfileFeaturedRecordKind(
                        rawValue: String($0)
                    )
                }

        var seen:
            Set<ProfileFeaturedRecordKind> = []

        return Array(
            decoded
                .filter {
                    seen.insert($0)
                        .inserted
                }
                .prefix(showcaseLimit)
        )
    }

    static func encodedSelection(
        _ selection:
            [ProfileFeaturedRecordKind]
    ) -> String {
        guard !selection.isEmpty else {
            return "-"
        }

        return selection
            .prefix(showcaseLimit)
            .map(\.rawValue)
            .joined(separator: ",")
    }
}


struct ProfilePerformanceSection: View {
    let stats: ProfilePerformanceStats?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Performance highlights",
                            norwegian: "Prestasjonshøydepunkter"
                        )
                    )
                    .font(.title3.weight(.bold))

                    Label(
                        ATHLTHLocalization.choose(
                            english: "Verified from Apple Health",
                            norwegian: "Verifisert fra Apple Health"
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.accent)
                }

                Spacer()

                NavigationLink {
                    PerformanceStatsView(stats: stats)
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            ATHLTHLocalization.choose(
                                english: "View all",
                                norwegian: "Se alle"
                            )
                        )
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                }
                .disabled(stats == nil)
            }

            if isLoading && stats == nil {
                HStack {
                    ProgressView()
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Reading your performance…",
                            norwegian: "Leser prestasjonene dine…"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 18)
            } else if let stats {
                HStack(spacing: 8) {
                    compactMetric(
                        icon: "figure.run.circle.fill",
                        title: ATHLTHLocalization.choose(
                            english: "Fastest 5K",
                            norwegian: "Raskeste 5 km"
                        ),
                        value:
                            stats.fastestFiveKilometers?
                                .formattedTime ?? "—",
                        tint: .green
                    )

                    compactMetric(
                        icon:
                            "point.topleft.down.to.point.bottomright.curvepath",
                        title: ATHLTHLocalization.choose(
                            english: "Longest run",
                            norwegian: "Lengste løpetur"
                        ),
                        value: formatDistance(
                            stats.longestRunMeters
                        ),
                        tint: .orange
                    )

                    compactMetric(
                        icon: "checkmark.circle.fill",
                        title: ATHLTHLocalization.choose(
                            english: "Workouts",
                            norwegian: "Økter"
                        ),
                        value: stats.totalWorkoutCount.formatted(),
                        tint: ATHLTHTheme.accent
                    )
                }
                .padding(.top, 12)
            } else {
                Text(
                    ATHLTHLocalization.choose(
                        english: "Connect Apple Health to build verified performance highlights.",
                        norwegian: "Koble til Apple Health for å bygge verifiserte prestasjonshøydepunkter."
                    )
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .padding(.vertical, 12)
            }
        }
        .padding(18)
        .background(
            Color.white.opacity(0.82),
            in: RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border.opacity(0.72),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(0.035),
            radius: 16,
            x: 0,
            y: 8
        )
    }

    private func compactMetric(
        icon: String,
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.10),
                    in: Circle()
                )

            Text(value)
                .font(
                    .subheadline
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .minimumScaleFactor(0.64)
                .lineLimit(1)

            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            minHeight: 92,
            alignment: .leading
        )
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.07),
                    Color.white.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                tint.opacity(0.09),
                lineWidth: 1
            )
        }
    }
}

private enum PerformanceVolumePeriod:
    String,
    CaseIterable,
    Identifiable {
    case week
    case month
    case year
    case total

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week:
            return ATHLTHLocalization.choose(
                english: "Week",
                norwegian: "Uke"
            )
        case .month:
            return ATHLTHLocalization.choose(
                english: "Month",
                norwegian: "Måned"
            )
        case .year:
            return ATHLTHLocalization.choose(
                english: "Year",
                norwegian: "År"
            )
        case .total:
            return ATHLTHLocalization.choose(
                english: "Total",
                norwegian: "Totalt"
            )
        }
    }

    var subtitle: String {
        switch self {
        case .week:
            return ATHLTHLocalization.choose(
                english: "This week",
                norwegian: "Denne uken"
            )
        case .month:
            return ATHLTHLocalization.choose(
                english: "This month",
                norwegian: "Denne måneden"
            )
        case .year:
            return ATHLTHLocalization.choose(
                english: "This year",
                norwegian: "Dette året"
            )
        case .total:
            return ATHLTHLocalization.choose(
                english: "All recorded training",
                norwegian: "All registrert trening"
            )
        }
    }
}

private struct PerformanceVolumePoint:
    Identifiable {
    let id: String
    let label: String
    let value: Double
}

struct PerformanceStatsView: View {
    let stats: ProfilePerformanceStats?
    var healthRecords: [HealthPersonalRecord] = []

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @State private var fetchedHealthRecords: [HealthPersonalRecord] = []
    @State private var performanceWorkoutHistory:
        [WorkoutSummary] = []
    @State private var trainingVolumePeriod:
        PerformanceVolumePeriod = .year
    @AppStorage(ProfileFeaturedRecordKind.storageKey)
    private var featuredRecordSelectionRaw = ""

    private let gridColumns = [
        GridItem(
            .adaptive(minimum: 168, maximum: 320),
            spacing: 12,
            alignment: .top
        )
    ]

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 16) {
                    editorialHero {
                        withAnimation(
                            .easeInOut(duration: 0.35)
                        ) {
                            reader.scrollTo(
                                "performance-volume",
                                anchor: .center
                            )
                        }
                    }

                    editorialFeaturedRecords
                    editorialSummaryStrip
                    editorialRunningPRCard
                    editorialStrengthPRCard

                    editorialTrainingVolumeCard
                        .id("performance-volume")

                    editorialTrainingMixCard
                    editorialMilestonesCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 120)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        )
        .navigationTitle(
            text(
                "Performance Statistics",
                "Prestasjonsstatistikk"
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard health.hasRequestedAuthorization
            else {
                return
            }

            if performanceWorkoutHistory
                .isEmpty {
                performanceWorkoutHistory =
                    (
                        try? await health
                            .performanceWorkoutHistory()
                    ) ??
                    health.workouts
            }

            if healthRecords.isEmpty &&
                fetchedHealthRecords
                    .isEmpty {
                fetchedHealthRecords =
                    (
                        try? await health
                            .personalRecords()
                    ) ?? []
            }
        }
    }

    private var resolvedPerformanceWorkouts:
        [WorkoutSummary] {
        performanceWorkoutHistory
            .isEmpty
            ? health.workouts
            : performanceWorkoutHistory
    }

    private func editorialHero(
        onOpenTrend: @escaping () -> Void
    ) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Image("GoalRunning")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    stops: [
                        .init(
                            color:
                                Color.black
                                    .opacity(0.76),
                            location: 0
                        ),
                        .init(
                            color:
                                Color.black
                                    .opacity(0.48),
                            location: 0.48
                        ),
                        .init(
                            color:
                                Color.black
                                    .opacity(0.05),
                            location: 1
                        )
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Path { path in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    path.move(
                        to: CGPoint(
                            x: 0,
                            y: h * 0.91
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w,
                            y: h * 0.55
                        ),
                        control1: CGPoint(
                            x: w * 0.35,
                            y: h * 0.96
                        ),
                        control2: CGPoint(
                            x: w * 0.70,
                            y: h * 0.60
                        )
                    )
                }
                .stroke(
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.72),
                    style:
                        StrokeStyle(
                            lineWidth: 1.4,
                            lineCap: .round
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text("ATHLTH")
                        .font(
                            .system(
                                size: 12,
                                weight: .black
                            )
                        )
                        .tracking(4.2)
                        .foregroundStyle(
                            .white.opacity(0.88)
                        )

                    Text(
                        text(
                            "Performance Passport",
                            "Prestasjonspass"
                        )
                    )
                    .font(
                        .system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                    Text(
                        text(
                            "Your personal performance, built from your training history.",
                            "Dine personlige prestasjoner, bygget fra treningshistorikken din."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        .white.opacity(0.88)
                    )
                    .lineLimit(2)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .frame(
                        maxWidth:
                            proxy.size.width * 0.63,
                        alignment: .leading
                    )

                    Button(action: onOpenTrend) {
                        HStack(spacing: 8) {
                            Text(
                                text(
                                    "View your progress",
                                    "Se din utvikling"
                                )
                            )

                            Image(
                                systemName:
                                    "chevron.right"
                            )
                        }
                        .font(
                            .subheadline
                                .weight(.semibold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .padding(
                            .horizontal,
                            16
                        )
                        .frame(height: 42)
                        .background(
                            Color.white
                                .opacity(0.92),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(20)

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        text(
                            "BETTER HABITS",
                            "BEDRE VANER"
                        )
                    )

                    Text(
                        text(
                            "GREATER POSSIBILITIES",
                            "STØRRE MULIGHETER"
                        )
                    )
                }
                .font(
                    .system(
                        size: 8,
                        weight: .bold
                    )
                )
                .tracking(1.5)
                .foregroundStyle(
                    .white.opacity(0.80)
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
                .padding(18)
            }
        }
        .frame(height: 245)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.12),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.12),
            radius: 18,
            y: 8
        )
    }

    private var editorialFeaturedRecords:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Text(
                    text(
                        "Featured records",
                        "Utvalgte rekorder"
                    )
                )
                .font(
                    .title3.weight(.bold)
                )

                Spacer()

                NavigationLink {
                    ProfileRecordShowcasePickerView(
                        stats: stats,
                        healthRecords:
                            resolvedHealthRecords
                    )
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            text(
                                "Edit",
                                "Rediger"
                            )
                        )

                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }
            }
            .padding(.horizontal, 4)

            LazyVGrid(
                columns: [
                    GridItem(
                        .flexible(),
                        spacing: 10
                    ),
                    GridItem(
                        .flexible(),
                        spacing: 10
                    )
                ],
                spacing: 10
            ) {
                ForEach(
                    0..<ProfileFeaturedRecordKind
                        .showcaseLimit,
                    id: \.self
                ) { index in
                    if featuredRecordKinds.indices
                        .contains(index) {
                        editorialFeaturedTile(
                            featuredRecordKinds[
                                index
                            ],
                            index: index
                        )
                    } else {
                        editorialEmptyFeaturedTile(
                            index: index
                        )
                    }
                }
            }
        }
    }

    private func editorialFeaturedTile(
        _ kind: ProfileFeaturedRecordKind,
        index: Int
    ) -> some View {
        let record =
            kind.healthKind.flatMap {
                record($0)
            }

        return ZStack(
            alignment: .topLeading
        ) {
            Image(
                editorialFeaturedAsset(
                    index
                )
            )
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 94)
            .clipped()
            .opacity(0.34)

            LinearGradient(
                colors: [
                    editorialFeaturedTint(
                        index
                    )
                    .opacity(0.84),
                    Color.white.opacity(0.76)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack(
                    alignment: .top
                ) {
                    Image(
                        systemName:
                            kind.icon
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        kind.tint
                    )
                    .frame(
                        width: 32,
                        height: 32
                    )
                    .background(
                        Color.white
                            .opacity(0.84),
                        in: Circle()
                    )

                    Spacer()

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                            .opacity(0.75)
                    )
                }

                Text(kind.title)
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(2)

                HStack(
                    alignment:
                        .firstTextBaseline
                ) {
                    Text(
                        kind.displayValue(
                            healthRecords:
                                resolvedHealthRecords,
                            stats: stats,
                            strengthRecords:
                                strengthWorkout
                                    .personalRecords,
                            strengthRepRecords:
                                strengthWorkout
                                    .repPersonalRecords
                        )
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                    Spacer()
                }

                Text(
                    record.map {
                        editorialRecordDetail(
                            $0
                        )
                    } ??
                    kind.shortTitle
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
            }
            .padding(10)
        }
        .frame(height: 94)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.58),
                lineWidth: 0.8
            )
        }
    }

    private func editorialEmptyFeaturedTile(
        index: Int
    ) -> some View {
        NavigationLink {
            ProfileRecordShowcasePickerView(
                stats: stats,
                healthRecords:
                    resolvedHealthRecords
            )
        } label: {
            ZStack {
                LinearGradient(
                    colors: [
                        editorialFeaturedTint(
                            index
                        )
                        .opacity(0.62),
                        Color.white.opacity(
                            0.88
                        )
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )

                VStack(spacing: 5) {
                    Image(
                        systemName:
                            "plus.circle.fill"
                    )
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )

                    Text(
                        text(
                            "Choose record",
                            "Velg rekord"
                        )
                    )
                    .font(
                        .caption
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                }
            }
            .frame(height: 94)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func editorialFeaturedAsset(
        _ index: Int
    ) -> String {
        [
            "GoalMountain",
            "GoalRunning",
            "GoalProgress",
            "GoalWalking"
        ][
            min(
                max(index, 0),
                3
            )
        ]
    }

    private func editorialFeaturedTint(
        _ index: Int
    ) -> Color {
        [
            Color.green,
            Color.orange,
            Color.indigo,
            Color.red
        ][
            min(
                max(index, 0),
                3
            )
        ]
        .opacity(0.11)
    }

    private func editorialRecordDetail(
        _ record: HealthPersonalRecord
    ) -> String {
        if let distance =
                record.kind
                    .targetDistanceMeters,
           distance > 0 {
            let pace =
                record.value /
                (distance / 1_000)

            return formatPace(pace)
        }

        return formatDate(record.date)
    }

    private var editorialSummaryStrip:
        some View {
        HStack(spacing: 0) {
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    text(
                        "Summary",
                        "Oppsummering"
                    )
                )
                .font(
                    .subheadline
                        .weight(.bold)
                )

                Text(
                    text(
                        "Your training in numbers.",
                        "Din trening i tall."
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            editorialSummaryDivider

            editorialSummaryMetric(
                icon:
                    "figure.run",
                value:
                    stats?
                        .totalWorkoutCount
                        .formatted() ??
                    "—",
                label:
                    text(
                        "Workouts",
                        "Økter"
                    )
            )

            editorialSummaryDivider

            editorialSummaryMetric(
                icon:
                    "point.topleft.down.to.point.bottomright.curvepath",
                value:
                    formatDistance(
                        stats?
                            .totalRunningDistanceMeters
                    ),
                label:
                    text(
                        "Total distance",
                        "Total distanse"
                    )
            )

            editorialSummaryDivider

            editorialSummaryMetric(
                icon: "clock",
                value:
                    stats.map {
                        formatLongDuration(
                            $0.totalTrainingDuration
                        )
                    } ?? "—",
                label:
                    text(
                        "Total duration",
                        "Total varighet"
                    )
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            Color.white.opacity(0.84),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border
                    .opacity(0.62),
                lineWidth: 0.8
            )
        }
    }

    private var editorialSummaryDivider:
        some View {
        Rectangle()
            .fill(
                ATHLTHTheme
                    .divider
                    .opacity(0.72)
            )
            .frame(
                width: 0.7,
                height: 52
            )
            .padding(.horizontal, 5)
    }

    private func editorialSummaryMetric(
        icon: String,
        value: String,
        label: String
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )

            Text(value)
                .font(
                    .system(
                        size: 14,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(label)
                .font(
                    .system(
                        size: 8.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(
            ATHLTHTheme.primaryText
        )
        .frame(
            maxWidth: .infinity
        )
    }

    private var editorialRunningPRCard:
        some View {
        VStack(spacing: 0) {
            ZStack(
                alignment: .bottomLeading
            ) {
                Image("GoalSprint")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 138)
                    .clipped()
                    .accessibilityHidden(
                        true
                    )

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black
                            .opacity(0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(
                    alignment: .bottom,
                    spacing: 10
                ) {
                    Image(
                        systemName:
                            "figure.run"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .background(
                        Color.black
                            .opacity(0.32),
                        in: Circle()
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            text(
                                "Running PRs",
                                "Løpe-PRer"
                            )
                        )
                        .font(
                            .headline
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            .white
                        )

                        Text(
                            text(
                                "Verified records and ATHLTH training milestones.",
                                "Verifiserte rekorder og ATHLTH-milepæler."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.84
                                )
                        )
                    }

                    Spacer()

                    sourceBadge(
                        title:
                            text(
                                "HEALTH + ATHLTH",
                                "HEALTH + ATHLTH"
                            ),
                        icon:
                            "checkmark.seal.fill"
                    )
                }
                .padding(14)
            }
            .frame(height: 138)

            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Text(
                        text(
                            "Personal bests",
                            "Personlige rekorder"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.bold)
                    )

                    Spacer()

                    NavigationLink {
                        PerformanceRecordCollectionView(
                            title:
                                text(
                                    "Running records",
                                    "Løperekorder"
                                ),
                            subtitle:
                                text(
                                    "Verified records and ATHLTH-calculated milestones from your full running history.",
                                    "Verifiserte rekorder og ATHLTH-beregnede milepæler fra hele løpehistorikken din."
                                ),
                            imageName:
                                "GoalSprint",
                            items:
                                runningDisplayItems,
                            sources:
                                runningDisplayItems
                                    .indices
                                    .map(
                                        runningMetricSource
                                    )
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                text(
                                    "View all",
                                    "Se alle"
                                )
                            )
                            Image(
                                systemName:
                                    "chevron.right"
                            )
                        }
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(
                            .flexible(),
                            spacing: 8
                        ),
                        GridItem(
                            .flexible(),
                            spacing: 8
                        )
                    ],
                    spacing: 8
                ) {
                    ForEach(
                        Array(
                            runningSummaryItems
                                .enumerated()
                        ),
                        id: \.offset
                    ) {
                        index,
                        item in

                        lightPRMetric(
                            item,
                            source:
                                runningSummaryMetricSource(
                                    index
                                )
                        )
                    }
                }
            }
            .padding(14)
        }
        .background(
            Color.white.opacity(
                0.94
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border
                    .opacity(0.62),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.055),
            radius: 14,
            y: 6
        )
    }

    private var runningSummaryItems:
        [PerformanceMetricItem] {
        Array(
            runningItems
                .prefix(4)
        ) + [
            longestRunItem,
            bestWeeklyRunningDistanceItem
        ]
    }

    private var runningDisplayItems:
        [PerformanceMetricItem] {
        Array(
            runningItems
                .prefix(6)
        ) + [
            longestRunItem,
            bestWeeklyRunningDistanceItem,
            mostRunsInWeekItem,
            bestRunningMonthItem
        ]
    }

    private func runningSummaryMetricSource(
        _ index: Int
    ) -> String {
        index < 5
            ? text(
                "Verified",
                "Verifisert"
            )
            : "ATHLTH"
    }

    private func runningMetricSource(
        _ index: Int
    ) -> String {
        index < 7
            ? text(
                "Verified",
                "Verifisert"
            )
            : "ATHLTH"
    }


    private var editorialStrengthPRCard:
        some View {
        VStack(spacing: 0) {
            ZStack(
                alignment: .bottomLeading
            ) {
                Image("GoalStrength")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 138)
                    .clipped()
                    .accessibilityHidden(
                        true
                    )

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black
                            .opacity(0.64)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(
                    alignment: .bottom,
                    spacing: 10
                ) {
                    Image(
                        systemName:
                            "dumbbell.fill"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .background(
                        Color.black
                            .opacity(0.32),
                        in: Circle()
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            text(
                                "Strength records",
                                "Styrke-rekorder"
                            )
                        )
                        .font(
                            .headline
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            .white
                        )

                        Text(
                            text(
                                "Records calculated from completed ATHLTH sets.",
                                "Rekorder beregnet fra fullførte ATHLTH-sett."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.84
                                )
                        )
                    }

                    Spacer()

                    sourceBadge(
                        title: "ATHLTH",
                        icon:
                            "sparkles"
                    )
                }
                .padding(14)
            }
            .frame(height: 138)

            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack {
                    Text(
                        text(
                            "Strength bests",
                            "Styrkerekorder"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.bold)
                    )

                    Spacer()

                    NavigationLink {
                        PerformanceRecordCollectionView(
                            title:
                                text(
                                    "Strength records",
                                    "Styrkerekorder"
                                ),
                            subtitle:
                                text(
                                    "ATHLTH records calculated from your completed strength workouts and working sets.",
                                    "ATHLTH-rekorder beregnet fra fullførte styrkeøkter og arbeidssett."
                                ),
                            imageName:
                                "GoalStrength",
                            items:
                                strengthDisplayItems,
                            sources:
                                Array(
                                    repeating:
                                        "ATHLTH",
                                    count:
                                        strengthDisplayItems
                                            .count
                                )
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text(
                                text(
                                    "View all",
                                    "Se alle"
                                )
                            )
                            Image(
                                systemName:
                                    "chevron.right"
                            )
                        }
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(
                            .flexible(),
                            spacing: 8
                        ),
                        GridItem(
                            .flexible(),
                            spacing: 8
                        )
                    ],
                    spacing: 8
                ) {
                    ForEach(
                        Array(
                            strengthSummaryItems
                                .enumerated()
                        ),
                        id: \.offset
                    ) {
                        _,
                        item in

                        lightPRMetric(
                            item,
                            source:
                                "ATHLTH"
                        )
                    }
                }
            }
            .padding(14)
        }
        .background(
            Color.white.opacity(
                0.94
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border
                    .opacity(0.62),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.055),
            radius: 14,
            y: 6
        )
    }

    private var strengthSummaryItems:
        [PerformanceMetricItem] {
        Array(
            strengthItems
                .prefix(4)
        ) + [
            longestStrengthWorkoutItem,
            bestWeeklyStrengthVolumeItem
        ]
    }

    private var strengthDisplayItems:
        [PerformanceMetricItem] {
        Array(
            strengthItems
                .prefix(6)
        ) + [
            longestStrengthWorkoutItem,
            mostStrengthSetsItem,
            mostStrengthRepsItem,
            mostStrengthExercisesItem,
            bestWeeklyStrengthVolumeItem,
            mostStrengthCaloriesItem
        ]
    }

    private func sourceBadge(
        title: String,
        icon: String
    ) -> some View {
        Label(
            title,
            systemImage: icon
        )
        .font(
            .system(
                size: 8,
                weight: .bold
            )
        )
        .tracking(0.45)
        .foregroundStyle(.white)
        .padding(
            .horizontal,
            8
        )
        .frame(height: 26)
        .background(
            Color.black
                .opacity(0.28),
            in: Capsule()
        )
    }

    private func lightPRMetric(
        _ item:
            PerformanceMetricItem,
        source: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            HStack {
                Image(
                    systemName:
                        item.icon
                )
                .font(
                    .system(
                        size: 11,
                        weight:
                            .semibold
                    )
                )
                .foregroundStyle(
                    item.tint
                )
                .frame(
                    width: 28,
                    height: 28
                )
                .background(
                    item.tint
                        .opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 9,
                            style:
                                .continuous
                        )
                )

                Spacer()

                Text(source)
                    .font(
                        .system(
                            size: 7.5,
                            weight:
                                .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
            }

            Text(item.title)
                .font(
                    .system(
                        size: 10,
                        weight:
                            .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.72
                )

            Text(item.value)
                .font(
                    .system(
                        size: 17,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.58
                )

            Text(
                item.detail
            )
            .font(
                .system(
                    size: 8.5,
                    weight: .medium
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
            .lineLimit(1)
            .minimumScaleFactor(
                0.64
            )

            Capsule()
                .fill(
                    item.tint
                )
                .frame(height: 3)
        }
        .padding(11)
        .frame(
            maxWidth: .infinity,
            minHeight: 126,
            alignment: .topLeading
        )
        .background(
            LinearGradient(
                colors: [
                    item.tint
                        .opacity(0.055),
                    Color.white
                        .opacity(0.94)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 17,
                    style:
                        .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(
                item.tint
                    .opacity(0.09),
                lineWidth: 0.7
            )
        }
    }


    private var editorialTrainingVolumeCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(spacing: 10) {
                Image(
                    systemName:
                        "chart.bar.fill"
                )
                .font(
                    .system(
                        size: 15,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    width: 34,
                    height: 34
                )
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        text(
                            "Training volume",
                            "Treningsvolum"
                        )
                    )
                    .font(
                        .headline
                            .weight(.bold)
                    )

                    Text(
                        trainingVolumePeriod
                            .subtitle
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                NavigationLink {
                    PerformanceTrainingVolumeDetailView(
                        stats: stats,
                        initialPeriod:
                            trainingVolumePeriod
                    )
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            text(
                                "Details",
                                "Detaljer"
                            )
                        )

                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }

            HStack(spacing: 4) {
                ForEach(
                    PerformanceVolumePeriod
                        .allCases
                ) {
                    period in

                    Button {
                        withAnimation(
                            .easeInOut(
                                duration: 0.18
                            )
                        ) {
                            trainingVolumePeriod =
                                period
                        }
                    } label: {
                        Text(period.title)
                            .font(
                                .system(
                                    size: 10,
                                    weight:
                                        trainingVolumePeriod ==
                                            period
                                        ? .bold
                                        : .medium
                                )
                            )
                            .foregroundStyle(
                                trainingVolumePeriod ==
                                    period
                                    ? ATHLTHTheme
                                        .primaryText
                                    : ATHLTHTheme
                                        .mutedText
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                            .frame(height: 31)
                            .background(
                                trainingVolumePeriod ==
                                    period
                                    ? Color.white
                                        .opacity(
                                            0.98
                                        )
                                    : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Color.black
                    .opacity(0.035),
                in: Capsule()
            )

            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                Text(
                    formatDistance(
                        selectedVolumeDistanceMeters
                    )
                )
                .font(
                    .system(
                        size: 28,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()

                Spacer()

                if trainingVolumePeriod ==
                    .year,
                   let change =
                    yearOverYearRunningChange {
                    HStack(spacing: 3) {
                        Image(
                            systemName:
                                change >= 0
                                ? "arrow.up.right"
                                : "arrow.down.right"
                        )

                        Text(
                            String(
                                format:
                                    "%+.0f%%",
                                change
                            )
                        )
                    }
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        change >= 0
                            ? Color.green
                            : Color.orange
                    )
                }
            }

            Text(
                text(
                    "Running distance",
                    "Løpedistanse"
                )
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )

            HStack(spacing: 8) {
                editorialVolumeMiniMetric(
                    value:
                        selectedVolumeWorkoutCount
                            .formatted(),
                    label:
                        text(
                            "Workouts",
                            "Økter"
                        ),
                    icon:
                        "checkmark.circle.fill"
                )

                editorialVolumeMiniMetric(
                    value:
                        selectedVolumeRunningCount
                            .formatted(),
                    label:
                        text(
                            "Runs",
                            "Løp"
                        ),
                    icon:
                        "figure.run"
                )

                editorialVolumeMiniMetric(
                    value:
                        selectedVolumeStrengthCount
                            .formatted(),
                    label:
                        text(
                            "Strength",
                            "Styrke"
                        ),
                    icon:
                        "dumbbell.fill"
                )

                editorialVolumeMiniMetric(
                    value:
                        selectedVolumeWalkingCount
                            .formatted(),
                    label:
                        text(
                            "Walks",
                            "Turer"
                        ),
                    icon:
                        "figure.walk"
                )
            }

            editorialSelectedVolumeChart
        }
        .padding(15)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
        .background(
            Color.white.opacity(
                0.90
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border
                    .opacity(0.62),
                lineWidth: 0.8
            )
        }
    }

    private func editorialVolumeMiniMetric(
        value: String,
        label: String,
        icon: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 10,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )

            Text(value)
                .font(
                    .subheadline
                        .weight(.bold)
                )
                .monospacedDigit()

            Text(label)
                .font(
                    .system(
                        size: 8.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
        }
        .padding(9)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            ATHLTHTheme
                .accentSoft
                .opacity(0.48),
            in:
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
        )
    }

    private var editorialSelectedVolumeChart:
        some View {
        let values =
            selectedVolumeSeries
        let maximum =
            max(
                values
                    .map(\.value)
                    .max() ?? 0,
                1
            )

        return HStack(
            alignment: .bottom,
            spacing: 5
        ) {
            ForEach(values) {
                point in

                VStack(spacing: 4) {
                    Spacer(
                        minLength: 0
                    )

                    RoundedRectangle(
                        cornerRadius: 4,
                        style: .continuous
                    )
                    .fill(
                        ATHLTHTheme
                            .accentDeep
                            .opacity(
                                point.value > 0
                                    ? 0.72
                                    : 0.12
                            )
                    )
                    .frame(
                        height:
                            max(
                                4,
                                70 *
                                (
                                    point.value /
                                    maximum
                                )
                            )
                    )

                    Text(point.label)
                        .font(
                            .system(
                                size: 7.5,
                                weight:
                                    .medium
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.65
                        )
                }
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 92)
            }
        }
    }

    private var selectedVolumeDistanceMeters:
        Double {
        if trainingVolumePeriod ==
            .total {
            return stats?
                .totalRunningDistanceMeters ??
                resolvedPerformanceWorkouts
                    .filter {
                        $0.activity ==
                            .running
                    }
                    .reduce(0.0) {
                        $0 +
                        max(
                            $1.distanceMeters ??
                                0,
                            0
                        )
                    }
        }

        return resolvedPerformanceWorkouts
            .filter {
                $0.activity ==
                    .running &&
                volumeDateIncluded(
                    $0.startDate,
                    period:
                        trainingVolumePeriod
                )
            }
            .reduce(0.0) {
                $0 +
                max(
                    $1.distanceMeters ??
                        0,
                    0
                )
            }
    }

    private var selectedVolumeWorkoutCount:
        Int {
        if trainingVolumePeriod ==
            .total {
            return stats?
                .totalWorkoutCount ??
                resolvedPerformanceWorkouts.count
        }

        return resolvedPerformanceWorkouts
            .filter {
                volumeDateIncluded(
                    $0.startDate,
                    period:
                        trainingVolumePeriod
                )
            }
            .count
    }

    private var selectedVolumeRunningCount:
        Int {
        resolvedPerformanceWorkouts
            .filter {
                $0.activity ==
                    .running &&
                (
                    trainingVolumePeriod ==
                        .total ||
                    volumeDateIncluded(
                        $0.startDate,
                        period:
                            trainingVolumePeriod
                    )
                )
            }
            .count
    }

    private var selectedVolumeStrengthCount:
        Int {
        resolvedPerformanceWorkouts
            .filter {
                $0.activity ==
                    .strength &&
                (
                    trainingVolumePeriod ==
                        .total ||
                    volumeDateIncluded(
                        $0.startDate,
                        period:
                            trainingVolumePeriod
                    )
                )
            }
            .count
    }

    private var selectedVolumeWalkingCount:
        Int {
        resolvedPerformanceWorkouts
            .filter {
                (
                    $0.activity ==
                        .walking ||
                    $0.activity ==
                        .hiking
                ) &&
                (
                    trainingVolumePeriod ==
                        .total ||
                    volumeDateIncluded(
                        $0.startDate,
                        period:
                            trainingVolumePeriod
                    )
                )
            }
            .count
    }

    private var selectedVolumeSeries:
        [PerformanceVolumePoint] {
        switch trainingVolumePeriod {
        case .week:
            return weekVolumeSeries
        case .month:
            return monthVolumeSeries
        case .year:
            return yearVolumeSeries
        case .total:
            return totalVolumeSeries
        }
    }

    private var weekVolumeSeries:
        [PerformanceVolumePoint] {
        let calendar =
            Calendar.current
        let start =
            calendar.dateInterval(
                of: .weekOfYear,
                for: Date()
            )?.start ??
            calendar.startOfDay(
                for: Date()
            )

        return (0..<7).map {
            offset in

            let day =
                calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: start
                ) ?? start
            let value =
                resolvedPerformanceWorkouts
                    .filter {
                        $0.activity ==
                            .running &&
                        calendar.isDate(
                            $0.startDate,
                            inSameDayAs: day
                        )
                    }
                    .reduce(0.0) {
                        $0 +
                        max(
                            $1.distanceMeters ??
                                0,
                            0
                        )
                    }

            return PerformanceVolumePoint(
                id:
                    "week-\(offset)",
                label:
                    day.formatted(
                        .dateTime
                            .weekday(
                                .narrow
                            )
                    ),
                value: value
            )
        }
    }

    private var monthVolumeSeries:
        [PerformanceVolumePoint] {
        let calendar =
            Calendar.current
        let monthInterval =
            calendar.dateInterval(
                of: .month,
                for: Date()
            )
        let start =
            monthInterval?.start ??
            Date()
        let end =
            monthInterval?.end ??
            Date()

        return (0..<5).map {
            index in

            let bucketStart =
                calendar.date(
                    byAdding: .day,
                    value: index * 7,
                    to: start
                ) ?? start
            let bucketEnd =
                min(
                    calendar.date(
                        byAdding: .day,
                        value: 7,
                        to: bucketStart
                    ) ?? end,
                    end
                )

            let value =
                resolvedPerformanceWorkouts
                    .filter {
                        $0.activity ==
                            .running &&
                        $0.startDate >=
                            bucketStart &&
                        $0.startDate <
                            bucketEnd
                    }
                    .reduce(0.0) {
                        $0 +
                        max(
                            $1.distanceMeters ??
                                0,
                            0
                        )
                    }

            return PerformanceVolumePoint(
                id:
                    "month-\(index)",
                label:
                    "U\(index + 1)",
                value: value
            )
        }
    }

    private var yearVolumeSeries:
        [PerformanceVolumePoint] {
        currentYearRunningDistanceByMonth
            .enumerated()
            .map {
                index,
                value in

                PerformanceVolumePoint(
                    id:
                        "year-\(index)",
                    label:
                        editorialMonthLetter(
                            index
                        ),
                    value: value
                )
            }
    }

    private var totalVolumeSeries:
        [PerformanceVolumePoint] {
        let calendar =
            Calendar.current
        let currentYear =
            calendar.component(
                .year,
                from: Date()
            )
        let years =
            Array(
                (max(
                    currentYear - 5,
                    2020
                )...currentYear)
            )

        return years.map {
            year in

            let value =
                resolvedPerformanceWorkouts
                    .filter {
                        $0.activity ==
                            .running &&
                        calendar.component(
                            .year,
                            from:
                                $0.startDate
                        ) == year
                    }
                    .reduce(0.0) {
                        $0 +
                        max(
                            $1.distanceMeters ??
                                0,
                            0
                        )
                    }

            return PerformanceVolumePoint(
                id:
                    "total-\(year)",
                label:
                    String(year)
                        .suffix(2)
                        .description,
                value: value
            )
        }
    }

    private func volumeDateIncluded(
        _ date: Date,
        period:
            PerformanceVolumePeriod
    ) -> Bool {
        let calendar =
            Calendar.current

        switch period {
        case .week:
            guard let interval =
                    calendar.dateInterval(
                        of: .weekOfYear,
                        for: Date()
                    )
            else {
                return false
            }
            return interval.contains(date)

        case .month:
            guard let interval =
                    calendar.dateInterval(
                        of: .month,
                        for: Date()
                    )
            else {
                return false
            }
            return interval.contains(date)

        case .year:
            return calendar.component(
                .year,
                from: date
            ) ==
                calendar.component(
                    .year,
                    from: Date()
                )

        case .total:
            return true
        }
    }


    private var editorialMonthlyRunningChart:
        some View {
        let values =
            currentYearRunningDistanceByMonth
        let maximum =
            max(
                values.max() ?? 0,
                1
            )

        return HStack(
            alignment: .bottom,
            spacing: 3
        ) {
            ForEach(
                Array(
                    values.enumerated()
                ),
                id: \.offset
            ) {
                index,
                value in
                VStack(spacing: 3) {
                    Spacer(
                        minLength: 0
                    )

                    RoundedRectangle(
                        cornerRadius: 3,
                        style: .continuous
                    )
                    .fill(
                        index ==
                            Calendar
                                .current
                                .component(
                                    .month,
                                    from: Date()
                                ) - 1
                            ? ATHLTHTheme
                                .accentDeep
                                .opacity(
                                    0.72
                                )
                            : ATHLTHTheme
                                .accentDeep
                                .opacity(
                                    0.18
                                )
                    )
                    .frame(
                        height:
                            max(
                                4,
                                54 *
                                (value /
                                 maximum)
                            )
                    )

                    Text(
                        editorialMonthLetter(
                            index
                        )
                    )
                    .font(
                        .system(
                            size: 6.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 72)
            }
        }
    }

    private var currentYearRunningDistanceByMonth:
        [Double] {
        let calendar =
            Calendar.current
        let year =
            calendar.component(
                .year,
                from: Date()
            )

        var values =
            Array(
                repeating: 0.0,
                count: 12
            )

        for workout in
            resolvedPerformanceWorkouts
            where workout.activity ==
                .running &&
                calendar.component(
                    .year,
                    from:
                        workout.startDate
                ) == year {
            let month =
                calendar.component(
                    .month,
                    from:
                        workout.startDate
                )

            guard (1...12)
                .contains(month)
            else {
                continue
            }

            values[month - 1] +=
                max(
                    workout
                        .distanceMeters ??
                    0,
                    0
                )
        }

        return values
    }

    private var currentYearRunningDistanceMeters:
        Double {
        currentYearRunningDistanceByMonth
            .reduce(0, +)
    }

    private var previousYearToDateRunningDistanceMeters:
        Double {
        let calendar =
            Calendar.current
        let now = Date()
        let currentYear =
            calendar.component(
                .year,
                from: now
            )
        let currentMonth =
            calendar.component(
                .month,
                from: now
            )

        return resolvedPerformanceWorkouts
            .filter { workout in
                workout.activity ==
                    .running &&
                calendar.component(
                    .year,
                    from:
                        workout.startDate
                ) ==
                    currentYear - 1 &&
                calendar.component(
                    .month,
                    from:
                        workout.startDate
                ) <= currentMonth
            }
            .reduce(0.0) {
                $0 +
                max(
                    $1.distanceMeters ??
                    0,
                    0
                )
            }
    }

    private var yearOverYearRunningChange:
        Double? {
        let previous =
            previousYearToDateRunningDistanceMeters

        guard previous > 0 else {
            return nil
        }

        return (
            (
                currentYearRunningDistanceMeters -
                previous
            ) /
            previous
        ) * 100
    }

    private func editorialMonthLetter(
        _ index: Int
    ) -> String {
        let symbols =
            Calendar.current
                .veryShortMonthSymbols

        guard symbols.indices
            .contains(index)
        else {
            return ""
        }

        return symbols[index]
    }

    private var editorialTrainingMixCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        text(
                            "Training mix",
                            "Treningsmiks"
                        )
                    )
                    .font(
                        .headline
                            .weight(.bold)
                    )

                    Text(
                        text(
                            "Your recorded sessions this year.",
                            "Dine registrerte økter dette året."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                Text(
                    currentYearWorkoutCount
                        .formatted()
                )
                .font(
                    .title2
                        .weight(.bold)
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
            }

            HStack(spacing: 8) {
                trainingMixMetric(
                    title:
                        text(
                            "Running",
                            "Løping"
                        ),
                    value:
                        currentYearRunningCount,
                    icon:
                        "figure.run",
                    tint: .green
                )

                trainingMixMetric(
                    title:
                        text(
                            "Strength",
                            "Styrke"
                        ),
                    value:
                        currentYearStrengthCount,
                    icon:
                        "dumbbell.fill",
                    tint:
                        ATHLTHTheme
                            .accentDeep
                )

                trainingMixMetric(
                    title:
                        text(
                            "Walk / hike",
                            "Gå / tur"
                        ),
                    value:
                        currentYearWalkingCount,
                    icon:
                        "figure.hiking",
                    tint: .orange
                )

                trainingMixMetric(
                    title:
                        text(
                            "Other",
                            "Annet"
                        ),
                    value:
                        max(
                            currentYearWorkoutCount -
                            currentYearRunningCount -
                            currentYearStrengthCount -
                            currentYearWalkingCount,
                            0
                        ),
                    icon:
                        "figure.mixed.cardio",
                    tint: .purple
                )
            }
        }
        .padding(15)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.92),
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.34)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border
                    .opacity(0.62),
                lineWidth: 0.8
            )
        }
    }

    private func trainingMixMetric(
        title: String,
        value: Int,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 12,
                    weight: .semibold
                )
            )
            .foregroundStyle(tint)

            Text(
                value.formatted()
            )
            .font(
                .headline
                    .weight(.bold)
            )
            .monospacedDigit()

            Text(title)
                .font(
                    .system(
                        size: 8.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.7
                )
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            tint.opacity(0.07),
            in:
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
        )
    }

    private var currentYearWorkoutCount:
        Int {
        let year =
            Calendar.current
                .component(
                    .year,
                    from: Date()
                )
        return resolvedPerformanceWorkouts
            .filter {
                Calendar.current
                    .component(
                        .year,
                        from:
                            $0.startDate
                    ) == year
            }
            .count
    }

    private var currentYearRunningCount:
        Int {
        currentYearActivityCount(
            matching: {
                $0 == .running
            }
        )
    }

    private var currentYearStrengthCount:
        Int {
        currentYearActivityCount(
            matching: {
                $0 == .strength
            }
        )
    }

    private var currentYearWalkingCount:
        Int {
        currentYearActivityCount(
            matching: {
                $0 == .walking ||
                $0 == .hiking
            }
        )
    }

    private func currentYearActivityCount(
        matching:
            (WorkoutActivity) -> Bool
    ) -> Int {
        let calendar =
            Calendar.current
        let year =
            calendar.component(
                .year,
                from: Date()
            )

        return resolvedPerformanceWorkouts
            .filter {
                calendar.component(
                    .year,
                    from:
                        $0.startDate
                ) == year &&
                matching($0.activity)
            }
            .count
    }

    private var editorialMilestonesCard:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 8) {
                Image(
                    systemName:
                        "flag.fill"
                )
                .font(
                    .system(
                        size: 14,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                )

                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {
                    Text(
                        text(
                            "Latest milestones",
                            "Siste milepæler"
                        )
                    )
                    .font(
                        .subheadline
                            .weight(.bold)
                    )

                    Text(
                        text(
                            "Recent achievements",
                            "Nylig oppnådde prestasjoner"
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                NavigationLink {
                    PerformanceMilestonesDetailView(
                        stats: stats,
                        healthRecords:
                            resolvedHealthRecords
                    )
                } label: {
                    HStack(spacing: 4) {
                        Text(
                            text(
                                "All",
                                "Alle"
                            )
                        )
                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }

            if let fiveK =
                    record(.fastest5K) {
                editorialMilestoneRow(
                    icon: "trophy.fill",
                    tint: .green,
                    title:
                        text(
                            "Fastest 5K",
                            "Raskeste 5 km"
                        ),
                    value:
                        fiveK.formattedValue,
                    detail:
                        formatDate(
                            fiveK.date
                        )
                )
            } else if let fallback =
                        stats?
                            .fastestFiveKilometers {
                editorialMilestoneRow(
                    icon: "trophy.fill",
                    tint: .green,
                    title:
                        text(
                            "Fastest 5K",
                            "Raskeste 5 km"
                        ),
                    value:
                        fallback
                            .formattedTime,
                    detail:
                        formatDate(
                            fallback.date
                        )
                )
            }

            if let longest =
                    record(.longestRun) {
                editorialMilestoneRow(
                    icon:
                        "location.fill",
                    tint: .purple,
                    title:
                        text(
                            "Longest distance",
                            "Lengste distanse"
                        ),
                    value:
                        longest
                            .formattedValue,
                    detail:
                        formatDate(
                            longest.date
                        )
                )
            } else if let meters =
                        stats?
                            .longestRunMeters,
                      meters > 0 {
                editorialMilestoneRow(
                    icon:
                        "location.fill",
                    tint: .purple,
                    title:
                        text(
                            "Longest distance",
                            "Lengste distanse"
                        ),
                    value:
                        formatDistance(
                            meters
                        ),
                    detail:
                        stats?
                            .longestRunDate
                            .map(
                                formatDate
                            ) ??
                        "—"
                )
            }

            if let longestWorkout =
                    record(
                        .longestWorkout
                    ) {
                editorialMilestoneRow(
                    icon: "clock.fill",
                    tint: .indigo,
                    title:
                        text(
                            "Longest workout",
                            "Lengste økt"
                        ),
                    value:
                        longestWorkout
                            .formattedValue,
                    detail:
                        formatDate(
                            longestWorkout
                                .date
                        )
                )
            }

            if let calories =
                    record(
                        .mostActiveCalories
                    ) {
                editorialMilestoneRow(
                    icon: "flame.fill",
                    tint: .orange,
                    title:
                        text(
                            "Most active calories",
                            "Flest aktive kalorier"
                        ),
                    value:
                        calories
                            .formattedValue,
                    detail:
                        formatDate(
                            calories
                                .date
                        )
                )
            }

            editorialMilestoneRow(
                icon:
                    "chart.line.uptrend.xyaxis",
                tint: .blue,
                title:
                    text(
                        "Total workouts",
                        "Totalt antall økter"
                    ),
                value:
                    stats?
                        .totalWorkoutCount
                        .formatted() ??
                    "—",
                detail:
                    text(
                        "All recorded",
                        "Totalt registrert"
                    )
            )
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
        .background(
            Color.white.opacity(0.86),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border
                    .opacity(0.62),
                lineWidth: 0.8
            )
        }
    }

    private func editorialMilestoneRow(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        NavigationLink {
            PerformanceMilestonesDetailView(
                stats: stats,
                healthRecords:
                    resolvedHealthRecords
            )
        } label: {
            HStack(spacing: 8) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 11,
                        weight: .bold
                    )
                )
                .foregroundStyle(tint)
                .frame(
                    width: 29,
                    height: 29
                )
                .background(
                    tint.opacity(
                        0.10
                    ),
                    in: Circle()
                )

            VStack(
                alignment: .leading,
                spacing: 1
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 10,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                Text(value)
                    .font(
                        .system(
                            size: 11,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                Text(detail)
                    .font(
                        .system(
                            size: 8.5,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(
                systemName:
                    "chevron.right"
            )
            .font(
                .system(
                    size: 9,
                    weight: .bold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var passportHero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image("ProgressHero")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    stops: [
                        .init(
                            color: .black.opacity(0.28),
                            location: 0
                        ),
                        .init(
                            color: .black.opacity(0.38),
                            location: 0.46
                        ),
                        .init(
                            color: .black.opacity(0.86),
                            location: 1
                        )
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )

                Path { path in
                    let w = proxy.size.width
                    let h = proxy.size.height

                    path.move(
                        to: CGPoint(
                            x: w * 0.42,
                            y: h * 0.76
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w * 0.98,
                            y: h * 0.34
                        ),
                        control1: CGPoint(
                            x: w * 0.60,
                            y: h * 0.79
                        ),
                        control2: CGPoint(
                            x: w * 0.78,
                            y: h * 0.38
                        )
                    )
                }
                .stroke(
                    ATHLTHTheme.premiumGold.opacity(0.72),
                    style: StrokeStyle(
                        lineWidth: 1.6,
                        lineCap: .round
                    )
                )
                .shadow(
                    color: ATHLTHTheme.premiumGold.opacity(0.45),
                    radius: 7
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("ATHLTH")
                        .font(.system(size: 13, weight: .black))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.82))

                    Text(
                        text(
                            "Performance Passport",
                            "Prestasjonspass"
                        )
                    )
                    .font(
                        .system(
                            size: 31,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                    Text(
                        text(
                            "Your personal performance, built from your training history.",
                            "Dine personlige prestasjoner, bygget fra treningshistorikken din."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .frame(height: 220)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.12),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: .black.opacity(0.12),
            radius: 18,
            y: 8
        )
    }

    private var featuredRecordsCard:
        some View {
        NavigationLink {
            ProfileRecordShowcasePickerView(
                stats: stats,
                healthRecords:
                    resolvedHealthRecords
            )
        } label: {
            VStack(
                alignment: .leading,
                spacing: 12
            ) {
                HStack(spacing: 11) {
                    Image(
                        systemName:
                            "sparkles.rectangle.stack.fill"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.premiumGold
                    )
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .background(
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.10),
                        in: Circle()
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            text(
                                "Show on profile",
                                "Vis på profil"
                            )
                        )
                        .font(
                            .subheadline
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )

                        Text(
                            text(
                                "Choose up to four personal records to feature.",
                                "Velg opptil fire personlige rekorder du vil vise frem."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(2)
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 4) {
                        Text(
                            text(
                                "Edit",
                                "Rediger"
                            )
                        )
                        Image(
                            systemName:
                                "chevron.right"
                        )
                    }
                    .font(
                        .caption.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                }

                HStack(spacing: 7) {
                    ForEach(
                        0..<ProfileFeaturedRecordKind
                            .showcaseLimit,
                        id: \.self
                    ) { index in
                        if featuredRecordKinds
                            .indices
                            .contains(index) {
                            let kind =
                                featuredRecordKinds[
                                    index
                                ]

                            featuredRecordSlot(
                                kind
                            )
                        } else {
                            emptyFeaturedRecordSlot
                        }
                    }
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.07),
                        Color(
                            .secondarySystemGroupedBackground
                        )
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.12),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var featuredRecordKinds:
        [ProfileFeaturedRecordKind] {
        ProfileFeaturedRecordKind
            .decodedSelection(
                from:
                    featuredRecordSelectionRaw
            )
    }

    private func featuredRecordSlot(
        _ kind:
            ProfileFeaturedRecordKind
    ) -> some View {
        VStack(spacing: 4) {
            Image(
                systemName: kind.icon
            )
            .font(
                .system(
                    size: 13,
                    weight: .semibold
                )
            )
            .foregroundStyle(kind.tint)

            Text(
                kind.displayValue(
                    healthRecords:
                        resolvedHealthRecords,
                    stats: stats
                )
            )
            .font(
                .system(
                    size: 11,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
            .lineLimit(1)
            .minimumScaleFactor(0.62)

            Text(kind.shortTitle)
                .font(
                    .system(
                        size: 8.5,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 70
        )
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var emptyFeaturedRecordSlot:
        some View {
        VStack(spacing: 5) {
            Image(systemName: "plus")
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )

            Text(
                text(
                    "Choose",
                    "Velg"
                )
            )
            .font(
                .system(
                    size: 8.5,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 70
        )
        .background(
            Color.black.opacity(0.025),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.16),
                style:
                    StrokeStyle(
                        lineWidth: 1,
                        dash: [4, 4]
                    )
            )
        }
    }

    private func metricSection(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        items: [PerformanceMetricItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(
                        accent.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider()
                        .opacity(0.5)
                }

                metricRow(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.05),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(0.035),
            radius: 12,
            y: 6
        )
    }

    private func metricRow(
        _ item: PerformanceMetricItem
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 34, height: 34)
                .background(
                    item.tint.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(2)

                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)

            Text(item.value)
                .font(
                    .subheadline
                        .monospacedDigit()
                        .weight(.bold)
                )
                .foregroundStyle(ATHLTHTheme.primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
    }

    private var verificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.premiumGold)
                    .frame(width: 36, height: 36)
                    .background(
                        ATHLTHTheme.premiumGold.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        text(
                            "Verified results",
                            "Verifiserte resultater"
                        )
                    )
                    .font(.headline.weight(.bold))

                    Text(
                        text(
                            "ATHLTH uses recorded data instead of estimating a result that was not measured.",
                            "ATHLTH bruker registrerte data i stedet for å estimere et resultat som ikke er målt."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Text(
                text(
                    "Running segment records require a recorded GPS route. Strength records are based on completed sets saved in ATHLTH.",
                    "Løpesegmentrekorder krever registrert GPS-rute. Styrkerekorder bygger på fullførte sett lagret i ATHLTH."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme.premiumGold.opacity(0.08),
                    Color(.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.premiumGold.opacity(0.12),
                lineWidth: 1
            )
        }
    }

    private var resolvedHealthRecords:
        [HealthPersonalRecord] {
        healthRecords.isEmpty
            ? fetchedHealthRecords
            : healthRecords
    }

    private var runningItems: [PerformanceMetricItem] {
        [
            runningRecordItem(
                kind: .fastest400M,
                title: text("Fastest 400 m", "Raskeste 400 m"),
                icon: "4.circle.fill",
                tint: .mint
            ),
            runningRecordItem(
                kind: .fastest800M,
                title: text("Fastest 800 m", "Raskeste 800 m"),
                icon: "8.circle.fill",
                tint: .teal
            ),
            runningRecordItem(
                kind: .fastest1K,
                title: text("Fastest 1K", "Raskeste 1 km"),
                icon: "1.circle.fill",
                tint: .blue,
                fallback: stats?.fastestOneKilometer
            ),
            runningRecordItem(
                kind: .fastestMile,
                title: text("Fastest mile", "Raskeste mile"),
                icon: "m.circle.fill",
                tint: .cyan
            ),
            runningRecordItem(
                kind: .fastest3K,
                title: text("Fastest 3K", "Raskeste 3 km"),
                icon: "3.circle.fill",
                tint: .indigo
            ),
            runningRecordItem(
                kind: .fastest5K,
                title: text("Fastest 5K", "Raskeste 5 km"),
                icon: "5.circle.fill",
                tint: .green,
                fallback: stats?.fastestFiveKilometers
            ),
            runningRecordItem(
                kind: .fastest10K,
                title: text("Fastest 10K", "Raskeste 10 km"),
                icon: "10.circle.fill",
                tint: .orange
            ),
            runningRecordItem(
                kind: .fastest15K,
                title: text("Fastest 15K", "Raskeste 15 km"),
                icon: "15.circle.fill",
                tint: .pink
            ),
            runningRecordItem(
                kind: .fastest10Mile,
                title: text("Fastest 10 miles", "Raskeste 10 miles"),
                icon: "figure.run.circle.fill",
                tint: .purple
            ),
            runningRecordItem(
                kind: .fastestHalfMarathon,
                title: text("Half marathon", "Halvmaraton"),
                icon: "mountain.2.fill",
                tint: .indigo
            ),
            runningRecordItem(
                kind: .fastestMarathon,
                title: text("Marathon", "Maraton"),
                icon: "flag.checkered",
                tint: ATHLTHTheme.premiumGold,
                fallback: stats?.fastestMarathon
            ),
            longestRunItem
        ]
    }

    private var volumeItems: [PerformanceMetricItem] {
        guard let stats else {
            return [
                emptyItem(
                    icon: "clock.fill",
                    title: text("Longest workout", "Lengste økt")
                ),
                emptyItem(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    title: text(
                        "Longest distance workout",
                        "Lengste distanseøkt"
                    )
                ),
                emptyItem(
                    icon: "checkmark.circle.fill",
                    title: text("Total workouts", "Totalt antall økter")
                ),
                emptyItem(
                    icon: "timer",
                    title: text("Total training time", "Total treningstid")
                ),
                emptyItem(
                    icon: "figure.run",
                    title: text(
                        "Running distance",
                        "Total løpsdistanse"
                    )
                )
            ]
        }

        return [
            PerformanceMetricItem(
                icon: "clock.fill",
                title: text("Longest workout", "Lengste økt"),
                value: formatDuration(stats.longestWorkoutDuration),
                detail: activityAndDate(
                    activity: stats.longestWorkoutActivity,
                    date: stats.longestWorkoutDate
                ),
                tint: .indigo
            ),
            PerformanceMetricItem(
                icon:
                    stats.longestWorkoutDistanceActivity?.icon ??
                    "location.fill",
                title: text(
                    "Longest distance workout",
                    "Lengste distanseøkt"
                ),
                value: formatDistance(
                    stats.longestWorkoutDistanceMeters
                ),
                detail: activityDateAndMil(
                    activity:
                        stats.longestWorkoutDistanceActivity,
                    date:
                        stats.longestWorkoutDistanceDate,
                    meters:
                        stats.longestWorkoutDistanceMeters
                ),
                tint: .blue
            ),
            PerformanceMetricItem(
                icon: "checkmark.circle.fill",
                title: text(
                    "Total workouts",
                    "Totalt antall økter"
                ),
                value: stats.totalWorkoutCount.formatted(),
                detail: text(
                    "All recorded workout types",
                    "Alle registrerte økttyper"
                ),
                tint: .green
            ),
            PerformanceMetricItem(
                icon: "timer",
                title: text(
                    "Total training time",
                    "Total treningstid"
                ),
                value: formatLongDuration(
                    stats.totalTrainingDuration
                ),
                detail: text(
                    "All recorded workouts",
                    "Alle registrerte økter"
                ),
                tint: .orange
            ),
            PerformanceMetricItem(
                icon: "figure.run",
                title: text(
                    "Running distance",
                    "Total løpsdistanse"
                ),
                value: formatDistance(
                    stats.totalRunningDistanceMeters
                ),
                detail: formatMil(
                    stats.totalRunningDistanceMeters
                ),
                tint: .blue
            )
        ]
    }

    private var strengthItems: [PerformanceMetricItem] {
        let records = strengthWorkout.personalRecords
        let heaviest =
            records
                .filter { $0.kind == .heaviestSet }
                .max { $0.score < $1.score }
        let estimatedOneRM =
            records.first {
                $0.kind == .estimatedOneRepMax
            }
        let workoutVolumeRecord =
            records.first {
                $0.kind == .workoutVolume
            }
        let completed =
            strengthWorkout.workoutHistory
                .filter(\.isFinished)
        let lifetimeVolume =
            completed.reduce(0.0) {
                $0 + max($1.totalVolumeKilograms, 0)
            }
        let bestRep =
            strengthWorkout.repPersonalRecords.max {
                if $0.weightKilograms ==
                    $1.weightKilograms {
                    return $0.reps < $1.reps
                }
                return $0.weightKilograms <
                    $1.weightKilograms
            }

        return [
            PerformanceMetricItem(
                icon: "trophy.fill",
                title: text("Heaviest set", "Tyngste sett"),
                value: heaviest?.value ?? "—",
                detail:
                    heaviest.map {
                        "\($0.title) · \(formatDate($0.date))"
                    } ??
                    text(
                        "No weighted record yet",
                        "Ingen vektet rekord ennå"
                    ),
                tint: ATHLTHTheme.premiumGold
            ),
            PerformanceMetricItem(
                icon: "bolt.fill",
                title: text(
                    "Estimated 1RM",
                    "Estimert 1RM"
                ),
                value: estimatedOneRM?.value ?? "—",
                detail:
                    estimatedOneRM.map {
                        "\($0.title) · \(formatDate($0.date))"
                    } ??
                    text(
                        "Built from completed sets",
                        "Bygges fra fullførte sett"
                    ),
                tint: .orange
            ),
            PerformanceMetricItem(
                icon: "chart.bar.fill",
                title: text(
                    "Best workout volume",
                    "Høyeste øktvolum"
                ),
                value: workoutVolumeRecord?.value ?? "—",
                detail:
                    workoutVolumeRecord.map {
                        formatDate($0.date)
                    } ??
                    text(
                        "No volume record yet",
                        "Ingen volumrekord ennå"
                    ),
                tint: .blue
            ),
            PerformanceMetricItem(
                icon: "repeat",
                title: text("Best rep PR", "Beste repetisjons-PR"),
                value: bestRep?.value ?? "—",
                detail:
                    bestRep.map {
                        "\($0.exerciseName) · \(formatDate($0.date))"
                    } ??
                    text(
                        "No rep PR yet",
                        "Ingen repetisjons-PR ennå"
                    ),
                tint: .purple
            ),
            PerformanceMetricItem(
                icon: "list.number",
                title: text(
                    "Strength workouts",
                    "Styrkeøkter"
                ),
                value: completed.count.formatted(),
                detail: text(
                    "Completed in ATHLTH",
                    "Fullført i ATHLTH"
                ),
                tint: .green
            ),
            PerformanceMetricItem(
                icon: "scalemass.fill",
                title: text(
                    "Lifetime volume",
                    "Totalt styrkevolum"
                ),
                value: formatKilograms(lifetimeVolume),
                detail: text(
                    "Working-set volume",
                    "Volum fra arbeidssett"
                ),
                tint: ATHLTHTheme.accentDeep
            )
        ]
    }

    private var bestWeeklyRunningDistanceItem:
        PerformanceMetricItem {
        let grouped =
            Dictionary(
                grouping:
                    resolvedPerformanceWorkouts
                        .filter {
                            $0.activity ==
                                .running
                        }
            ) {
                weekBucket(
                    for:
                        $0.startDate
                )
            }

        let best =
            grouped
                .map {
                    key,
                    workouts in
                    (
                        key,
                        workouts.reduce(
                            0.0
                        ) {
                            $0 +
                            max(
                                $1.distanceMeters ??
                                    0,
                                0
                            )
                        }
                    )
                }
                .max {
                    $0.1 <
                    $1.1
                }

        return PerformanceMetricItem(
            icon:
                "calendar.badge.checkmark",
            title:
                text(
                    "Best weekly distance",
                    "Beste ukesdistanse"
                ),
            value:
                formatDistance(
                    best?.1
                ),
            detail:
                best.map {
                    weekLabel($0.0)
                } ??
                text(
                    "No running history yet",
                    "Ingen løpehistorikk ennå"
                ),
            tint: .green
        )
    }

    private var mostRunsInWeekItem:
        PerformanceMetricItem {
        let grouped =
            Dictionary(
                grouping:
                    resolvedPerformanceWorkouts
                        .filter {
                            $0.activity ==
                                .running
                        }
            ) {
                weekBucket(
                    for:
                        $0.startDate
                )
            }

        let best =
            grouped.max {
                $0.value.count <
                $1.value.count
            }

        return PerformanceMetricItem(
            icon:
                "calendar.badge.plus",
            title:
                text(
                    "Most runs in a week",
                    "Flest løpeøkter på én uke"
                ),
            value:
                best.map {
                    $0.value.count
                        .formatted()
                } ?? "—",
            detail:
                best.map {
                    weekLabel($0.key)
                } ??
                text(
                    "No running history yet",
                    "Ingen løpehistorikk ennå"
                ),
            tint: .cyan
        )
    }

    private var bestRunningMonthItem:
        PerformanceMetricItem {
        let calendar =
            Calendar.current
        let running =
            resolvedPerformanceWorkouts
                .filter {
                    $0.activity ==
                        .running
                }

        let grouped =
            Dictionary(
                grouping: running
            ) {
                calendar
                    .dateInterval(
                        of: .month,
                        for:
                            $0.startDate
                    )?
                    .start ??
                calendar.startOfDay(
                    for:
                        $0.startDate
                )
            }

        let best =
            grouped
                .map {
                    key,
                    workouts in
                    (
                        key,
                        workouts.reduce(
                            0.0
                        ) {
                            $0 +
                            max(
                                $1.distanceMeters ??
                                    0,
                                0
                            )
                        }
                    )
                }
                .max {
                    $0.1 <
                    $1.1
                }

        return PerformanceMetricItem(
            icon:
                "calendar",
            title:
                text(
                    "Best running month",
                    "Beste løpemåned"
                ),
            value:
                formatDistance(
                    best?.1
                ),
            detail:
                best.map {
                    monthLabel($0.0)
                } ??
                text(
                    "No running history yet",
                    "Ingen løpehistorikk ennå"
                ),
            tint: .orange
        )
    }

    private var finishedStrengthWorkouts:
        [StrengthWorkoutLog] {
        strengthWorkout
            .workoutHistory
            .filter(\.isFinished)
    }

    private var longestStrengthWorkoutItem:
        PerformanceMetricItem {
        let best =
            finishedStrengthWorkouts
                .compactMap {
                    workout ->
                        (
                            StrengthWorkoutLog,
                            TimeInterval
                        )? in

                    let duration =
                        workout
                            .healthMetrics
                            .duration ??
                        workout
                            .endedAt
                            .map {
                                $0.timeIntervalSince(
                                    workout
                                        .startedAt
                                )
                            }

                    guard let duration,
                          duration > 0
                    else {
                        return nil
                    }

                    return (
                        workout,
                        duration
                    )
                }
                .max {
                    $0.1 <
                    $1.1
                }

        return PerformanceMetricItem(
            icon: "clock.fill",
            title:
                text(
                    "Longest strength workout",
                    "Lengste styrkeøkt"
                ),
            value:
                formatDuration(
                    best?.1
                ),
            detail:
                best.map {
                    formatDate(
                        $0.0
                            .startedAt
                    )
                } ??
                text(
                    "No completed workout yet",
                    "Ingen fullført økt ennå"
                ),
            tint: .indigo
        )
    }

    private var mostStrengthSetsItem:
        PerformanceMetricItem {
        let best =
            finishedStrengthWorkouts
                .max {
                    $0.totalCompletedSets <
                    $1.totalCompletedSets
                }

        return PerformanceMetricItem(
            icon: "list.number",
            title:
                text(
                    "Most sets in a workout",
                    "Flest sett i én økt"
                ),
            value:
                best.map {
                    $0.totalCompletedSets
                        .formatted()
                } ?? "—",
            detail:
                best.map {
                    formatDate(
                        $0.startedAt
                    )
                } ??
                text(
                    "No completed workout yet",
                    "Ingen fullført økt ennå"
                ),
            tint: .blue
        )
    }

    private var mostStrengthRepsItem:
        PerformanceMetricItem {
        let best =
            finishedStrengthWorkouts
                .map {
                    workout in
                    (
                        workout,
                        workout.exercises
                            .flatMap(\.sets)
                            .filter(
                                \.isCompleted
                            )
                            .reduce(0) {
                                $0 +
                                max(
                                    $1.completedReps ??
                                        0,
                                    0
                                )
                            }
                    )
                }
                .max {
                    $0.1 <
                    $1.1
                }

        return PerformanceMetricItem(
            icon:
                "repeat.circle.fill",
            title:
                text(
                    "Most reps in a workout",
                    "Flest reps i én økt"
                ),
            value:
                best.map {
                    $0.1.formatted()
                } ?? "—",
            detail:
                best.map {
                    formatDate(
                        $0.0
                            .startedAt
                    )
                } ??
                text(
                    "No completed workout yet",
                    "Ingen fullført økt ennå"
                ),
            tint: .purple
        )
    }

    private var mostStrengthExercisesItem:
        PerformanceMetricItem {
        let best =
            finishedStrengthWorkouts
                .map {
                    workout in
                    (
                        workout,
                        workout.exercises
                            .filter(
                                \.isCompleted
                            )
                            .count
                    )
                }
                .max {
                    $0.1 <
                    $1.1
                }

        return PerformanceMetricItem(
            icon:
                "square.grid.2x2.fill",
            title:
                text(
                    "Most exercises in a workout",
                    "Flest øvelser i én økt"
                ),
            value:
                best.map {
                    $0.1.formatted()
                } ?? "—",
            detail:
                best.map {
                    formatDate(
                        $0.0
                            .startedAt
                    )
                } ??
                text(
                    "No completed workout yet",
                    "Ingen fullført økt ennå"
                ),
            tint: .teal
        )
    }

    private var bestWeeklyStrengthVolumeItem:
        PerformanceMetricItem {
        let grouped =
            Dictionary(
                grouping:
                    finishedStrengthWorkouts
            ) {
                weekBucket(
                    for:
                        $0.startedAt
                )
            }

        let best =
            grouped
                .map {
                    key,
                    workouts in
                    (
                        key,
                        workouts.reduce(
                            0.0
                        ) {
                            $0 +
                            max(
                                $1.totalVolumeKilograms,
                                0
                            )
                        }
                    )
                }
                .max {
                    $0.1 <
                    $1.1
                }

        return PerformanceMetricItem(
            icon:
                "chart.bar.fill",
            title:
                text(
                    "Best weekly volume",
                    "Høyeste ukesvolum"
                ),
            value:
                best.map {
                    formatKilograms(
                        $0.1
                    )
                } ?? "—",
            detail:
                best.map {
                    weekLabel($0.0)
                } ??
                text(
                    "No completed workouts yet",
                    "Ingen fullførte økter ennå"
                ),
            tint:
                ATHLTHTheme
                    .accentDeep
        )
    }

    private var mostStrengthCaloriesItem:
        PerformanceMetricItem {
        let best =
            finishedStrengthWorkouts
                .compactMap {
                    workout ->
                        (
                            StrengthWorkoutLog,
                            Double
                        )? in

                    guard let calories =
                            workout
                                .healthMetrics
                                .activeCalories,
                          calories > 0
                    else {
                        return nil
                    }

                    return (
                        workout,
                        calories
                    )
                }
                .max {
                    $0.1 <
                    $1.1
                }

        return PerformanceMetricItem(
            icon: "flame.fill",
            title:
                text(
                    "Most active calories",
                    "Flest aktive kalorier"
                ),
            value:
                best.map {
                    "\(Int($0.1.rounded())) kcal"
                } ?? "—",
            detail:
                best.map {
                    formatDate(
                        $0.0
                            .startedAt
                    )
                } ??
                text(
                    "No calorie record yet",
                    "Ingen kalorirekord ennå"
                ),
            tint: .orange
        )
    }

    private func weekBucket(
        for date: Date
    ) -> Date {
        Calendar.current
            .dateInterval(
                of: .weekOfYear,
                for: date
            )?
            .start ??
            Calendar.current
                .startOfDay(
                    for: date
                )
    }

    private func weekLabel(
        _ start: Date
    ) -> String {
        let calendar =
            Calendar.current
        let end =
            calendar.date(
                byAdding: .day,
                value: 6,
                to: start
            ) ?? start

        return
            start.formatted(
                .dateTime
                    .day()
                    .month(
                        .abbreviated
                    )
            ) +
            " – " +
            end.formatted(
                .dateTime
                    .day()
                    .month(
                        .abbreviated
                    )
            )
    }

    private func monthLabel(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime
                .month(.wide)
                .year()
        )
    }

    private var recoveryItems: [PerformanceMetricItem] {
        let sleepValue =
            health.sleep.totalAsleep > 0
                ? formatDuration(health.sleep.totalAsleep)
                : "—"
        let sleepDetail: String
        if let end = health.sleep.sleepEnd {
            sleepDetail =
                text("Last sleep · ", "Siste søvn · ") +
                formatDate(end)
        } else {
            sleepDetail =
                text(
                    "No recent sleep data",
                    "Ingen nyere søvndata"
                )
        }

        return [
            PerformanceMetricItem(
                icon: "moon.fill",
                title: text("Last sleep", "Siste søvn"),
                value: sleepValue,
                detail: sleepDetail,
                tint: .indigo
            ),
            PerformanceMetricItem(
                icon: "waveform.path.ecg",
                title: "HRV",
                value:
                    health.heart.hrvMilliseconds.map {
                        "\(Int($0.rounded())) ms"
                    } ?? "—",
                detail:
                    health.heart.hrvDate.map {
                        formatDate($0)
                    } ??
                    text(
                        "No recent HRV",
                        "Ingen nyere HRV"
                    ),
                tint: .blue
            ),
            PerformanceMetricItem(
                icon: "heart.fill",
                title: text(
                    "Resting heart rate",
                    "Hvilepuls"
                ),
                value:
                    health.heart.restingHeartRate.map {
                        "\(Int($0.rounded())) bpm"
                    } ?? "—",
                detail:
                    health.heart.restingHeartRateDate.map {
                        formatDate($0)
                    } ??
                    text(
                        "No recent resting HR",
                        "Ingen nyere hvilepuls"
                    ),
                tint: .red
            ),
            PerformanceMetricItem(
                icon: "leaf.fill",
                title: text(
                    "Recovery score",
                    "Restitusjonsscore"
                ),
                value:
                    health.recovery.score.map {
                        "\($0)"
                    } ?? "—",
                detail:
                    health.recovery.score == nil
                        ? text(
                            "Building your baseline",
                            "Bygger grunnlaget ditt"
                        )
                        : health.recovery.detail,
                tint: .green
            )
        ]
    }

    private var otherItems: [PerformanceMetricItem] {
        [
            healthRecordItem(
                kind: .longestRide,
                title: text(
                    "Longest ride",
                    "Lengste sykkeltur"
                ),
                icon: "figure.outdoor.cycle",
                tint: .green
            ),
            healthRecordItem(
                kind: .longestWalkOrHike,
                title: text(
                    "Longest walk / hike",
                    "Lengste gåtur / fjelltur"
                ),
                icon: "figure.hiking",
                tint: .brown
            ),
            healthRecordItem(
                kind: .mostActiveCalories,
                title: text(
                    "Most active calories",
                    "Flest aktive kalorier"
                ),
                icon: "flame.fill",
                tint: .orange
            ),
            healthRecordItem(
                kind: .longestWorkout,
                title: text(
                    "Longest workout",
                    "Lengste økt"
                ),
                icon: "clock.fill",
                tint: .indigo
            )
        ]
    }

    private var longestRunItem: PerformanceMetricItem {
        if let record = record(.longestRun) {
            return PerformanceMetricItem(
                icon:
                    "point.topleft.down.to.point.bottomright.curvepath",
                title: text(
                    "Longest run",
                    "Lengste løpetur"
                ),
                value: record.formattedValue,
                detail: formatDate(record.date),
                tint: .purple
            )
        }

        return PerformanceMetricItem(
            icon:
                "point.topleft.down.to.point.bottomright.curvepath",
            title: text(
                "Longest run",
                "Lengste løpetur"
            ),
            value:
                formatDistance(
                    stats?.longestRunMeters
                ),
            detail:
                stats?.longestRunDate.map {
                    formatDate($0)
                } ??
                text(
                    "No run recorded yet",
                    "Ingen løpetur registrert ennå"
                ),
            tint: .purple
        )
    }

    private func runningRecordItem(
        kind: HealthPersonalRecordKind,
        title: String,
        icon: String,
        tint: Color,
        fallback: TimedDistancePerformanceRecord? = nil
    ) -> PerformanceMetricItem {
        if let record = record(kind) {
            return PerformanceMetricItem(
                icon: icon,
                title: title,
                value: record.formattedValue,
                detail: runningRecordDetail(record),
                tint: tint
            )
        }

        if let fallback {
            return PerformanceMetricItem(
                icon: icon,
                title: title,
                value: fallback.formattedTime,
                detail:
                    "\(fallback.formattedPace) · " +
                    formatDate(fallback.date),
                tint: tint
            )
        }

        return emptyItem(
            icon: icon,
            title: title,
            tint: tint,
            detail: text(
                "No GPS-verified result yet",
                "Ingen GPS-verifisert rekord ennå"
            )
        )
    }

    private func healthRecordItem(
        kind: HealthPersonalRecordKind,
        title: String,
        icon: String,
        tint: Color
    ) -> PerformanceMetricItem {
        guard let record = record(kind) else {
            return emptyItem(
                icon: icon,
                title: title,
                tint: tint
            )
        }

        return PerformanceMetricItem(
            icon: icon,
            title: title,
            value: record.formattedValue,
            detail: formatDate(record.date),
            tint: tint
        )
    }

    private func emptyItem(
        icon: String,
        title: String,
        tint: Color = ATHLTHTheme.accentDeep,
        detail: String? = nil
    ) -> PerformanceMetricItem {
        PerformanceMetricItem(
            icon: icon,
            title: title,
            value: "—",
            detail:
                detail ??
                text(
                    "No recorded result yet",
                    "Ingen registrert verdi ennå"
                ),
            tint: tint
        )
    }

    private func record(
        _ kind: HealthPersonalRecordKind
    ) -> HealthPersonalRecord? {
        resolvedHealthRecords.first {
            $0.kind == kind
        }
    }

    private func runningRecordDetail(
        _ record: HealthPersonalRecord
    ) -> String {
        guard let distance =
                record.kind.targetDistanceMeters,
              distance > 0
        else {
            return formatDate(record.date)
        }

        let pace =
            record.value /
            (distance / 1_000)

        return
            "\(formatPace(pace)) · " +
            formatDate(record.date)
    }

    private func text(
        _ english: String,
        _ norwegian: String
    ) -> String {
        ATHLTHLocalization.choose(
            english: english,
            norwegian: norwegian
        )
    }

    private func formatDate(
        _ date: Date
    ) -> String {
        date.formatted(
            date: .abbreviated,
            time: .omitted
        )
    }

    private func activityAndDate(
        activity: WorkoutActivity?,
        date: Date?
    ) -> String {
        let activityName =
            activity?.rawValue ??
            text("Workout", "Trening")

        guard let date else {
            return activityName
        }

        return
            "\(activityName) · " +
            formatDate(date)
    }

    private func activityDateAndMil(
        activity: WorkoutActivity?,
        date: Date?,
        meters: Double?
    ) -> String {
        var components: [String] = []

        if let activity {
            components.append(activity.rawValue)
        }

        if meters != nil {
            components.append(formatMil(meters))
        }

        if let date {
            components.append(formatDate(date))
        }

        return components.isEmpty
            ? "—"
            : components.joined(separator: " · ")
    }

    private func formatPace(
        _ secondsPerKilometer: TimeInterval
    ) -> String {
        guard secondsPerKilometer.isFinite,
              secondsPerKilometer > 0
        else {
            return "—"
        }

        let total = Int(secondsPerKilometer.rounded())
        return String(
            format:
                "%d:%02d /km",
            total / 60,
            total % 60
        )
    }

    private func formatKilograms(
        _ kilograms: Double
    ) -> String {
        guard kilograms > 0 else {
            return "—"
        }

        if kilograms >= 1_000_000 {
            return String(
                format:
                    "%.2fM kg",
                kilograms / 1_000_000
            )
        }

        if kilograms >= 10_000 {
            return String(
                format:
                    "%.0f kg",
                kilograms
            )
        }

        return String(
            format:
                "%.1f kg",
            kilograms
        )
    }
}

private struct PerformanceRecordCollectionView:
    View {
    let title: String
    let subtitle: String
    let imageName: String
    let items:
        [PerformanceMetricItem]
    let sources: [String]

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.14)
            )

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    hero

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .flexible(),
                                spacing: 10
                            ),
                            GridItem(
                                .flexible(),
                                spacing: 10
                            )
                        ],
                        spacing: 10
                    ) {
                        ForEach(
                            Array(
                                items
                                    .enumerated()
                            ),
                            id: \.offset
                        ) {
                            index,
                            item in

                            recordCard(
                                item,
                                source:
                                    sources
                                        .indices
                                        .contains(
                                            index
                                        )
                                    ? sources[
                                        index
                                    ]
                                    : "ATHLTH"
                            )
                        }
                    }
                }
                .padding(
                    .horizontal,
                    16
                )
                .padding(.top, 10)
                .padding(
                    .bottom,
                    40
                )
                .frame(
                    maxWidth: 760
                )
                .frame(
                    maxWidth:
                        .infinity
                )
            }
            .scrollIndicators(
                .hidden
            )
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private var hero:
        some View {
        GeometryReader {
            proxy in

            ZStack(
                alignment:
                    .bottomLeading
            ) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width:
                            proxy.size
                                .width,
                        height:
                            proxy.size
                                .height
                    )
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black
                            .opacity(0.66)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(title)
                        .font(
                            .title2
                                .weight(.bold)
                        )
                        .foregroundStyle(
                            .white
                        )

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            .white
                                .opacity(
                                    0.86
                                )
                        )
                        .fixedSize(
                            horizontal:
                                false,
                            vertical:
                                true
                        )
                }
                .padding(16)
            }
        }
        .frame(height: 176)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
    }

    private func recordCard(
        _ item:
            PerformanceMetricItem,
        source: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Image(
                    systemName:
                        item.icon
                )
                .font(
                    .system(
                        size: 14,
                        weight:
                            .semibold
                    )
                )
                .foregroundStyle(
                    item.tint
                )
                .frame(
                    width: 38,
                    height: 38
                )
                .background(
                    item.tint
                        .opacity(0.10),
                    in:
                        RoundedRectangle(
                            cornerRadius: 12,
                            style:
                                .continuous
                        )
                )

                Spacer()

                Text(source)
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
            }

            Text(item.title)
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(2)

            Text(item.value)
                .font(
                    .title3
                        .weight(.bold)
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(
                    0.62
                )

            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
                .lineLimit(2)

            Spacer(
                minLength: 0
            )

            Capsule()
                .fill(item.tint)
                .frame(height: 3)
        }
        .padding(13)
        .frame(
            maxWidth: .infinity,
            minHeight: 154,
            alignment: .topLeading
        )
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                item.tint
                    .opacity(0.10),
                lineWidth: 0.8
            )
        }
    }
}

private struct PerformanceTrainingVolumeDetailView:
    View {
    let stats: ProfilePerformanceStats?
    @EnvironmentObject private var health:
        HealthKitManager
    @State private var period:
        PerformanceVolumePeriod
    @State private var workoutHistory:
        [WorkoutSummary] = []

    init(
        stats: ProfilePerformanceStats?,
        initialPeriod:
            PerformanceVolumePeriod
    ) {
        self.stats = stats
        _period =
            State(
                initialValue:
                    initialPeriod
            )
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.16)
            )

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    volumeHero
                    periodPicker
                    metricsGrid
                    activityBreakdown
                    recentSessions
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 40)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Training volume",
                norwegian:
                    "Treningsvolum"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task {
            guard workoutHistory
                    .isEmpty,
                  health
                    .hasRequestedAuthorization
            else {
                return
            }

            workoutHistory =
                (
                    try? await health
                        .performanceWorkoutHistory()
                ) ??
                health.workouts
        }
    }

    private var volumeHero:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        period.subtitle
                    )
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        formatDistance(
                            distanceMeters
                        )
                    )
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Recorded running distance",
                            norwegian:
                                "Registrert løpedistanse"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }

                Spacer()

                Image(
                    systemName:
                        "chart.bar.xaxis"
                )
                .font(
                    .system(
                        size: 26,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
                .frame(
                    width: 62,
                    height: 62
                )
                .background(
                    ATHLTHTheme
                        .accentSoft,
                    in:
                        RoundedRectangle(
                            cornerRadius: 19,
                            style: .continuous
                        )
                )
            }

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Built from your recorded Health workouts. Change the period below to inspect your actual training history.",
                    norwegian:
                        "Bygget fra de registrerte Health-øktene dine. Bytt periode under for å se den faktiske treningshistorikken."
                )
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.96),
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.56)
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .border
                    .opacity(0.64),
                lineWidth: 0.8
            )
        }
    }

    private var periodPicker:
        some View {
        HStack(spacing: 4) {
            ForEach(
                PerformanceVolumePeriod
                    .allCases
            ) { option in
                Button {
                    withAnimation(
                        .easeInOut(
                            duration: 0.18
                        )
                    ) {
                        period = option
                    }
                } label: {
                    Text(option.title)
                        .font(
                            .caption
                                .weight(
                                    period ==
                                        option
                                    ? .bold
                                    : .medium
                                )
                        )
                        .foregroundStyle(
                            period ==
                                option
                                ? Color.white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .frame(height: 38)
                        .background(
                            period ==
                                option
                                ? ATHLTHTheme
                                    .accentDeep
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Color.white
                .opacity(0.86),
            in: Capsule()
        )
    }

    private var metricsGrid:
        some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .flexible(),
                    spacing: 10
                ),
                GridItem(
                    .flexible(),
                    spacing: 10
                )
            ],
            spacing: 10
        ) {
            detailMetric(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Workouts",
                            norwegian:
                                "Økter"
                        ),
                value:
                    workoutCount
                        .formatted(),
                icon:
                    "checkmark.circle.fill",
                tint:
                    ATHLTHTheme
                        .accentDeep
            )

            detailMetric(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Runs",
                            norwegian:
                                "Løpeøkter"
                        ),
                value:
                    runningCount
                        .formatted(),
                icon:
                    "figure.run",
                tint: .green
            )

            detailMetric(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Strength",
                            norwegian:
                                "Styrkeøkter"
                        ),
                value:
                    strengthCount
                        .formatted(),
                icon:
                    "dumbbell.fill",
                tint: .indigo
            )

            detailMetric(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Walk / hike",
                            norwegian:
                                "Gå / tur"
                        ),
                value:
                    walkingCount
                        .formatted(),
                icon:
                    "figure.hiking",
                tint: .orange
            )
        }
    }

    private func detailMetric(
        title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 11) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 16,
                    weight: .semibold
                )
            )
            .foregroundStyle(tint)
            .frame(
                width: 40,
                height: 40
            )
            .background(
                tint.opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(value)
                    .font(
                        .title3
                            .weight(.bold)
                    )
                    .monospacedDigit()

                Text(title)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(13)
        .background(
            Color.white
                .opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
    }

    private var activityBreakdown:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Activity mix",
                    norwegian:
                        "Aktivitetsmiks"
                )
            )
            .font(
                .headline
                    .weight(.bold)
            )

            breakdownRow(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Running",
                            norwegian:
                                "Løping"
                        ),
                value:
                    runningCount,
                total:
                    max(
                        workoutCount,
                        1
                    ),
                tint: .green
            )

            breakdownRow(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Strength",
                            norwegian:
                                "Styrke"
                        ),
                value:
                    strengthCount,
                total:
                    max(
                        workoutCount,
                        1
                    ),
                tint: .indigo
            )

            breakdownRow(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Walk / hike",
                            norwegian:
                                "Gå / tur"
                        ),
                value:
                    walkingCount,
                total:
                    max(
                        workoutCount,
                        1
                    ),
                tint: .orange
            )

            let other =
                max(
                    workoutCount -
                    runningCount -
                    strengthCount -
                    walkingCount,
                    0
                )

            breakdownRow(
                title:
                    ATHLTHLocalization
                        .choose(
                            english:
                                "Other",
                            norwegian:
                                "Annet"
                        ),
                value: other,
                total:
                    max(
                        workoutCount,
                        1
                    ),
                tint: .purple
            )
        }
        .padding(15)
        .background(
            Color.white
                .opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
    }

    private func breakdownRow(
        title: String,
        value: Int,
        total: Int,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(
                    .caption
                        .weight(.semibold)
                )
                .frame(
                    width: 82,
                    alignment: .leading
                )

            GeometryReader {
                proxy in

                ZStack(
                    alignment: .leading
                ) {
                    Capsule()
                        .fill(
                            Color.black
                                .opacity(0.06)
                        )

                    Capsule()
                        .fill(tint)
                        .frame(
                            width:
                                proxy
                                    .size
                                    .width *
                                min(
                                    Double(value) /
                                    Double(total),
                                    1
                                )
                        )
                }
            }
            .frame(height: 7)

            Text(
                value.formatted()
            )
            .font(
                .caption
                    .weight(.bold)
            )
            .monospacedDigit()
            .frame(
                width: 30,
                alignment: .trailing
            )
        }
    }

    private var recentSessions:
        some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Recent sessions",
                        norwegian:
                            "Nylige økter"
                    )
                )
                .font(
                    .system(
                        size: 14,
                        weight: .bold,
                        design: .rounded
                    )
                )

                Spacer()

                Text(
                    selectedWorkouts
                        .count
                        .formatted()
                )
                .font(
                    .caption
                        .weight(.bold)
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )
            }

            if selectedWorkouts
                .isEmpty {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "No recorded workouts in this period.",
                        norwegian:
                            "Ingen registrerte økter i denne perioden."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .padding(
                    .vertical,
                    8
                )
            } else {
                ForEach(
                    Array(
                        selectedWorkouts
                            .prefix(12)
                    ),
                    id: \.id
                ) {
                    workout in

                    HStack(spacing: 11) {
                        Image(
                            systemName:
                                activityIcon(
                                    workout
                                        .activity
                                )
                        )
                        .font(
                            .system(
                                size: 14,
                                weight:
                                    .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                        .frame(
                            width: 38,
                            height: 38
                        )
                        .background(
                            ATHLTHTheme
                                .accentSoft,
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        12,
                                    style:
                                        .continuous
                                )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                activityTitle(
                                    workout
                                        .activity
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            Text(
                                workout
                                    .startDate
                                    .formatted(
                                        date:
                                            .abbreviated,
                                        time:
                                            .shortened
                                    )
                            )
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Spacer()

                        if let meters =
                                workout
                                    .distanceMeters,
                           meters > 0 {
                            Text(
                                formatDistance(
                                    meters
                                )
                            )
                            .font(
                                .caption
                                    .weight(
                                        .bold
                                    )
                            )
                            .monospacedDigit()
                        }
                    }
                    .padding(
                        .vertical,
                        4
                    )
                }
            }
        }
        .padding(15)
        .background(
            Color.white
                .opacity(0.90),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
    }

    private var resolvedWorkouts:
        [WorkoutSummary] {
        workoutHistory.isEmpty
            ? health.workouts
            : workoutHistory
    }

    private var selectedWorkouts:
        [WorkoutSummary] {
        resolvedWorkouts
            .filter {
                period ==
                    .total ||
                includes(
                    $0.startDate
                )
            }
            .sorted {
                $0.startDate >
                $1.startDate
            }
    }

    private var distanceMeters:
        Double {
        if period == .total {
            return stats?
                .totalRunningDistanceMeters ??
                selectedWorkouts
                    .filter {
                        $0.activity ==
                            .running
                    }
                    .reduce(0.0) {
                        $0 +
                        max(
                            $1.distanceMeters ??
                                0,
                            0
                        )
                    }
        }

        return selectedWorkouts
            .filter {
                $0.activity ==
                    .running
            }
            .reduce(0.0) {
                $0 +
                max(
                    $1.distanceMeters ??
                        0,
                    0
                )
            }
    }

    private var workoutCount: Int {
        if period == .total {
            return stats?
                .totalWorkoutCount ??
                selectedWorkouts.count
        }
        return selectedWorkouts.count
    }

    private var runningCount:
        Int {
        selectedWorkouts
            .filter {
                $0.activity ==
                    .running
            }
            .count
    }

    private var strengthCount:
        Int {
        selectedWorkouts
            .filter {
                $0.activity ==
                    .strength
            }
            .count
    }

    private var walkingCount:
        Int {
        selectedWorkouts
            .filter {
                $0.activity ==
                    .walking ||
                $0.activity ==
                    .hiking
            }
            .count
    }

    private func includes(
        _ date: Date
    ) -> Bool {
        let calendar =
            Calendar.current

        switch period {
        case .week:
            return calendar
                .dateInterval(
                    of: .weekOfYear,
                    for: Date()
                )?
                .contains(date) ??
                false

        case .month:
            return calendar
                .dateInterval(
                    of: .month,
                    for: Date()
                )?
                .contains(date) ??
                false

        case .year:
            return calendar
                .component(
                    .year,
                    from: date
                ) ==
                calendar.component(
                    .year,
                    from: Date()
                )

        case .total:
            return true
        }
    }

    private func activityTitle(
        _ activity:
            WorkoutActivity
    ) -> String {
        switch activity {
        case .running:
            return ATHLTHLocalization.choose(
                english: "Running",
                norwegian: "Løping"
            )
        case .walking:
            return ATHLTHLocalization.choose(
                english: "Walking",
                norwegian: "Gåtur"
            )
        case .hiking:
            return ATHLTHLocalization.choose(
                english: "Hiking",
                norwegian: "Fjelltur"
            )
        case .strength:
            return ATHLTHLocalization.choose(
                english: "Strength",
                norwegian: "Styrke"
            )
        default:
            return ATHLTHLocalization.choose(
                english: "Workout",
                norwegian: "Treningsøkt"
            )
        }
    }

    private func activityIcon(
        _ activity:
            WorkoutActivity
    ) -> String {
        switch activity {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        case .hiking:
            return "figure.hiking"
        case .strength:
            return "dumbbell.fill"
        default:
            return "figure.mixed.cardio"
        }
    }
}

private struct PerformanceMilestonesDetailView:
    View {
    let stats: ProfilePerformanceStats?
    let healthRecords:
        [HealthPersonalRecord]

    @EnvironmentObject private var strengthWorkout:
        StrengthWorkoutStore

    private var records:
        [ProfileFeaturedRecordKind] {
        ProfileFeaturedRecordKind
            .allCases
            .filter {
                $0.displayValue(
                    healthRecords:
                        healthRecords,
                    stats: stats,
                    strengthRecords:
                        strengthWorkout
                            .personalRecords,
                    strengthRepRecords:
                        strengthWorkout
                            .repPersonalRecords
                ) != "—"
            }
            .sorted {
                (recordDate($0) ??
                    .distantPast) >
                (recordDate($1) ??
                    .distantPast)
            }
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.20)
            )

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    headerCard

                    if records.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "No milestones yet",
                                norwegian:
                                    "Ingen milepæler ennå"
                            ),
                            systemImage:
                                "flag",
                            description:
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Your verified records will appear here as you train.",
                                        norwegian:
                                            "Verifiserte rekorder vises her etter hvert som du trener."
                                    )
                                )
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(records) {
                            kind in

                            milestoneCard(
                                kind
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Milestones",
                norwegian: "Milepæler"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private var headerCard:
        some View {
        HStack(spacing: 13) {
            Image(
                systemName:
                    "flag.checkered"
            )
            .font(
                .system(
                    size: 22,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .premiumGold
            )
            .frame(
                width: 54,
                height: 54
            )
            .background(
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Your performance milestones",
                        norwegian:
                            "Dine prestasjonsmilepæler"
                    )
                )
                .font(
                    .system(
                        size: 15,
                        weight: .bold,
                        design: .rounded
                    )
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Built from verified Health records and your training history.",
                        norwegian:
                            "Bygget fra verifiserte Health-rekorder og treningshistorikken din."
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer()
        }
        .padding(16)
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
        )
    }

    private func milestoneCard(
        _ kind:
            ProfileFeaturedRecordKind
    ) -> some View {
        let sourceRecord =
            kind.healthKind.flatMap {
                healthKind in

                healthRecords.first {
                    $0.kind ==
                        healthKind
                }
            }

        return HStack(spacing: 13) {
            Image(
                systemName:
                    kind.icon
            )
            .font(
                .system(
                    size: 17,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                kind.tint
            )
            .frame(
                width: 46,
                height: 46
            )
            .background(
                kind.tint
                    .opacity(0.10),
                in:
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(kind.title)
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )

                Text(
                    kind.displayValue(
                        healthRecords:
                            healthRecords,
                        stats: stats,
                        strengthRecords:
                            strengthWorkout
                                .personalRecords,
                        strengthRepRecords:
                            strengthWorkout
                                .repPersonalRecords
                    )
                )
                .font(
                    .title3
                        .weight(.bold)
                )
                .monospacedDigit()

                HStack(spacing: 5) {
                    Image(
                        systemName:
                            sourceRecord != nil
                            ? "checkmark.seal.fill"
                            : "clock.arrow.circlepath"
                    )

                    Text(
                        sourceRecord != nil
                            ? ATHLTHLocalization
                                .choose(
                                    english:
                                        "Verified from Apple Health",
                                    norwegian:
                                        "Verifisert fra Apple Health"
                                )
                            : ATHLTHLocalization
                                .choose(
                                    english:
                                        "From training history",
                                    norwegian:
                                        "Fra treningshistorikk"
                                )
                    )
                }
                .font(
                    .system(
                        size: 9.5,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    sourceRecord != nil
                        ? ATHLTHTheme
                            .accentDeep
                        : ATHLTHTheme
                            .mutedText
                )
            }

            Spacer()

            if let date =
                    recordDate(kind) {
                Text(
                    date.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }
        }
        .padding(14)
        .background(
            Color.white
                .opacity(0.92),
            in:
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                kind.tint
                    .opacity(0.10),
                lineWidth: 0.8
            )
        }
    }

    private func recordDate(
        _ kind:
            ProfileFeaturedRecordKind
    ) -> Date? {
        if let healthKind =
                kind.healthKind,
           let record =
                healthRecords.first(
                    where: {
                        $0.kind ==
                            healthKind
                    }
                ) {
            return record.date
        }

        switch kind {
        case .fastest1K:
            return stats?
                .fastestOneKilometer?
                .date
        case .fastest5K:
            return stats?
                .fastestFiveKilometers?
                .date
        case .fastestMarathon:
            return stats?
                .fastestMarathon?
                .date
        case .longestRun:
            return stats?
                .longestRunDate
        case .strengthHeaviestSet:
            return strengthWorkout
                .personalRecords
                .filter {
                    $0.kind ==
                        .heaviestSet
                }
                .max {
                    $0.score < $1.score
                }?
                .date
        case .strengthEstimatedOneRM:
            return strengthWorkout
                .personalRecords
                .filter {
                    $0.kind ==
                        .estimatedOneRepMax
                }
                .max {
                    $0.score < $1.score
                }?
                .date
        case .strengthWorkoutVolume:
            return strengthWorkout
                .personalRecords
                .filter {
                    $0.kind ==
                        .workoutVolume
                }
                .max {
                    $0.score < $1.score
                }?
                .date
        case .strengthBestRepPR:
            return strengthWorkout
                .repPersonalRecords
                .max {
                    $0.date < $1.date
                }?
                .date
        default:
            return nil
        }
    }
}

struct ProfileRecordShowcasePickerView:
    View {
    @Environment(\.dismiss) private var dismiss

    let stats: ProfilePerformanceStats?
    var healthRecords:
        [HealthPersonalRecord] = []

    @EnvironmentObject private var health:
        HealthKitManager
    @EnvironmentObject private var strengthWorkout:
        StrengthWorkoutStore
    @State private var fetchedHealthRecords:
        [HealthPersonalRecord] = []
    @AppStorage(ProfileFeaturedRecordKind.storageKey)
    private var featuredRecordSelectionRaw = ""

    private var resolvedHealthRecords:
        [HealthPersonalRecord] {
        healthRecords.isEmpty
            ? fetchedHealthRecords
            : healthRecords
    }

    private var selection:
        [ProfileFeaturedRecordKind] {
        ProfileFeaturedRecordKind
            .decodedSelection(
                from:
                    featuredRecordSelectionRaw
            )
    }

    private var candidates:
        [ProfileFeaturedRecordKind] {
        ProfileFeaturedRecordKind.allCases
    }

    private func candidates(
        for group: ProfileRecordGroup
    ) -> [ProfileFeaturedRecordKind] {
        candidates.filter {
            $0.group == group
        }
    }

    private func recordValue(
        for kind:
            ProfileFeaturedRecordKind
    ) -> String {
        kind.displayValue(
            healthRecords:
                resolvedHealthRecords,
            stats: stats,
            strengthRecords:
                strengthWorkout
                    .personalRecords,
            strengthRepRecords:
                strengthWorkout
                    .repPersonalRecords
        )
    }

    private func isAvailable(
        _ kind:
            ProfileFeaturedRecordKind
    ) -> Bool {
        recordValue(for: kind) != "—"
    }

    var body: some View {
        ZStack {
            ATHLTHPremiumCanvas(
                accent:
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.22)
            )

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    showcaseHero

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        HStack {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "Your profile showcase",
                                        norwegian:
                                            "Din rekordhylle"
                                    )
                                )
                                .font(
                                    .headline
                                        .weight(
                                            .bold
                                        )
                                )

                                Text(
                                    ATHLTHLocalization.choose(
                                        english:
                                            "These are the records visitors see on your profile.",
                                        norwegian:
                                            "Dette er rekordene andre ser på profilen din."
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )
                            }

                            Spacer()

                            Text(
                                "\(selection.count)/\(ProfileFeaturedRecordKind.showcaseLimit)"
                            )
                            .font(
                                .caption
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                            .padding(
                                .horizontal,
                                10
                            )
                            .frame(height: 28)
                            .background(
                                ATHLTHTheme
                                    .accentSoft,
                                in: Capsule()
                            )
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .flexible(),
                                    spacing: 10
                                ),
                                GridItem(
                                    .flexible(),
                                    spacing: 10
                                )
                            ],
                            spacing: 10
                        ) {
                            ForEach(
                                0..<ProfileFeaturedRecordKind
                                    .showcaseLimit,
                                id: \.self
                            ) {
                                index in

                                showcaseSlot(
                                    index
                                )
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        Color.white
                            .opacity(0.90),
                        in:
                            RoundedRectangle(
                                cornerRadius: 24,
                                style:
                                    .continuous
                            )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 24,
                            style:
                                .continuous
                        )
                        .stroke(
                            ATHLTHTheme
                                .border
                                .opacity(
                                    0.60
                                ),
                            lineWidth: 0.8
                        )
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        recordGroupSection(
                            .running
                        )
                        recordGroupSection(
                            .strength
                        )
                        recordGroupSection(
                            .appleHealth
                        )
                    }
                }
                .padding(
                    .horizontal,
                    16
                )
                .padding(.top, 12)
                .padding(
                    .bottom,
                    40
                )
                .frame(maxWidth: 720)
                .frame(
                    maxWidth: .infinity
                )
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(
            ATHLTHLocalization.choose(
                english:
                    "Profile records",
                norwegian:
                    "Rekorder på profil"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .frame(width: 38, height: 38)
                        .background(
                            Color.white.opacity(0.92),
                            in: Circle()
                        )
                        .shadow(
                            color: Color.black.opacity(0.06),
                            radius: 8,
                            y: 3
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Back",
                        norwegian: "Tilbake"
                    )
                )
            }
        }
        .task {
            guard healthRecords
                    .isEmpty,
                  fetchedHealthRecords
                    .isEmpty,
                  health
                    .hasRequestedAuthorization
            else {
                return
            }

            fetchedHealthRecords =
                (
                    try? await health
                        .personalRecords()
                ) ?? []
        }
    }

    private var showcaseHero:
        some View {
        GeometryReader {
            proxy in

            ZStack(
                alignment: .leading
            ) {
                Image("GoalProgress")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width:
                            proxy.size
                                .width,
                        height:
                            proxy.size
                                .height
                    )
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black
                            .opacity(0.72),
                        ATHLTHTheme
                            .accentDeep
                            .opacity(0.54),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "PERSONAL RECORDS",
                            norwegian:
                                "PERSONLIGE REKORDER"
                        ),
                        systemImage:
                            "trophy.fill"
                    )
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .tracking(1.0)
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Build your record showcase",
                            norwegian:
                                "Bygg rekordhyllen din"
                        )
                    )
                    .font(
                        .title2
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        .white
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Choose up to four verified performances that best represent you.",
                            norwegian:
                                "Velg opptil fire verifiserte prestasjoner som best representerer deg."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .white
                            .opacity(0.86)
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .frame(
                        maxWidth:
                            proxy.size
                                .width *
                            0.68,
                        alignment: .leading
                    )
                }
                .padding(18)
            }
        }
        .frame(height: 116)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
        )
        .shadow(
            color:
                Color.black
                    .opacity(0.12),
            radius: 16,
            y: 8
        )
    }

    private func showcaseSlot(
        _ index: Int
    ) -> some View {
        Group {
            if selection.indices
                .contains(index) {
                let kind =
                    selection[index]

                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    HStack {
                        Image(
                            systemName:
                                kind.icon
                        )
                        .font(
                            .system(
                                size: 13,
                                weight:
                                    .semibold
                            )
                        )
                        .foregroundStyle(
                            kind.tint
                        )

                        Spacer()

                        Image(
                            systemName:
                                "checkmark.seal.fill"
                        )
                        .font(
                            .system(
                                size: 11
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .accentDeep
                        )
                    }

                    Text(
                        recordValue(
                            for: kind
                        )
                    )
                    .font(
                        .headline
                            .weight(.bold)
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.72
                    )

                    Text(kind.title)
                        .font(
                            .caption2
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                }
                .padding(10)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 62,
                    alignment: .leading
                )
                .background(
                    LinearGradient(
                        colors: [
                            kind.tint
                                .opacity(
                                    0.12
                                ),
                            Color.white
                                .opacity(
                                    0.88
                                )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    ),
                    in:
                        RoundedRectangle(
                            cornerRadius: 18,
                            style:
                                .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style:
                            .continuous
                    )
                    .stroke(
                        kind.tint
                            .opacity(
                                0.18
                            ),
                        lineWidth: 0.8
                    )
                }
            } else {
                VStack(spacing: 6) {
                    Image(
                        systemName:
                            "plus"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Open slot",
                            norwegian:
                                "Ledig plass"
                        )
                    )
                    .font(
                        .caption2
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 62
                )
                .background(
                    Color.black
                        .opacity(0.025),
                    in:
                        RoundedRectangle(
                            cornerRadius: 18,
                            style:
                                .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style:
                            .continuous
                    )
                    .stroke(
                        ATHLTHTheme
                            .border
                            .opacity(0.65),
                        style:
                            StrokeStyle(
                                lineWidth: 0.8,
                                dash: [
                                    5,
                                    5
                                ]
                            )
                    )
                }
            }
        }
    }


    private func recordGroupSection(
        _ group: ProfileRecordGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack(spacing: 7) {
                Image(
                    systemName:
                        group.icon
                )
                .font(
                    .system(
                        size: 14,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )

                Text(group.title)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )

                Spacer()

                HStack(spacing: 3) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Tap to choose",
                            norwegian: "Trykk for å velge"
                        )
                    )
                    Image(systemName: "chevron.right")
                }
                .font(.caption2)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
            }

            LazyVGrid(
                columns: Array(
                    repeating:
                        GridItem(
                            .flexible(),
                            spacing: 6
                        ),
                    count: 4
                ),
                spacing: 6
            ) {
                ForEach(
                    candidates(
                        for: group
                    )
                ) { kind in
                    showcaseCard(kind)
                }
            }
        }
        .padding(8)
        .background(
            Color.white.opacity(0.88),
            in: RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme.border
                    .opacity(0.55),
                lineWidth: 0.8
            )
        }
    }

    private func showcaseCard(
        _ kind:
            ProfileFeaturedRecordKind
    ) -> some View {
        let isSelected =
            selection.contains(kind)
        let selectionIsFull =
            selection.count >=
                ProfileFeaturedRecordKind
                    .showcaseLimit
        let available =
            isAvailable(kind)

        return Button {
            toggle(kind)
        } label: {
            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                HStack {
                    Image(
                        systemName:
                            kind.icon
                    )
                    .font(
                        .system(
                            size: 10,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        kind.tint
                    )
                    .frame(
                        width: 24,
                        height: 24
                    )
                    .background(
                        kind.tint
                            .opacity(0.10),
                        in:
                            RoundedRectangle(
                                cornerRadius: 12,
                                style:
                                    .continuous
                            )
                    )

                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(
                                isSelected
                                    ? kind.tint
                                    : ATHLTHTheme
                                        .border,
                                lineWidth:
                                    isSelected
                                    ? 0
                                    : 1.2
                            )
                            .frame(
                                width: 16,
                                height: 16
                            )

                        if isSelected {
                            Circle()
                                .fill(
                                    ATHLTHTheme
                                        .accentDeep
                                )
                                .frame(
                                    width: 19,
                                    height: 19
                                )

                            Image(
                                systemName:
                                    "checkmark"
                            )
                            .font(
                                .system(
                                    size: 8,
                                    weight:
                                        .bold
                                )
                            )
                            .foregroundStyle(
                                .white
                            )
                        }
                    }
                }

                Text(kind.title)
                    .font(
                        .system(
                            size: 8.2,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(2)
                    .minimumScaleFactor(
                        0.72
                    )

                Text(
                    recordValue(
                        for: kind
                    )
                )
                .font(
                    .system(
                        size: 12,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.68
                )

                Label(
                    isSelected
                        ? ATHLTHLocalization
                            .choose(
                                english:
                                    "Shown on profile",
                                norwegian:
                                    "Vises på profil"
                            )
                        : ATHLTHLocalization
                            .choose(
                                english:
                                    available ? "Available" : "Not recorded",
                                norwegian:
                                    available ? "Tilgjengelig" : "Ikke registrert"
                            ),
                    systemImage:
                        isSelected
                        ? "checkmark.seal.fill"
                        : "plus.circle"
                )
                .font(
                    .system(
                        size: 6.1,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    isSelected
                        ? ATHLTHTheme
                            .accentDeep
                        : ATHLTHTheme
                            .mutedText
                )
            }
            .padding(6)
            .frame(
                maxWidth: .infinity,
                minHeight: 64,
                alignment: .topLeading
            )
            .background(
                LinearGradient(
                    colors: [
                        isSelected
                            ? kind.tint
                                .opacity(
                                    0.10
                                )
                            : Color.white
                                .opacity(
                                    0.92
                                ),
                        Color.white
                            .opacity(0.86)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
                in:
                    RoundedRectangle(
                        cornerRadius: 12,
                        style:
                            .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 13,
                    style:
                        .continuous
                )
                .stroke(
                    isSelected
                        ? ATHLTHTheme
                            .premiumGold
                            .opacity(
                                0.30
                            )
                        : ATHLTHTheme
                            .border
                            .opacity(
                                0.55
                            ),
                    lineWidth:
                        isSelected
                        ? 1.2
                        : 0.8
                )
            }
            .shadow(
                color:
                    Color.black
                        .opacity(
                            isSelected
                            ? 0.045
                            : 0.02
                        ),
                radius: 9,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(
            (
                !available &&
                !isSelected
            ) ||
            (
                !isSelected &&
                selectionIsFull
            )
        )
        .opacity(
            !available
                ? 0.42
                : (
                    !isSelected &&
                    selectionIsFull
                        ? 0.42
                        : 1
                )
        )
    }

    private func toggle(
        _ kind:
            ProfileFeaturedRecordKind
    ) {
        var updated = selection

        if let index =
            updated.firstIndex(
                of: kind
            ) {
            updated.remove(
                at: index
            )
        } else {
            guard updated.count <
                    ProfileFeaturedRecordKind
                        .showcaseLimit
            else {
                return
            }

            updated.append(kind)
        }

        featuredRecordSelectionRaw =
            ProfileFeaturedRecordKind
                .encodedSelection(updated)
    }
}

private struct PerformanceMetricItem {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color
}

private func formatDistance(_ meters: Double?) -> String {
    guard let meters, meters > 0 else { return "—" }

    let kilometers = meters / 1_000

    if kilometers >= 1_000 {
        return String(format: "%.0f km", kilometers)
    }

    if kilometers >= 100 {
        return String(format: "%.1f km", kilometers)
    }

    return String(format: "%.2f km", kilometers)
}

private func formatMil(_ meters: Double?) -> String {
    guard let meters, meters >= 10_000 else {
        return ATHLTHLocalization.choose(
            english: "Distance verified",
            norwegian: "Distanse verifisert"
        )
    }

    return String(format: "%.2f mil", meters / 10_000)
}

private func formatDuration(_ duration: TimeInterval?) -> String {
    guard let duration, duration > 0 else { return "—" }

    let totalMinutes = Int((duration / 60).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 {
        return ATHLTHLocalization.isNorwegian
            ? "\(hours)t \(minutes)m"
            : "\(hours)h \(minutes)m"
    }

    return "\(minutes) min"
}

private func formatLongDuration(_ duration: TimeInterval) -> String {
    guard duration > 0 else { return "—" }

    let totalMinutes = Int((duration / 60).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours >= 100 {
        return "\(hours) h"
    }

    if hours > 0 {
        return ATHLTHLocalization.isNorwegian
            ? "\(hours)t \(minutes)m"
            : "\(hours)h \(minutes)m"
    }

    return "\(minutes) min"
}
