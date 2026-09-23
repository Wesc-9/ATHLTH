#if DEBUG
import Foundation

enum PreviewData {
    static let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    static let profile = UserProfile(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        userID: userID,
        username: "stian",
        displayName: "Stian",
        bio: "Move better. Train smarter.",
        avatarURL: nil,
        presence: TrainingPresence(
            state: .available,
            workoutTitle: nil,
            startedAt: nil,
            visibility: .friends
        )
    )

    static let benchPress = Exercise(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        origin: .publicCatalog,
        ownerID: nil,
        name: "Bench Press",
        instructions: [
            "Lie on the bench with your feet planted.",
            "Lower the bar with control.",
            "Press the bar upward until your arms are extended."
        ],
        primaryMuscles: ["Chest"],
        secondaryMuscles: ["Triceps", "Front delts"],
        equipment: ["Barbell", "Bench"],
        imageURL: nil,
        isVisibleOutsideOwnerLibrary: true
    )

    static let customExercise = Exercise(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        origin: .custom,
        ownerID: userID,
        name: "Stian Cable Side Raise",
        instructions: [
            "Set the cable low.",
            "Raise the arm to shoulder height with control."
        ],
        primaryMuscles: ["Lateral deltoid"],
        secondaryMuscles: [],
        equipment: ["Cable"],
        imageURL: nil,
        isVisibleOutsideOwnerLibrary: false
    )

    static let upperBodySession = PlannedSession(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        title: "Upper Body Strength",
        kind: .strength,
        scheduledStart: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()),
        durationMinutes: 50,
        targetDistanceKilometers: nil,
        targetPaceSecondsPerKilometer: nil,
        routeID: nil,
        exercises: [
            PlannedExercise(
                id: UUID(),
                exerciseID: benchPress.id,
                embeddedExercise: benchPress.snapshot,
                sets: 4,
                reps: 8,
                targetWeightKilograms: 80,
                targetRPE: 8,
                restSeconds: 120,
                notes: nil
            ),
            PlannedExercise(
                id: UUID(),
                exerciseID: customExercise.id,
                embeddedExercise: customExercise.snapshot,
                sets: 3,
                reps: 12,
                targetWeightKilograms: nil,
                targetRPE: 8,
                restSeconds: 75,
                notes: nil
            )
        ],
        notes: "Keep the last set challenging, but controlled."
    )

    static let spotifyPlaylists: [SpotifyPlaylistReference] = [
        SpotifyPlaylistReference(
            id: "gym-power-mix",
            name: "Gym Power Mix",
            uri: "spotify:playlist:gym-power-mix",
            artworkURL: nil,
            ownerName: "Stian"
        ),
        SpotifyPlaylistReference(
            id: "run-focus",
            name: "Run Focus",
            uri: "spotify:playlist:run-focus",
            artworkURL: nil,
            ownerName: "Stian"
        ),
        SpotifyPlaylistReference(
            id: "recovery-flow",
            name: "Recovery Flow",
            uri: "spotify:playlist:recovery-flow",
            artworkURL: nil,
            ownerName: "Stian"
        )
    ]

    static let trainingPlan = TrainingPlan(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        ownerID: userID,
        title: "Balanced Performance",
        summary: "Strength, running and recovery across a flexible week.",
        visibility: .friends,
        version: 1,
        weeks: [
            TrainingPlanWeek(
                id: UUID(),
                weekNumber: 1,
                title: "Foundation",
                days: [
                    TrainingPlanDay(
                        id: UUID(),
                        dayIndex: 1,
                        title: "Monday",
                        sessions: [upperBodySession]
                    ),
                    TrainingPlanDay(
                        id: UUID(),
                        dayIndex: 2,
                        title: "Tuesday",
                        sessions: [
                            PlannedSession(
                                id: UUID(),
                                title: "Easy Run",
                                kind: .running,
                                scheduledStart: nil,
                                durationMinutes: 40,
                                targetDistanceKilometers: 6,
                                targetPaceSecondsPerKilometer: nil,
                                routeID: nil,
                                exercises: [],
                                notes: "Conversational pace."
                            )
                        ]
                    )
                ]
            )
        ],
        tags: ["strength", "running", "balanced"],
        spotifyPlaylist: spotifyPlaylists.first,
        spotifyAutoplayOnWorkoutStart: true,
        createdAt: Date(),
        updatedAt: Date()
    )

    static let healthSnapshot = HealthSnapshot(
        activeCalories: 482,
        activeCaloriesGoal: 700,
        steps: 8_432,
        sleepDuration: 7 * 3600 + 24 * 60,
        restingHeartRate: 56,
        hrvMilliseconds: 72,
        recoveryScore: 82
    )

    static let recoverySnapshot = RecoverySnapshot(
        score: 82,
        sleepScore: 84,
        sleepDuration: 7 * 3600 + 24 * 60,
        hrvMilliseconds: 72,
        restingHeartRate: 56,
        readinessText: "Well recovered"
    )
}
#endif
