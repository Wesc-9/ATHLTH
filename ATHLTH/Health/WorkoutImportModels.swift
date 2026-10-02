import Foundation

struct PendingWorkoutImport: Identifiable, Hashable {
    let summary: WorkoutSummary
    let sourceName: String
    let deviceName: String?

    var id: UUID { summary.id }

    var sourceDescription: String {
        if let deviceName,
           !deviceName.isEmpty,
           deviceName.caseInsensitiveCompare(sourceName) != .orderedSame {
            return "\(sourceName) · \(deviceName)"
        }

        return sourceName
    }
}
