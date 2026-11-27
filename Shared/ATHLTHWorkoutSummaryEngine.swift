import Foundation

/// Device-independent, read-only result metrics. The recorder remains the
/// owner of the saved workout; this engine never writes HealthKit or creates
/// another workout. Missing measurements stay missing.
struct ATHLTHWorkoutSummaryEngine: Equatable {
    let durationSeconds: Double?
    let distanceMeters: Double?
    let activeCalories: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
    let paceSecondsPerKilometer: Double?
    let speedKilometersPerHour: Double?
    let rowingSplitSeconds: Double?
    let completedSets: Int?

    init(duration: Double, distanceMeters: Double? = nil,
         activeCalories: Double? = nil, averageHeartRate: Double? = nil,
         maximumHeartRate: Double? = nil, activity: String,
         completedSets: Int? = nil) {
        let sport = activity.lowercased().filter { $0.isLetter || $0.isNumber }
        let foot = ["running", "walking", "treadmill", "hiking"].contains(sport)
        let cycling = ["cycling", "bicycle"].contains(sport)
        let rowing = ["rowing", "row"].contains(sport)
        let sports = ["sports", "play"].contains(sport)
        self.durationSeconds = Self.nonnegative(duration)
        let meters = (foot || cycling || rowing || sports) ? Self.positive(distanceMeters) : nil
        self.distanceMeters = meters
        self.activeCalories = Self.positive(activeCalories)
        self.averageHeartRate = Self.positive(averageHeartRate)
        self.maximumHeartRate = Self.positive(maximumHeartRate)
        self.completedSets = sport == "strength" ? completedSets.flatMap { $0 >= 0 ? $0 : nil } : nil
        if let meters, let seconds = Self.positive(duration) {
            let pace = seconds / (meters / 1000)
            self.paceSecondsPerKilometer = foot ? Self.positive(pace) : nil
            self.speedKilometersPerHour = (foot || cycling || sports) ? Self.positive(meters / seconds * 3.6) : nil
            self.rowingSplitSeconds = rowing ? Self.positive(seconds * 500 / meters) : nil
        } else {
            self.paceSecondsPerKilometer = nil
            self.speedKilometersPerHour = nil
            self.rowingSplitSeconds = nil
        }
    }

    static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func roundedInteger(_ value: Double?) -> Int? {
        guard let value = nonnegative(value) else { return nil }
        return Int(exactly: value.rounded())
    }

    static func durationText(_ seconds: Double?) -> String {
        guard let total = roundedInteger(seconds) else { return "—" }
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func distanceText(_ meters: Double?) -> String {
        guard let meters = positive(meters) else { return "—" }
        return String(format: "%.2f km", meters / 1000)
    }

    static func paceText(_ seconds: Double?) -> String {
        guard let seconds = positive(seconds), let total = roundedInteger(seconds), total > 0 else { return "—" }
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }

    static func speedText(_ speed: Double?) -> String {
        guard let speed = positive(speed) else { return "—" }
        return String(format: "%.1f km/t", speed)
    }

    static func pulseText(_ bpm: Double?) -> String {
        guard let bpm = positive(bpm), let value = roundedInteger(bpm) else { return "—" }
        return "\(value) bpm"
    }

    static func calorieText(_ calories: Double?) -> String {
        guard let calories = positive(calories), let value = roundedInteger(calories) else { return "—" }
        return "\(value) kcal"
    }

    var durationText: String { Self.durationText(durationSeconds) }
    var distanceText: String { Self.distanceText(distanceMeters) }
    var paceText: String { Self.paceText(paceSecondsPerKilometer) }
    var speedText: String { Self.speedText(speedKilometersPerHour) }
    var averagePulseText: String { Self.pulseText(averageHeartRate) }
    var maximumPulseText: String { Self.pulseText(maximumHeartRate) }
    var calorieText: String { Self.calorieText(activeCalories) }
}
