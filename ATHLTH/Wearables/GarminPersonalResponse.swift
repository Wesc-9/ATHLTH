import Foundation

/// Decode only the fields needed for the private, read-only preview.
struct GarminPersonalActivityResponse: Decodable {
    struct ActivityType: Decodable { let typeKey: String? }
    let activityId: Int64
    let activityType: ActivityType?
    let startTimeGMT: String
    let duration: Double
    let elapsedDuration: Double?
    let distance: Double?
    let calories: Double?
    let averageHR: Double?
    let maxHR: Double?

    func normalized() throws -> GarminImportedActivity {
        guard activityId > 0, let start = Self.utcDate(startTimeGMT) else {
            throw GarminImportError.invalidActivity
        }
        return try GarminImportNormalizer.activity(.init(
            activityID: String(activityId), activityType: activityType?.typeKey ?? "unknown",
            deviceModel: nil, startedAt: start, elapsedSeconds: elapsedDuration,
            durationSeconds: duration, distanceMeters: distance,
            // Total activity calories are not necessarily active calories.
            activeEnergyKilocalories: nil, averageHeartRate: averageHR, maximumHeartRate: maxHR
        ))
    }

    private static func utcDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS",
                       "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

struct GarminPersonalSteps: Decodable {
    let calendarDate: String
    let totalSteps: Int?
}

struct GarminPersonalSleep: Decodable {
    let sleepTimeSeconds: Double?
    let deepSleepSeconds: Double?
    let lightSleepSeconds: Double?
    let remSleepSeconds: Double?
}

struct GarminPersonalHeart: Decodable {
    let restingHeartRate: Double?
}

struct GarminPersonalHRV: Decodable {
    struct Summary: Decodable { let lastNightAvg: Double? }
    let hrvSummary: Summary?
}

struct GarminPersonalDailySummary: Decodable {
    struct Day: Decodable {
        let calendarDate: String?
        let averageStressLevel: Double?
        let bodyBatteryHighestValue: Double?
        let bodyBatteryLowestValue: Double?
    }
    let data: [Day]
}
