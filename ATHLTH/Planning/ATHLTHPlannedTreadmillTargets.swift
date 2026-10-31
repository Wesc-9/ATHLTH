import Foundation

/// Conversion is shared by speed and pace inputs: both persist as seconds/km.
enum ATHLTHPlannedTreadmillTargets {
    static func pace(forSpeed kilometersPerHour: Double) -> Double {
        3_600 / min(max(kilometersPerHour, 1), 25)
    }

    static func speed(forPace secondsPerKilometer: Double) -> Double {
        min(max(3_600 / max(secondsPerKilometer, 1), 1), 25)
    }
}
