import Foundation

/// One competition uses one scoring discipline regardless of whether the
/// competition is a duel, single event, league or knockout cup.
enum ATHLTHCompetitionDiscipline: String, Codable, CaseIterable, Identifiable {
    case sprint, workout, distance, duration, laps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sprint: return "Sprint"
        case .workout: return "Treningsøkt"
        case .distance: return "Distanse"
        case .duration: return "Tid"
        case .laps: return "Runder"
        }
    }
}

enum ATHLTHCompetitionSprintMode: String, Codable, CaseIterable, Identifiable {
    case massStart = "mass_start", relay, staggered
    var id: String { rawValue }
    var title: String {
        switch self {
        case .massStart: return "Fellesstart"
        case .relay: return "Lagsprint"
        case .staggered: return "Hver sin tur"
        }
    }
}

enum ATHLTHCompetitionSprintTarget: String, Codable, CaseIterable, Identifiable {
    case distance, duration, route
    var id: String { rawValue }
    var title: String {
        switch self {
        case .distance: return "Distanse"
        case .duration: return "Tid"
        case .route: return "Rute"
        }
    }
}

/// Requirement is a rule, not a user-editable assertion of device provenance.
/// Recording origin must be checked against source-workout metadata on server.
enum ATHLTHCompetitionRecordingDevice: String, Codable, CaseIterable, Identifiable {
    case any, appleWatch = "apple_watch", iphone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: return "Alle godkjente registreringsenheter"
        case .appleWatch: return "Apple Watch er påkrevd"
        case .iphone: return "iPhone med ATHLTH"
        }
    }
}

enum ATHLTHCompetitionLapVerification: String, Codable, CaseIterable, Identifiable {
    case gps, supervised
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gps: return "Felles målpunkt · GPS-passering"
        case .supervised: return "Passering bekreftes av arrangør"
        }
    }
}

struct ATHLTHCompetitionRaceRules: Codable, Equatable {
    var discipline: ATHLTHCompetitionDiscipline = .workout
    var sprintMode: ATHLTHCompetitionSprintMode = .massStart
    var sprintTarget: ATHLTHCompetitionSprintTarget = .distance
    var routeID: UUID? = nil
    var routeName: String = ""
    var recordingDevice: ATHLTHCompetitionRecordingDevice = .any
    var targetDistanceMeters: Int = 100
    var targetDurationSeconds: Int = 60
    var lapCount: Int = 3
    /// A lap can be used without knowing its length. All athletes must run
    /// the same course. It does not imply a measured distance.
    var lapVerification: ATHLTHCompetitionLapVerification = .gps
    var lapCourseName: String = ""
    var lapCourseLatitude: Double? = nil
    var lapCourseLongitude: Double? = nil
    var countdownSeconds: Int = 10
    var allowOptInLiveLocation: Bool = false
    /// Explicitly listed permitted equipment, e.g. shoes or gym apparatus.
    /// This does not substitute for device-source verification.
    var equipmentRules: String = ""

    var isValid: Bool {
        guard (100...100_000).contains(targetDistanceMeters),
              (10...86_400).contains(targetDurationSeconds),
              (1...500).contains(lapCount),
              (5...30).contains(countdownSeconds),
              lapCourseName.count <= 120,
              routeName.count <= 120,
              equipmentRules.count <= 350,
              (lapCourseLatitude == nil && lapCourseLongitude == nil) ||
              (lapCourseLatitude.map { (-90...90).contains($0) } == true &&
               lapCourseLongitude.map { (-180...180).contains($0) } == true)
        else { return false }
        if discipline == .sprint && sprintTarget == .route && routeID == nil {
            return false
        }
        return discipline != .laps ||
            !lapCourseName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
