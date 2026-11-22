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
        // The backend states UTC explicitly. Do not reinterpret a UTC expiry
        // as a local midnight, which could shorten the user's actual grant.
        return "Du har fått ATHLTH+ i \(dayCount) dager. Tilgangen varer til \(expiry) UTC."
    }
}
