import Foundation

enum ATHLTHLiveWorkoutFeature: String, CaseIterable, Codable, Hashable, Identifiable {
    case ghostGap
    case routeGuardian
    case zoneLock
    case liveChallenge
    case liveShare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ghostGap: return "Ghost Gap"
        case .routeGuardian: return "Route Guardian"
        case .zoneLock: return "Zone Lock"
        case .liveChallenge: return "Live Challenge"
        case .liveShare: return "Live Share"
        }
    }

    var subtitle: String {
        switch self {
        case .ghostGap:
            return "See your live lead or gap against your ghost."
        case .routeGuardian:
            return "Surface route guidance and off-route warnings."
        case .zoneLock:
            return "Keep your target heart-rate zone visible."
        case .liveChallenge:
            return "Show progress for an active challenge."
        case .liveShare:
            return "Show live-sharing status and viewer count."
        }
    }

    var systemImage: String {
        switch self {
        case .ghostGap: return "figure.run"
        case .routeGuardian: return "location.fill"
        case .zoneLock: return "heart.fill"
        case .liveChallenge: return "trophy.fill"
        case .liveShare: return "dot.radiowaves.left.and.right"
        }
    }
}

struct ATHLTHLiveWorkoutSurfaceConfiguration: Codable, Hashable {
    var dynamicIslandEnabled: Bool
    var watchEnabled: Bool
    var smartPriorityEnabled: Bool
    var hapticsEnabled: Bool
    var audioAlertsEnabled: Bool

    var ghostGapEnabled: Bool
    var routeGuardianEnabled: Bool
    var zoneLockEnabled: Bool
    var liveChallengeEnabled: Bool
    var liveShareEnabled: Bool

    static let standard = ATHLTHLiveWorkoutSurfaceConfiguration(
        dynamicIslandEnabled: true,
        watchEnabled: true,
        smartPriorityEnabled: true,
        hapticsEnabled: true,
        audioAlertsEnabled: true,
        ghostGapEnabled: true,
        routeGuardianEnabled: true,
        zoneLockEnabled: true,
        liveChallengeEnabled: true,
        liveShareEnabled: true
    )

    func isEnabled(_ feature: ATHLTHLiveWorkoutFeature) -> Bool {
        switch feature {
        case .ghostGap: return ghostGapEnabled
        case .routeGuardian: return routeGuardianEnabled
        case .zoneLock: return zoneLockEnabled
        case .liveChallenge: return liveChallengeEnabled
        case .liveShare: return liveShareEnabled
        }
    }

    mutating func setEnabled(
        _ enabled: Bool,
        for feature: ATHLTHLiveWorkoutFeature
    ) {
        switch feature {
        case .ghostGap: ghostGapEnabled = enabled
        case .routeGuardian: routeGuardianEnabled = enabled
        case .zoneLock: zoneLockEnabled = enabled
        case .liveChallenge: liveChallengeEnabled = enabled
        case .liveShare: liveShareEnabled = enabled
        }
    }
}

struct ATHLTHLiveChallengeContext: Codable, Hashable {
    var title: String
    var targetDistanceMeters: Double?
    var projectedFinishSeconds: TimeInterval?
    var personalBestDeltaSeconds: TimeInterval?
}

struct ATHLTHLiveShareContext: Codable, Hashable {
    var isSharing: Bool
    var viewerCount: Int
    var viewerSummary: String?
}

struct ATHLTHLiveGhostContext: Codable, Hashable {
    var title: String
    var distanceDeltaMeters: Double?
    var estimatedTimeDeltaSeconds: TimeInterval?
    var updatedAt: Date
}

struct ATHLTHLiveWorkoutContext: Codable, Hashable {
    var challenge: ATHLTHLiveChallengeContext?
    var liveShare: ATHLTHLiveShareContext?
    var liveGhost: ATHLTHLiveGhostContext? = nil

    static let empty = ATHLTHLiveWorkoutContext(
        challenge: nil,
        liveShare: nil,
        liveGhost: nil
    )
}

enum ATHLTHLiveWorkoutFocus: String, Codable, Hashable {
    case routeGuardian
    case zoneLock
    case ghostGap
    case liveChallenge
    case liveShare
    case workout
}

struct ATHLTHLiveWorkoutPriorityState: Hashable {
    var hasRoute: Bool
    var routeDeviationMeters: Double?
    var routeDeviationThresholdMeters: Double?
    var hasZoneTarget: Bool
    var zoneStatus: String?
    var hasGhost: Bool
    var hasChallenge: Bool
    var hasLiveShare: Bool
}

enum ATHLTHLiveWorkoutPriorityResolver {
    static func resolve(
        configuration: ATHLTHLiveWorkoutSurfaceConfiguration,
        state: ATHLTHLiveWorkoutPriorityState
    ) -> ATHLTHLiveWorkoutFocus {
        let routeAvailable =
            configuration.routeGuardianEnabled &&
            state.hasRoute

        let routeIsUrgent: Bool = {
            guard routeAvailable,
                  let deviation = state.routeDeviationMeters,
                  let threshold = state.routeDeviationThresholdMeters
            else {
                return false
            }

            return deviation > threshold
        }()

        let zoneAvailable =
            configuration.zoneLockEnabled &&
            state.hasZoneTarget

        let zoneIsUrgent: Bool = {
            guard zoneAvailable,
                  let status = state.zoneStatus?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !status.isEmpty
            else {
                return false
            }

            return status.caseInsensitiveCompare("On target") != .orderedSame &&
                status.caseInsensitiveCompare("In target") != .orderedSame
        }()

        let ghostAvailable =
            configuration.ghostGapEnabled &&
            state.hasGhost

        let challengeAvailable =
            configuration.liveChallengeEnabled &&
            state.hasChallenge

        let liveShareAvailable =
            configuration.liveShareEnabled &&
            state.hasLiveShare

        if configuration.smartPriorityEnabled {
            if routeIsUrgent { return .routeGuardian }
            if zoneIsUrgent { return .zoneLock }
            if ghostAvailable { return .ghostGap }
            if challengeAvailable { return .liveChallenge }
            if liveShareAvailable { return .liveShare }
            if routeAvailable { return .routeGuardian }
            if zoneAvailable { return .zoneLock }
            return .workout
        }

        if ghostAvailable { return .ghostGap }
        if challengeAvailable { return .liveChallenge }
        if liveShareAvailable { return .liveShare }
        if routeAvailable { return .routeGuardian }
        if zoneAvailable { return .zoneLock }
        return .workout
    }
}

enum ATHLTHLiveWorkoutPreferencesStore {
    private static let key =
        "athlth.liveWorkout.surfaceConfiguration.v1"

    static func load() -> ATHLTHLiveWorkoutSurfaceConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(
                ATHLTHLiveWorkoutSurfaceConfiguration.self,
                from: data
              )
        else {
            return .standard
        }

        return configuration
    }

    static func save(
        _ configuration: ATHLTHLiveWorkoutSurfaceConfiguration
    ) {
        guard let data = try? JSONEncoder().encode(configuration)
        else {
            return
        }

        defaults.set(data, forKey: key)
    }

    private static var defaults: UserDefaults {
        #if os(watchOS)
        return .standard
        #else
        return UserDefaults(
            suiteName: ATHLTHSurfaceSharedStore.appGroupIdentifier
        ) ?? .standard
        #endif
    }
}

enum ATHLTHLiveWorkoutContextStore {
    private static let key =
        "athlth.liveWorkout.context.v1"

    static func load() -> ATHLTHLiveWorkoutContext {
        guard let data = defaults.data(forKey: key),
              let context = try? JSONDecoder().decode(
                ATHLTHLiveWorkoutContext.self,
                from: data
              )
        else {
            return .empty
        }

        return context
    }

    static func save(_ context: ATHLTHLiveWorkoutContext) {
        guard let data = try? JSONEncoder().encode(context)
        else {
            return
        }

        defaults.set(data, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    private static var defaults: UserDefaults {
        #if os(watchOS)
        return .standard
        #else
        return UserDefaults(
            suiteName: ATHLTHSurfaceSharedStore.appGroupIdentifier
        ) ?? .standard
        #endif
    }
}
