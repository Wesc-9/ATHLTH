import CoreLocation
import Foundation

enum SubscriptionTier: String, Codable, CaseIterable, Identifiable, Hashable {
    case free
    case paid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free"
        case .paid: return "ATHLTH+"
        }
    }
}

enum SubscriptionAccessState: String, Codable, Hashable {
    case free
    case trial
    case paid
    case expired
    case revoked

    var title: String {
        switch self {
        case .free: return "Free"
        case .trial: return "ATHLTH+ trial"
        case .paid: return "ATHLTH+"
        case .expired: return "ATHLTH+ expired"
        case .revoked: return "ATHLTH+ revoked"
        }
    }
}

enum SubscriptionLifecycleState: String, Codable, Hashable {
    case free
    case trial
    case active
    case expired
    case revoked

    var title: String {
        switch self {
        case .free: return "Free"
        case .trial: return "ATHLTH+ trial"
        case .active: return "ATHLTH+"
        case .expired: return "ATHLTH+ expired"
        case .revoked: return "ATHLTH+ revoked"
        }
    }
}

enum SubscriptionAccessSource: String, Codable, Hashable {
    case none
    case athlthTrial
    case appStore
    case serverVerified
}

enum ATHLTHFeature: Hashable, CaseIterable {
    case backgroundHealthSync
    case advancedTrainingPlans
    case advancedRecovery
    case aiTrainingPrograms
    case audioCoach

    var requiresATHLTHPlus: Bool {
        switch self {
        case .aiTrainingPrograms,
             .audioCoach:
            return true
        case .backgroundHealthSync,
             .advancedTrainingPlans,
             .advancedRecovery:
            return false
        }
    }
}

struct SubscriptionAccess: Codable, Hashable {
    var state: SubscriptionAccessState
    var trialStartedAt: Date?
    var trialEndsAt: Date?
    var source: SubscriptionAccessSource?
    var productID: String?
    var currentPeriodEndsAt: Date?

    init(
        state: SubscriptionAccessState,
        trialStartedAt: Date? = nil,
        trialEndsAt: Date? = nil,
        source: SubscriptionAccessSource? = nil,
        productID: String? = nil,
        currentPeriodEndsAt: Date? = nil
    ) {
        self.state = state
        self.trialStartedAt = trialStartedAt
        self.trialEndsAt = trialEndsAt
        self.source = source
        self.productID = productID
        self.currentPeriodEndsAt = currentPeriodEndsAt
    }

    static let free = SubscriptionAccess(
        state: .free,
        source: SubscriptionAccessSource.none
    )

    var trialIsActive: Bool {
        guard state == .trial, let trialEndsAt else { return false }
        return Date() < trialEndsAt
    }

    var paidIsActive: Bool {
        guard state == .paid else { return false }
        guard let currentPeriodEndsAt else { return true }
        return Date() < currentPeriodEndsAt
    }

    var lifecycleState: SubscriptionLifecycleState {
        switch state {
        case .trial:
            return trialIsActive ? .trial : .expired
        case .paid:
            return paidIsActive ? .active : .expired
        case .expired:
            return .expired
        case .revoked:
            return .revoked
        case .free:
            let normalizedSource = source ?? .none
            if normalizedSource != .none,
               trialEndsAt != nil || currentPeriodEndsAt != nil || productID != nil {
                return .expired
            }
            return .free
        }
    }

    var hasPaidAccess: Bool {
        lifecycleState == .trial || lifecycleState == .active
    }

    var effectiveTier: SubscriptionTier {
        hasPaidAccess ? .paid : .free
    }

    var displayTitle: String {
        lifecycleState.title
    }

    var billingPeriodTitle: String? {
        switch productID {
        case SubscriptionStore.monthlyProductID:
            return "Monthly"
        case SubscriptionStore.yearlyProductID:
            return "Yearly"
        default:
            return nil
        }
    }

    var trialDaysRemaining: Int? {
        guard trialIsActive, let trialEndsAt else { return nil }
        let remaining = Calendar.current.dateComponents(
            [.day],
            from: Date(),
            to: trialEndsAt
        ).day ?? 0
        return max(1, remaining + 1)
    }
}

enum AccountRole: String, Codable, Hashable, CaseIterable {
    case user
    case admin
    case owner

    var title: String {
        switch self {
        case .user: return "User"
        case .admin: return "Admin"
        case .owner: return "Owner"
        }
    }

    var canAccessControlCenter: Bool {
        self == .admin || self == .owner
    }

    var canManageAdmins: Bool {
        self == .owner
    }
}

enum ProfileVisibility: String, Codable, CaseIterable, Identifiable {
    case privateOnly = "private"
    case friends
    case publicProfile = "public"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateOnly: return "Private"
        case .friends: return "Friends"
        case .publicProfile: return "Public"
        }
    }
}

struct ATHLTHUser: Identifiable, Codable, Hashable {
    let id: UUID
    var email: String?
    var appleUserIdentifier: String?
    var username: String
    var displayName: String
    var createdAt: Date
}

enum TrainingPresenceState: String, Codable, Hashable {
    case offline
    case available
    case training
}

struct TrainingPresence: Codable, Hashable {
    var state: TrainingPresenceState
    var workoutTitle: String?
    var startedAt: Date?
    var visibility: ProfileVisibility
}

struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID
    var username: String
    var displayName: String
    var bio: String
    var avatarURL: URL?
    var presence: TrainingPresence
}

enum WorkoutKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case running
    case walking
    case strength
    case mobility
    case recovery
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walk"
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .recovery: return "Recovery"
        case .custom: return "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.flexibility"
        case .recovery: return "leaf.fill"
        case .custom: return "plus.circle.fill"
        }
    }
}

enum ExerciseOrigin: String, Codable, Hashable {
    case publicCatalog
    case custom
}

struct ExerciseSnapshot: Codable, Hashable {
    var name: String
    var instructions: [String]
    var primaryMuscles: [String]
    var equipment: [String]
    var imageURL: URL?
    var videoURL: URL? = nil
}

struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    var origin: ExerciseOrigin
    var ownerID: UUID?
    var name: String
    var instructions: [String]
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var equipment: [String]
    var imageURL: URL?
    var isVisibleOutsideOwnerLibrary: Bool
    var videoURL: URL? = nil

    var snapshot: ExerciseSnapshot {
        ExerciseSnapshot(
            name: name,
            instructions: instructions,
            primaryMuscles: primaryMuscles,
            equipment: equipment,
            imageURL: imageURL,
            videoURL: videoURL
        )
    }
}

struct PlannedExercise: Identifiable, Codable, Hashable {
    let id: UUID
    var exerciseID: UUID?
    var embeddedExercise: ExerciseSnapshot
    var sets: Int
    var reps: Int?
    var targetWeightKilograms: Double?
    var targetRPE: Double?
    var restSeconds: Int?
    var notes: String?
    var targetRIR: Double? = nil
    var supersetGroupID: UUID? = nil
    var progression: StrengthProgressionRule? = nil
}

struct PlannedSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var kind: WorkoutKind
    var scheduledStart: Date?
    var durationMinutes: Int?
    var targetDistanceKilometers: Double?
    var targetPaceSecondsPerKilometer: Double?
    var routeID: UUID?
    var exercises: [PlannedExercise]
    var notes: String?
    var runningWorkout: RunningWorkoutTemplate? = nil
    var sharedSourceOwnerID: UUID? = nil
    var sharedSourceSessionID: UUID? = nil
}

struct TrainingPlanDay: Identifiable, Codable, Hashable {
    let id: UUID
    var dayIndex: Int
    var title: String
    var sessions: [PlannedSession]
}

struct TrainingPlanWeek: Identifiable, Codable, Hashable {
    let id: UUID
    var weekNumber: Int
    var title: String
    var days: [TrainingPlanDay]
}

struct TrainingPlan: Identifiable, Codable, Hashable {
    let id: UUID
    var ownerID: UUID
    var title: String
    var summary: String
    var visibility: ProfileVisibility
    var version: Int
    var weeks: [TrainingPlanWeek]
    var tags: [String]
    var spotifyPlaylist: SpotifyPlaylistReference? = nil
    var spotifyAutoplayOnWorkoutStart: Bool = true
    var createdAt: Date
    var updatedAt: Date
    var startDate: Date? = nil
    var sharedSourceOwnerID: UUID? = nil
    var sharedSourcePlanID: UUID? = nil
    var sharedSourceVersion: Int? = nil
}

struct RouteCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var sequence: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct TrainingRoute: Identifiable, Codable, Hashable {
    let id: UUID
    var ownerID: UUID
    var title: String
    var visibility: ProfileVisibility
    var coordinates: [RouteCoordinate]
    var distanceKilometers: Double
    var elevationGainMeters: Double?
    var importedFilename: String?
    var createdAt: Date

    // Optional route-builder metadata. Kept optional so previously saved
    // GPX routes continue to decode without migration.
    var startName: String? = nil
    var endName: String? = nil
    var expectedTravelTimeSeconds: TimeInterval? = nil
    var routeSource: String? = nil
    var sharedSourceOwnerID: UUID? = nil
    var sharedSourceRouteID: UUID? = nil
}

struct ActivityRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID
    var workoutKind: WorkoutKind
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var distanceKilometers: Double?
    var activeCalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var routeID: UUID?
    var visibility: ProfileVisibility
}

struct ActivityComment: Identifiable, Codable, Hashable {
    let id: UUID
    var activityID: UUID
    var authorID: UUID
    var body: String
    var createdAt: Date
}

struct DirectMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var senderID: UUID
    var recipientID: UUID
    var body: String
    var createdAt: Date
    var readAt: Date?
}

struct HealthSnapshot: Equatable, Hashable {
    var activeCalories: Double
    var activeCaloriesGoal: Double
    var steps: Int
    var sleepDuration: TimeInterval
    var restingHeartRate: Double?
    var hrvMilliseconds: Double?
    var recoveryScore: Int?
}

struct RecoverySnapshot: Equatable, Hashable {
    var score: Int
    var sleepScore: Int
    var sleepDuration: TimeInterval
    var hrvMilliseconds: Double?
    var restingHeartRate: Double?
    var readinessText: String
}
