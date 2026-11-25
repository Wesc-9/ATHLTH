import XCTest
@testable import ATHLTH

final class ATHLTHCompetitionCreationPolicyTests: XCTestCase {
    private let owner = UUID()
    private let rival = UUID()

    func testChangingCompetitionFormatPreservesSelectedFriend() {
        let other = UUID()
        let roster: Set<UUID> = [rival, other]
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.opponentsAfterFormatChange(
            roster, format: .duel, preferred: rival), Set([rival]))
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.opponentsAfterFormatChange(
            roster, format: .single, preferred: rival), roster)
    }

    private func valid(
        activity: ATHLTHQuickStartActivity,
        format: ATHLTHCompetitionFormat,
        opponents: Set<UUID>,
        metric: ATHLTHChallengeScoring,
        distance: Double = 5,
        duration: Double = 30,
        exercise: String = "Squat",
        name: String = "Competition"
    ) -> Bool {
        ATHLTHCompetitionCreationPolicy.canPublish(
            name: name,
            ownerID: owner,
            opponents: opponents,
            format: format,
            metric: metric,
            activity: activity,
            distanceKM: distance,
            durationMinutes: duration,
            exerciseName: exercise,
            endsAt: Date().addingTimeInterval(7 * 86_400),
            now: Date()
        )
    }

    func testAllThreeSportsUseEstablishedChallengeAndTournamentTypes() {
        XCTAssertEqual(
            ATHLTHCompetitionCreationPolicy.sport(.running), .running
        )
        XCTAssertEqual(
            ATHLTHCompetitionCreationPolicy.sport(.walking), .walking
        )
        XCTAssertEqual(
            ATHLTHCompetitionCreationPolicy.sport(.strength), .strength
        )
        XCTAssertEqual(
            ATHLTHCompetitionCreationPolicy.tournamentActivity(.running),
            .running
        )
        XCTAssertEqual(
            ATHLTHCompetitionCreationPolicy.tournamentActivity(.walking),
            .walking
        )
        XCTAssertEqual(
            ATHLTHCompetitionCreationPolicy.tournamentActivity(.strength),
            .strength
        )
    }

    func testSharedCompetitionPickerUsesCanonicalTypesWithoutIncorrectSportMapping() {
        XCTAssertEqual(Set(ATHLTHPlannedWorkoutType.defaultOrder), Set(ATHLTHPlannedWorkoutType.allCases))
        XCTAssertEqual(ATHLTHPlannedWorkoutType.defaultOrder.count, 6)
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.quickStartActivity(for: .running), .running)
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.quickStartActivity(for: .walking), .walking)
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.quickStartActivity(for: .strength), .strength)
        XCTAssertNil(ATHLTHCompetitionCreationPolicy.quickStartActivity(for: .cycling))
        XCTAssertNil(ATHLTHCompetitionCreationPolicy.quickStartActivity(for: .mobility))
        XCTAssertNil(ATHLTHCompetitionCreationPolicy.quickStartActivity(for: .custom))
    }

    func testCompetitionHasOwnEntryInsteadOfQuickStart() {
        for sport in [
            ATHLTHQuickStartActivity.running, .walking, .strength
        ] {
            XCTAssertFalse(sport.types.contains(.competition))
        }
        XCTAssertEqual(ATHLTHCompetitionFormat.allCases.count, 4)
    }

    func testDuelCannotStartWithoutOneEligibleOpponent() {
        XCTAssertFalse(valid(
            activity: .running, format: .duel, opponents: [],
            metric: .fastestDistance
        ))
        XCTAssertFalse(valid(
            activity: .running, format: .duel, opponents: [owner],
            metric: .fastestDistance
        ))
        XCTAssertTrue(valid(
            activity: .running, format: .duel, opponents: [rival],
            metric: .fastestDistance
        ))
        XCTAssertFalse(valid(
            activity: .running, format: .duel,
            opponents: [rival, UUID()],
            metric: .fastestDistance
        ))
    }

    func testCupAndLeagueRequireDifferentRosterSizes() {
        let players: Set<UUID> = [rival, UUID()]
        XCTAssertTrue(valid(
            activity: .walking, format: .league,
            opponents: players, metric: .mostDistance
        ))
        XCTAssertFalse(valid(
            activity: .walking, format: .cup,
            opponents: players, metric: .mostDistance
        ))
        XCTAssertTrue(valid(
            activity: .walking, format: .cup,
            opponents: players.union([UUID()]), metric: .mostDistance
        ))
    }

    func testLeagueAllowsOneOpponentAndCupNeedsThreeOpponents() {
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.minOpponents(.league), 1)
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.minOpponents(.cup), 3)
        XCTAssertTrue(valid(
            activity: .running, format: .league,
            opponents: [rival], metric: .fastestDistance
        ))
        XCTAssertFalse(valid(
            activity: .running, format: .cup,
            opponents: [rival, UUID()], metric: .fastestDistance
        ))
        XCTAssertTrue(valid(
            activity: .running, format: .cup,
            opponents: [rival, UUID(), UUID()], metric: .fastestDistance
        ))
    }

    func testSingleEventHasExactlyOneSharedEventWithThreeOrMoreAthletes() {
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.minOpponents(.single), 2)
        XCTAssertFalse(valid(
            activity: .running, format: .single,
            opponents: [rival], metric: .fastestDistance
        ))
        XCTAssertTrue(valid(
            activity: .running, format: .single,
            opponents: [rival, UUID()], metric: .fastestDistance
        ))
        XCTAssertTrue(valid(
            activity: .strength, format: .single,
            opponents: [rival, UUID(), UUID()], metric: .workoutVolume
        ))
    }

    func testVeryShortSprintsMayLastTenSeconds() {
        XCTAssertTrue(valid(
            activity: .running, format: .duel,
            opponents: [rival], metric: .farthestInTime,
            duration: 10.0 / 60.0
        ))
    }

    func testDistanceAndTimeMustBeFiniteAndWithinBounds() {
        XCTAssertFalse(valid(
            activity: .running, format: .duel, opponents: [rival],
            metric: .fastestDistance, distance: .nan
        ))
        XCTAssertFalse(valid(
            activity: .running, format: .duel, opponents: [rival],
            metric: .fastestDistance, distance: 600
        ))
        XCTAssertFalse(valid(
            activity: .walking, format: .duel, opponents: [rival],
            metric: .farthestInTime, duration: 0
        ))
    }

    func testStrengthNeedsAnExerciseForExerciseSpecificScoring() {
        XCTAssertFalse(valid(
            activity: .strength, format: .duel, opponents: [rival],
            metric: .mostReps, exercise: " "
        ))
        XCTAssertTrue(valid(
            activity: .strength, format: .duel, opponents: [rival],
            metric: .workoutVolume, exercise: ""
        ))
    }

    func testRouteTimeTrialRequiresSelectedRoute() {
        XCTAssertFalse(ATHLTHCompetitionCreationPolicy.canPublish(
            name: "Route duel",
            ownerID: owner,
            opponents: [rival],
            format: .duel,
            metric: .fastestRoute,
            activity: .running,
            distanceKM: 5,
            durationMinutes: 30,
            exerciseName: "",
            hasRoute: false,
            endsAt: Date().addingTimeInterval(86_400),
            now: Date()
        ))
        XCTAssertTrue(ATHLTHCompetitionCreationPolicy.canPublish(
            name: "Route duel",
            ownerID: owner,
            opponents: [rival],
            format: .duel,
            metric: .fastestRoute,
            activity: .running,
            distanceKM: 5,
            durationMinutes: 30,
            exerciseName: "",
            hasRoute: true,
            endsAt: Date().addingTimeInterval(86_400),
            now: Date()
        ))
    }

    func testOnlyCompatibleDuelsCanBePublished() {
        XCTAssertFalse(valid(
            activity: .strength, format: .duel, opponents: [rival],
            metric: .fastestDistance
        ))
        XCTAssertFalse(valid(
            activity: .running, format: .duel, opponents: [rival],
            metric: .workoutVolume
        ))
    }

    func testExistingTournamentEngineCreatesRealLeagueAndCupFixtures() throws {
        let athletes = [
            ATHLTHTournamentParticipant(id: owner, username: "Creator"),
            ATHLTHTournamentParticipant(id: rival, username: "Rival"),
            ATHLTHTournamentParticipant(id: UUID(), username: "Athlete 3"),
            ATHLTHTournamentParticipant(id: UUID(), username: "Athlete 4")
        ]
        for format in [ATHLTHTournamentFormat.league, .cup] {
            let draft = ATHLTHTournamentDraft(
                ownerID: owner,
                clubID: nil,
                title: "Running competition",
                format: format,
                groupSize: 4,
                qualifiersPerGroup: 2,
                participants: athletes,
                allowedActivities: [.running]
            )
            let fixtures = try ATHLTHTournamentEngine.initialFixtures(for: draft)
            XCTAssertFalse(fixtures.isEmpty)
            XCTAssertTrue(fixtures.allSatisfy {
                $0.homeID != $0.awayID
            })
            if format == .league {
                XCTAssertEqual(fixtures.count, 6)
            } else {
                XCTAssertEqual(fixtures.count, 2)
            }
        }
    }
}
