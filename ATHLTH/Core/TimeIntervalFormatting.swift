import Foundation

extension TimeInterval {
    var shortDuration: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0
            ? "\(hours)h \(minutes)m"
            : "\(minutes)m"
    }
}
