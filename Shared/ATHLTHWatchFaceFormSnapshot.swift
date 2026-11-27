import Foundation

/// Minimal on-device projection for Watch complications. No health samples,
/// account identifier, advice or workout history is shared with the widget.
struct ATHLTHWatchFaceFormSnapshot: Codable, Equatable {
    static let suite = "group.com.wesc9.athlth"
    static let key = "athlth.watch.face.form.v1"
    static let widgetKind = "ATHLTHDailyFormWatchWidget"

    let score: Int
    let updatedAt: Date

    func currentScore(at date: Date, calendar: Calendar = .current) -> Int? {
        guard (0...100).contains(score), updatedAt <= date,
              calendar.isDate(updatedAt, inSameDayAs: date) else { return nil }
        return score
    }

    static func nextDay(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.dateInterval(of: .day, for: date)?.end
    }

    static func read(from defaults: UserDefaults?) -> Self? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Only reload WidgetKit when the source projection actually changes.
    @discardableResult
    static func write(_ snapshot: Self?, to defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        if let snapshot {
            guard read(from: defaults) != snapshot,
                  let data = try? JSONEncoder().encode(snapshot) else { return false }
            defaults.set(data, forKey: key)
        } else {
            guard defaults.object(forKey: key) != nil else { return false }
            defaults.removeObject(forKey: key)
        }
        return true
    }
}
