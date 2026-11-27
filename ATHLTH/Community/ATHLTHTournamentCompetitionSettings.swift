import Foundation

/// Shared safe settings for competition creation and future seasons.
/// Old locally saved drafts decode with conservative defaults.
enum ATHLTHCompetitionUnlock: String, Codable, CaseIterable, Identifiable {
    case interval
    case everyoneFinished = "everyone_finished"
    case allAtStart = "all_at_start"
    var id: String { rawValue }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "everyoneFinished" { self = .everyoneFinished; return }
        guard let value = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown competition progression")
        }
        self = value
    }
    var title: String {
        switch self {
        case .interval: return "Etter valgt tidsrom"
        case .everyoneFinished: return "Når alle har gjennomført"
        case .allAtStart: return "Alle øvelser tilgjengelig fra start"
        }
    }
}

enum ATHLTHCompetitionIntervalUnit: String, Codable, CaseIterable, Identifiable {
    case minute, hour, day, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .minute: return "Minutt"
        case .hour: return "Time"
        case .day: return "Dag"
        case .month: return "Måned"
        }
    }
    /// Calendar months must be evaluated by the server as calendar
    /// intervals, never approximated as a fixed 30-day duration.
    var maximumCount: Int {
        switch self {
        case .minute: return 10_080
        case .hour: return 720
        case .day: return 90
        case .month: return 12
        }
    }
}

enum ATHLTHCompetitionInvitePermission: String, Codable, CaseIterable, Identifiable {
    case admin, participants
    var id: String { rawValue }
    var title: String {
        self == .admin ? "Kun arrangør" : "Alle godkjente deltakere"
    }
}

enum ATHLTHCompetitionJoinApproval: String, Codable, CaseIterable, Identifiable {
    case open, participants, admin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: return "Åpen – ingen ekstra godkjenning"
        case .participants: return "Alle deltakere må godkjenne"
        case .admin: return "Kun arrangøren godkjenner"
        }
    }
}

/// Rewards and penalties are a voluntary social agreement, not transfers,
/// obligations or automated punishments. Participants must acknowledge them
/// together with the final competition rules before any workout counts.
struct ATHLTHCompetitionAgreement: Codable, Equatable {
    var allowed: String = ""
    var prohibited: String = ""
    var firstPrize: String = ""
    var secondPrize: String = ""
    var thirdPrize: String = ""
    var loserConsequence: String = ""

    var hasTerms: Bool {
        [allowed, prohibited, firstPrize, secondPrize,
         thirdPrize, loserConsequence].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    var isValid: Bool {
        [allowed, prohibited, firstPrize, secondPrize,
         thirdPrize, loserConsequence].allSatisfy { $0.count <= 500 }
    }
}

enum ATHLTHCompetitionStartMode: String, Codable, CaseIterable, Identifiable {
    case manual, whenReady = "when_ready", scheduled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: return "Arrangøren starter når alle er klare"
        case .whenReady: return "Automatisk når alle er klare"
        case .scheduled: return "Til valgt dato og klokkeslett"
        }
    }
}

enum ATHLTHCompetitionEnvironment: String, Codable, CaseIterable, Identifiable {
    case any, outdoor, indoor, treadmill, gym
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: return "Ingen begrensning"
        case .outdoor: return "Kun utendørs"
        case .indoor: return "Kun innendørs"
        case .treadmill: return "Kun tredemølle"
        case .gym: return "Kun treningssenter"
        }
    }

    var detail: String {
        switch self {
        case .any: return "Alle treningsmiljøer er tillatt. Inne- og uteøkter kan ha ulik målenøyaktighet."
        case .outdoor: return "Utendørsaktivitet med GPS der det er relevant. Registrert utendørstype alene er ikke GPS-bevis."
        case .indoor: return "Innendørsaktivitet uten krav til GPS. Målingen baseres på den opprinnelige økten og tilgjengelige sensorer."
        case .treadmill: return "Bruk innendørs løpe- eller gåmodus på tredemølle. Hastighet, distanse, tid og stigning erstatter GPS-rute; manuelt angitte verdier må ikke kalles sensormålinger."
        case .gym: return "Treningssenter krever bekreftelse av sted. En styrkeøkt alene beviser ikke at den er utført på et treningssenter."
        }
    }

    /// The current server competition RPC only accepts these three values.
    var canPublish: Bool { self == .any || self == .outdoor || self == .gym }

    func supports(_ activities: Set<ATHLTHTournamentActivity>) -> Bool {
        !activities.isEmpty && activities.allSatisfy { activity in
            switch self {
            case .any, .outdoor: return true
            case .indoor, .gym: return activity != .hiking
            case .treadmill: return activity == .running || activity == .walking
            }
        }
    }

    /// A child can narrow a parent, never relax it or contradict it.
    func permits(_ child: Self) -> Bool {
        if self == .any || self == child { return true }
        return self == .indoor && (child == .treadmill || child == .gym)
    }

    /// Keep the existing server contract in addition to local compatibility.
    func canPublish(for activities: Set<ATHLTHTournamentActivity>) -> Bool {
        guard canPublish, supports(activities) else { return false }
        switch self {
        case .outdoor: return activities.contains(.running) || activities.contains(.walking) || activities.contains(.hiking)
        case .gym: return activities.contains(.strength)
        default: return true
        }
    }

    func supports(_ race: ATHLTHCompetitionRaceRules) -> Bool {
        if self == .indoor || self == .treadmill || self == .gym {
            if race.discipline == .laps && race.lapVerification == .gps { return false }
            if race.discipline == .sprint && race.sprintTarget == .route { return false }
            if self == .treadmill && race.discipline == .laps { return false }
            if race.allowOptInLiveLocation { return false }
        }
        return true
    }
}

enum ATHLTHCompetitionUnansweredPolicy: String, Codable, CaseIterable, Identifiable {
    case cancel, `continue`, replace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cancel: return "Avlys når svarfristen utløper"
        case .continue: return "Start uten dem som ikke har godtatt"
        case .replace: return "Gi mer tid til å finne en erstatter"
        }
    }
}

struct ATHLTHTournamentCompetitionSettings: Codable, Equatable {
    var startsAt: Date? = nil
    var endsAt: Date? = nil
    var startMode: ATHLTHCompetitionStartMode = .manual
    var environment: ATHLTHCompetitionEnvironment = .any
    /// Stable keys are activity raw values and library/template UUIDs.
    /// Absence means inherit; explicit `any` cannot relax a restricted parent.
    var activityEnvironments: [String: ATHLTHCompetitionEnvironment] = [:]
    var exerciseEnvironments: [UUID: ATHLTHCompetitionEnvironment] = [:]

    func effectiveEnvironment(activity: ATHLTHTournamentActivity, exerciseID: UUID? = nil) -> ATHLTHCompetitionEnvironment {
        if let exerciseID, let specific = exerciseEnvironments[exerciseID] { return specific }
        return activityEnvironments[activity.rawValue] ?? environment
    }

    func allowedEnvironments(activity: ATHLTHTournamentActivity, exerciseID: UUID? = nil) -> [ATHLTHCompetitionEnvironment] {
        let parent = exerciseID == nil ? environment : effectiveEnvironment(activity: activity)
        return ATHLTHCompetitionEnvironment.allCases.filter {
            parent.permits($0) && $0.supports(Set([activity])) && $0.supports(race)
        }
    }

    /// Never silently ignore stale overrides, unknown activities or an
    /// exercise whose real catalog activity has not yet been resolved.
    func environmentsValid(activities: Set<ATHLTHTournamentActivity>,
                           exerciseActivities: [UUID: ATHLTHTournamentActivity]) -> Bool {
        guard environment.supports(activities), environment.supports(race),
              activityEnvironments.allSatisfy({ key, value in
                  guard let activity = ATHLTHTournamentActivity(rawValue: key), activities.contains(activity) else { return false }
                  return allowedEnvironments(activity: activity).contains(value)
              }) else { return false }
        let selected = Set(selectedExerciseIDs ?? [])
        return exerciseEnvironments.allSatisfy { id, value in
            guard selected.contains(id), let activity = exerciseActivities[id],
                  activities.contains(activity) else { return false }
            return allowedEnvironments(activity: activity, exerciseID: id).contains(value)
        }
    }

    /// Hierarchical rules may be saved as recipes, but must never be
    /// published with a server that would discard their restrictions.
    func environmentsCanPublish(activities: Set<ATHLTHTournamentActivity>) -> Bool {
        activityEnvironments.isEmpty && exerciseEnvironments.isEmpty && environment.canPublish(for: activities)
    }

    // Preserve the server's existing meeting_place contract. The optional
    // split fields retain editable address and instructions in local drafts.
    var meetingPlace: String = ""
    var meetingAddress: String? = nil
    var meetingDescription: String? = nil

    var hasMeetingPoint: Bool {
        !meetingPlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (meetingLat != nil && meetingLon != nil)
    }

    var meetingDisplayAddress: String {
        let address = (meetingAddress ?? meetingPlace).trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? "Valgt punkt på kart" : address
    }

    var meetingDisplayDescription: String? {
        let value = (meetingDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func combinedMeetingPlace(address: String, description: String) -> String {
        [address, description].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    mutating func setMeetingPoint(address: String, description: String,
                                  latitude: Double?, longitude: Double?) {
        meetingAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingPlace = Self.combinedMeetingPlace(address: address, description: description)
        meetingLat = latitude
        meetingLon = longitude
    }
    var meetingLat: Double? = nil
    var meetingLon: Double? = nil
    var coachExerciseIDs: [UUID] = []
    var selectedExerciseIDs: [UUID]? = nil
    var race: ATHLTHCompetitionRaceRules = .init()
    var invitationDays: Int = 3
    var unansweredPolicy: ATHLTHCompetitionUnansweredPolicy = .cancel
    var allowFeedPost: Bool = true
    var unlock: ATHLTHCompetitionUnlock = .interval
    var every: Int = 7
    var unit: ATHLTHCompetitionIntervalUnit = .day
    var completionHours: Int = 48
    var invitationPermission: ATHLTHCompetitionInvitePermission = .admin
    var joinApproval: ATHLTHCompetitionJoinApproval = .admin
    var agreement: ATHLTHCompetitionAgreement = .init()

    var isValid: Bool {
        let now = Date()
        let validStart = startsAt.map {
            $0 >= now.addingTimeInterval(-120) &&
            $0 <= now.addingTimeInterval(366 * 86_400)
        } ?? true
        let validVenue = meetingPlace.count <= 240 &&
            ((meetingLat == nil && meetingLon == nil) ||
             (meetingLat.map { (-90...90).contains($0) } == true &&
              meetingLon.map { (-180...180).contains($0) } == true))
        let validEnd = endsAt.map { $0 > max(now, startsAt ?? now) && $0 <= now.addingTimeInterval(366 * 86_400) } ?? true
        return validStart && validEnd && validVenue && race.isValid && environment.supports(race) &&
            activityEnvironments.count <= ATHLTHTournamentActivity.allCases.count &&
            exerciseEnvironments.count <= 12 &&
            Set(exerciseEnvironments.keys).isSubset(of: Set(selectedExerciseIDs ?? [])) &&
            (1...30).contains(invitationDays) &&
            race.plannedMeasures.count + (selectedExerciseIDs?.count ?? 0) <= 12 &&
            (selectedExerciseIDs.map { ($0.count > 0 || !race.plannedMeasures.isEmpty) && Set($0).count == $0.count && coachExerciseIDs.isEmpty } ?? true) &&
            (race.plannedMeasures.isEmpty || (race.discipline == .workout && coachExerciseIDs.isEmpty)) &&
            coachExerciseIDs.count <= 12 &&
            Set(coachExerciseIDs).count == coachExerciseIDs.count &&
            (startMode != .scheduled || startsAt != nil) &&
            (1...unit.maximumCount).contains(every) &&
            ATHLTHTournamentCadence.completionHours.contains(completionHours) &&
            agreement.isValid
    }

    var requiresExplicitConsent: Bool {
        agreement.hasTerms
    }

    /// Server scores a missed exercise as zero after its completion deadline.
    /// This is intentionally not a user-disableable setting.
    var missedExercisePoints: Int { 0 }

    // Existing locally stored drafts predate the new start/venue rules.
    // Decode missing fields to safe defaults instead of discarding a draft.
    init() {}
    private enum CodingKeys: String, CodingKey {
        case startsAt, endsAt, startMode, environment, activityEnvironments, exerciseEnvironments, meetingPlace, meetingAddress, meetingDescription, meetingLat,
             meetingLon, coachExerciseIDs, selectedExerciseIDs, race, invitationDays, unansweredPolicy,
             allowFeedPost, unlock, every, unit, completionHours,
             invitationPermission, joinApproval, agreement
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startsAt = try c.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
        startMode = try c.decodeIfPresent(ATHLTHCompetitionStartMode.self,
                                          forKey: .startMode) ?? .manual
        environment = try c.decodeIfPresent(ATHLTHCompetitionEnvironment.self,
                                            forKey: .environment) ?? .any
        activityEnvironments = try c.decodeIfPresent([String: ATHLTHCompetitionEnvironment].self, forKey: .activityEnvironments) ?? [:]
        exerciseEnvironments = try c.decodeIfPresent([UUID: ATHLTHCompetitionEnvironment].self, forKey: .exerciseEnvironments) ?? [:]
        meetingPlace = try c.decodeIfPresent(String.self,
                                             forKey: .meetingPlace) ?? ""
        meetingAddress = try c.decodeIfPresent(String.self, forKey: .meetingAddress)
        meetingDescription = try c.decodeIfPresent(String.self, forKey: .meetingDescription)
        meetingLat = try c.decodeIfPresent(Double.self, forKey: .meetingLat)
        meetingLon = try c.decodeIfPresent(Double.self, forKey: .meetingLon)
        coachExerciseIDs = try c.decodeIfPresent([UUID].self,
                                                  forKey: .coachExerciseIDs) ?? []
        selectedExerciseIDs = try c.decodeIfPresent([UUID].self, forKey: .selectedExerciseIDs)
        race = try c.decodeIfPresent(ATHLTHCompetitionRaceRules.self,
                                     forKey: .race) ?? .init()
        invitationDays = try c.decodeIfPresent(Int.self,
                            forKey: .invitationDays) ?? 3
        unansweredPolicy = try c.decodeIfPresent(
            ATHLTHCompetitionUnansweredPolicy.self,
            forKey: .unansweredPolicy) ?? .cancel
        allowFeedPost = try c.decodeIfPresent(Bool.self,
                        forKey: .allowFeedPost) ?? true
        unlock = try c.decodeIfPresent(ATHLTHCompetitionUnlock.self,
                                       forKey: .unlock) ?? .interval
        every = try c.decodeIfPresent(Int.self, forKey: .every) ?? 7
        unit = try c.decodeIfPresent(ATHLTHCompetitionIntervalUnit.self,
                                     forKey: .unit) ?? .day
        completionHours = try c.decodeIfPresent(Int.self,
                             forKey: .completionHours) ?? 48
        invitationPermission = try c.decodeIfPresent(
            ATHLTHCompetitionInvitePermission.self,
            forKey: .invitationPermission) ?? .admin
        joinApproval = try c.decodeIfPresent(
            ATHLTHCompetitionJoinApproval.self, forKey: .joinApproval) ?? .admin
        agreement = try c.decodeIfPresent(
            ATHLTHCompetitionAgreement.self, forKey: .agreement) ?? .init()
    }
}
