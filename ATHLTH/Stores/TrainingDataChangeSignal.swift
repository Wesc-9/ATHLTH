import Foundation

extension Notification.Name {
    static let athlthTrainingDataDidChange =
        Notification.Name("athlth.trainingDataDidChange")
}

enum ATHLTHTrainingDataChangeSignal {
    static func post(userID: UUID) {
        NotificationCenter.default.post(
            name: .athlthTrainingDataDidChange,
            object: userID
        )
    }
}
