import Foundation

/// A complimentary grant is a system message, not a social interaction.
/// Both the app inbox and push notifications localize the same server-owned
/// canonical text; clients never infer entitlement from the notification.
enum ATHLTHPlusGrantNotificationCopy {
    static let eventKind = "athlth_plus_granted"

    static func title(norwegian: Bool) -> String {
        norwegian ? "Du har fått ATHLTH+" : "ATHLTH+ granted"
    }

    static func message(_ canonical: String, norwegian: Bool) -> String {
        guard norwegian else { return canonical }
        if canonical == "You have received ATHLTH+ with no end date." {
            return "Du har fått ATHLTH+ uten sluttdato."
        }

        let prefix = "You have received ATHLTH+ for "
        let divider = " days. Valid until "
        guard let prefixRange = canonical.range(of: prefix, options: .anchored),
              let range = canonical.range(of: divider),
              prefixRange.upperBound <= range.lowerBound,
              canonical.hasSuffix(" UTC.") else {
            return canonical
        }

        let days = String(canonical[prefixRange.upperBound..<range.lowerBound])
        guard let dayCount = Int(days), [7, 30, 90, 365].contains(dayCount)
        else { return canonical }
        let expiry = String(canonical[range.upperBound...].dropLast(5))
        // Parse and display UTC deliberately: a midnight conversion to local
        // time could make the gifted entitlement look one day shorter.
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        let displayExpiry: String
        if let date = parser.date(from: expiry) {
            let display = DateFormatter()
            display.locale = Locale(identifier: "nb_NO")
            display.timeZone = TimeZone(secondsFromGMT: 0)
            display.dateFormat = "d. MMMM yyyy 'kl.' HH:mm"
            displayExpiry = display.string(from: date)
        } else {
            displayExpiry = expiry
        }
        return "Du har fått ATHLTH+ i \(dayCount) dager. Tilgangen varer til \(displayExpiry) UTC."
    }
}
