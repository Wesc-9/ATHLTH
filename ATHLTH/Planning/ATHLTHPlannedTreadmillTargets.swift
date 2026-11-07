import Foundation

/// Presentation-only choices. All three modes persist the same seconds/km.
enum ATHLTHTreadmillInputMode: String, CaseIterable, Identifiable {
    case treadmill, speed, pace
    var id: String { rawValue }
    func title(measurement: MeasurementPreference) -> String {
        switch self {
        case .treadmill:
            return ATHLTHLocalization.choose(
                english: "Treadmill tempo", norwegian: "Mølletempo")
        case .speed: return measurement.runningSpeedUnit
        case .pace: return measurement.runningPaceUnit
        }
    }
}

/// Conversion is shared by speed and pace inputs: both persist as seconds/km.
enum ATHLTHPlannedTreadmillTargets {
    static let kilometersPerMile = 1.609344
    static func displaySpeed(_ kmh: Double, measurement: MeasurementPreference) -> Double {
        measurement == .metric ? kmh : kmh / kilometersPerMile
    }
    static func canonicalSpeed(_ speed: Double, measurement: MeasurementPreference) -> Double {
        measurement == .metric ? speed : speed * kilometersPerMile
    }
    static func displayPace(_ secondsPerKm: Double, measurement: MeasurementPreference) -> Double {
        measurement == .metric ? secondsPerKm : secondsPerKm * kilometersPerMile
    }
    static func canonicalPace(_ secondsPerDisplayUnit: Double, measurement: MeasurementPreference) -> Double {
        measurement == .metric ? secondsPerDisplayUnit : secondsPerDisplayUnit / kilometersPerMile
    }

    static func pace(forSpeed kilometersPerHour: Double) -> Double {
        3_600 / min(max(kilometersPerHour, 1), 25)
    }

    static func speed(forPace secondsPerKilometer: Double) -> Double {
        min(max(3_600 / max(secondsPerKilometer, 1), 1), 25)
    }
}
