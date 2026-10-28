import Foundation

/// What an athlete actually selected after a GPS-stationary suggestion.
/// The existing iPhone treadmill capture mode is reused for indoor runs,
/// while this value prevents labelling indoor tracks as treadmills.
enum ATHLTHIndoorRunVenue: String, Codable, CaseIterable, Identifiable {
    case treadmill
    case indoorTrack
    case otherIndoor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .treadmill:
            return ATHLTHLocalization.choose(english: "Treadmill", norwegian: "Tredemølle")
        case .indoorTrack:
            return ATHLTHLocalization.choose(english: "Indoor running track", norwegian: "Innendørs løpebane")
        case .otherIndoor:
            return ATHLTHLocalization.choose(english: "Other indoor training", norwegian: "Annen innendørstrening")
        }
    }

    var detail: String {
        switch self {
        case .treadmill:
            return ATHLTHLocalization.choose(
                english: "Enter belt speed to calculate distance",
                norwegian: "Registrer møllehastighet for å beregne distanse"
            )
        case .indoorTrack:
            return ATHLTHLocalization.choose(
                english: "Keep time and steps; distance needs a separate reliable source",
                norwegian: "Behold tid og øktdeler; distanse trenger en egen pålitelig kilde"
            )
        case .otherIndoor:
            return ATHLTHLocalization.choose(
                english: "Continue without a GPS route or invented distance",
                norwegian: "Fortsett uten GPS-rute eller antatt distanse"
            )
        }
    }

    var symbol: String {
        switch self {
        case .treadmill: return "figure.run.treadmill"
        case .indoorTrack: return "figure.run"
        case .otherIndoor: return "figure.indoor.cycle"
        }
    }
}

/// Conservative, deterministic prompt policy. Running loops outdoors should
/// not be interpreted as stillness from end-to-start displacement alone.
/// Distance is the accumulated *accepted* GPS distance, not straight-line
/// displacement. A missing GPS signal is not proof of indoor training.
enum ATHLTHIndoorRunDetection {
    static let minimumElapsed: TimeInterval = 15 * 60
    static let maximumDistanceMeters: Double = 100

    static func shouldOffer(
        elapsedWallSeconds: TimeInterval,
        acceptedDistanceMeters: Double,
        firstReliableFix: Date?,
        lastReliableFix: Date?,
        acceptedFixCount: Int,
        now: Date,
        isOutdoor: Bool,
        manualPause: Bool,
        hasPlannedRouteOrGhost: Bool,
        alreadyPrompted: Bool
    ) -> Bool {
        guard isOutdoor, !manualPause, !hasPlannedRouteOrGhost, !alreadyPrompted,
              elapsedWallSeconds >= minimumElapsed,
              acceptedDistanceMeters.isFinite,
              (0..<maximumDistanceMeters).contains(acceptedDistanceMeters),
              acceptedFixCount >= 3,
              let firstReliableFix, let lastReliableFix,
              lastReliableFix >= firstReliableFix,
              now.timeIntervalSince(lastReliableFix) <= 120,
              lastReliableFix.timeIntervalSince(firstReliableFix) >= 12 * 60
        else { return false }
        return true
    }
}
