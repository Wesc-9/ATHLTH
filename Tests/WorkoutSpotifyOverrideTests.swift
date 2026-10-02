import XCTest
@testable import ATHLTH

final class WorkoutSpotifyOverrideTests: XCTestCase {
    @MainActor
    func testWorkoutPlaylistOverridesProgramDefault() {
        let store = makeStore()
        let programPlaylist = playlist(
            id: "program",
            name: "Program"
        )
        let workoutPlaylist = playlist(
            id: "workout",
            name: "Workout"
        )
        let workout = makeWorkout(
            playlist: workoutPlaylist,
            autoplay: true
        )

        addPlan(
            to: store,
            workout: workout,
            playlist: programPlaylist,
            autoplay: true
        )

        XCTAssertEqual(
            WorkoutLaunchCoordinator
                .resolvedSpotifyPlaylist(
                    workout: workout,
                    session: store
                )?.id,
            workoutPlaylist.id
        )
    }

    @MainActor
    func testWorkoutOffOverridesProgramDefault() {
        let store = makeStore()
        let programPlaylist = playlist(
            id: "program",
            name: "Program"
        )
        let workout = makeWorkout(
            playlist: nil,
            autoplay: false
        )

        addPlan(
            to: store,
            workout: workout,
            playlist: programPlaylist,
            autoplay: true
        )

        XCTAssertNil(
            WorkoutLaunchCoordinator
                .resolvedSpotifyPlaylist(
                    workout: workout,
                    session: store
                )
        )
    }

    @MainActor
    func testLegacyWorkoutInheritsProgramDefault() {
        let store = makeStore()
        let programPlaylist = playlist(
            id: "program",
            name: "Program"
        )
        let workout = makeWorkout(
            playlist: nil,
            autoplay: nil
        )

        addPlan(
            to: store,
            workout: workout,
            playlist: programPlaylist,
            autoplay: true
        )

        XCTAssertEqual(
            WorkoutLaunchCoordinator
                .resolvedSpotifyPlaylist(
                    workout: workout,
                    session: store
                )?.id,
            programPlaylist.id
        )
    }

    @MainActor
    private func makeStore() -> AppSessionStore {
        let suite =
            "WorkoutSpotifyOverrideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(
            suiteName: suite
        )!

        return AppSessionStore(
            profile: UserProfile(
                id: UUID(),
                userID: UUID(),
                username: "runner",
                displayName: "Runner",
                bio: "",
                avatarURL: nil,
                presence: TrainingPresence(
                    state: .available,
                    workoutTitle: nil,
                    startedAt: nil,
                    visibility: .friends
                )
            ),
            defaults: defaults
        )
    }

    private func playlist(
        id: String,
        name: String
    ) -> SpotifyPlaylistReference {
        SpotifyPlaylistReference(
            id: id,
            name: name,
            uri: "spotify:playlist:\(id)",
            artworkURL: nil,
            ownerName: "ATHLTH"
        )
    }

    private func makeWorkout(
        playlist: SpotifyPlaylistReference?,
        autoplay: Bool?
    ) -> PlannedSession {
        PlannedSession(
            id: UUID(),
            title: "Run",
            kind: .running,
            scheduledStart: nil,
            durationMinutes: 45,
            targetDistanceKilometers: 8,
            targetPaceSecondsPerKilometer: nil,
            routeID: nil,
            exercises: [],
            notes: nil,
            spotifyPlaylist: playlist,
            spotifyAutoplayOnStart: autoplay
        )
    }

    @MainActor
    private func addPlan(
        to store: AppSessionStore,
        workout: PlannedSession,
        playlist: SpotifyPlaylistReference,
        autoplay: Bool
    ) {
        let day = TrainingPlanDay(
            id: UUID(),
            dayIndex: 0,
            title: "Day 1",
            sessions: [workout]
        )
        let week = TrainingPlanWeek(
            id: UUID(),
            weekNumber: 1,
            title: "Week 1",
            days: [day]
        )
        let plan = TrainingPlan(
            id: UUID(),
            ownerID: store.profile.userID,
            title: "Plan",
            summary: "",
            visibility: .privateOnly,
            version: 1,
            weeks: [week],
            tags: [],
            spotifyPlaylist: playlist,
            spotifyAutoplayOnWorkoutStart:
                autoplay,
            createdAt: Date(),
            updatedAt: Date(),
            startDate:
                Calendar.current
                    .startOfDay(for: Date()),
            endDate:
                Calendar.current.date(
                    byAdding: .day,
                    value: 6,
                    to:
                        Calendar.current
                            .startOfDay(
                                for: Date()
                            )
                )
        )

        XCTAssertTrue(
            store.addTrainingPlan(plan)
        )
    }
}
