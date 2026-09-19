import CoreLocation
import Foundation

enum AccountRole: String, Codable, Hashable {
    case user
    case admin

    var title: String {
        switch self {
        case .user: return "User"
        case .admin: return "Admin"
        }
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
    var followersCount: Int
    var followingCount: Int
    var workoutsCount: Int
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

    var snapshot: ExerciseSnapshot {
        ExerciseSnapshot(
            name: name,
            instructions: instructions,
            primaryMuscles: primaryMuscles,
            equipment: equipment,
            imageURL: imageURL
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
}

enum ChallengeStatus: String, Codable, Hashable {
    case upcoming
    case active
    case completed
}

struct RouteAttempt: Identifiable, Codable, Hashable {
    let id: UUID
    var userID: UUID
    var routeID: UUID
    var activityID: UUID?
    var startedAt: Date
    var duration: TimeInterval
    var distanceKilometers: Double
    var averagePaceSecondsPerKilometer: Double?
}

struct RouteChallenge: Identifiable, Codable, Hashable {
    let id: UUID
    var creatorID: UUID
    var routeID: UUID
    var title: String
    var visibility: ProfileVisibility
    var status: ChallengeStatus
    var startsAt: Date?
    var endsAt: Date?
    var participantIDs: [UUID]
    var attempts: [RouteAttempt]
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

enum FriendshipStatus: String, Codable, Hashable {
    case pending
    case accepted
    case blocked
}

struct Friendship: Identifiable, Codable, Hashable {
    let id: UUID
    var requesterID: UUID
    var addresseeID: UUID
    var status: FriendshipStatus
    var createdAt: Date
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
