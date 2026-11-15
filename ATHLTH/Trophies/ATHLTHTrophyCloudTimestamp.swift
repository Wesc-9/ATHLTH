import Foundation

/// The trophy Edge Function validates timestamps with JavaScript Date.
/// Send explicit RFC3339 strings rather than relying on the SDK's
/// version-specific Foundation Date encoder.
enum ATHLTHTrophyCloudTimestamp {
    static func encode(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
