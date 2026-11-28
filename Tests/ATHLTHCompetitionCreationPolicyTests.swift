import CoreGraphics
import XCTest
@testable import ATHLTH

final class ATHLTHCompetitionCreationPolicyTests: XCTestCase {
    private let owner = UUID()
    private let rival = UUID()

    func testPredefinedCompetitionExercisesKeepServerMetricAndTarget() {
        let fixtures: [(ATHLTHTournamentActivity, String, Double?, String)] = [
            (.strength, "repetitions", nil, "Flest repetisjoner"), // push-ups
            (.strength, "repetitions", nil, "Flest repetisjoner"), // squats
            (.strength, "repetitions", nil, "Flest repetisjoner"), // burpees
            (.strength, "time", nil, "Lengst holdetid"), // plank
            (.running, "distance", 3000, "Raskest tid"),
            (.running, "distance", 5000, "Raskest tid"),
            (.running, "distance", 10000, "Raskest tid"),
            (.running, "duration", 1800, "Lengst distanse"),
            (.walking, "distance", 5000, "Raskest tid"),
            (.walking, "distance", 10000, "Raskest tid")
        ]
        for (activity, metric, target, description) in fixtures {
            let id = UUID()
            let remote = ATHLTHTournamentActivityTemplateRemote(id: id, title: "Preset",
                activityType: activity, metric: metric, targetValue: target)
            let selected = remote.competitionSelection
            XCTAssertEqual(selected.id, id)
            XCTAssertEqual(selected.metric, metric)
            XCTAssertEqual(selected.targetValue, target)
            XCTAssertTrue(selected.hasSupportedMetric)
            XCTAssertFalse(selected.canCustomizeMeasure)
            XCTAssertTrue(selected.resultDescription.hasPrefix(description))
        }
        let library = ATHLTHTournamentExerciseSearchResult(id: UUID(), name: "Bench Press", isActivityTemplate: false)
        XCTAssertTrue(library.canCustomizeMeasure)
        XCTAssertTrue(library.hasSupportedMetric)
        let invalid = ATHLTHTournamentExerciseSearchResult(id: UUID(), name: "Invalid", isActivityTemplate: true,
            metric: "distance", activity: .running)
        XCTAssertFalse(invalid.hasSupportedMetric)
        XCTAssertFalse(invalid.canCustomizeMeasure)
    }

    func testUniversalFirstStepOnlyNeedsNameAndValidRoster() {
        let others = [rival, UUID(), UUID(), UUID()]
        for format in ATHLTHCompetitionFormat.allCases {
            let min = ATHLTHCompetitionCreationPolicy.minOpponents(format)
            let valid = Set(others.prefix(min))
            XCTAssertTrue(ATHLTHCompetitionCreationPolicy.canContinueToRules(
                name: format.title, ownerID: owner, opponents: valid, format: format))
            XCTAssertFalse(ATHLTHCompetitionCreationPolicy.canContinueToRules(
                name: format.title, ownerID: owner, opponents: Set(others.prefix(min - 1)), format: format))
            XCTAssertFalse(ATHLTHCompetitionCreationPolicy.canContinueToRules(
                name: " ", ownerID: owner, opponents: valid, format: format))
            XCTAssertFalse(ATHLTHCompetitionCreationPolicy.canContinueToRules(
                name: format.title, ownerID: owner, opponents: valid.union([owner]), format: format))
        }
        XCTAssertFalse(ATHLTHCompetitionCreationPolicy.canContinueToRules(
            name: "Duell", ownerID: owner, opponents: Set(others.prefix(2)), format: .duel))
    }

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

    func testAutomaticDuelTitleIncludesBothUsersAndChosenBranches() {
        XCTAssertEqual(ATHLTHCompetitionCreationPolicy.duelName(owner: "bruker1",
            opponent: "bruker2", branches: ["Løping", "Styrke"]),
            "Duell bruker1 vs bruker2 i Løping og Styrke")
        XCTAssertLessThanOrEqual(ATHLTHCompetitionCreationPolicy.duelName(
            owner: String(repeating: "a", count: 100),
            opponent: String(repeating: "b", count: 100), branches: ["Løping", "Styrke"]).count, 80)
    }

    func testCompetitionCheckpointRestoresIncompleteRulesAndAccountIsolation() throws {
        let defaults = UserDefaults(suiteName: "athlth.test.competition.\(UUID())")!
        let key = "duel.test.running.true"
        var settings = ATHLTHTournamentCompetitionSettings()
        settings.selectedExerciseIDs = []
        settings.race.duelMode = true
        settings.completionHours = 72
        let draft = ATHLTHTournamentDraft(ownerID: owner, clubID: nil,
            title: "", format: .league, singleEventMode: true, groupSize: 4,
            qualifiersPerGroup: 2, participants: [.init(id: owner, username: "bruker1"),
                .init(id: rival, username: "bruker2")], allowedActivities: [.running, .strength],
            competitionSettings: settings)
        let checkpoint = ATHLTHCompetitionCreationCheckpoint(owner: owner, format: "duel",
            leagueStyle: .league, customTitle: "", opponents: [rival], rules: draft,
            inRules: true, scrollID: "timing")
        checkpoint.save(entry: key, defaults: defaults)
        let loaded = try XCTUnwrap(ATHLTHCompetitionCreationCheckpoint.load(owner: owner, entry: key, defaults: defaults))
        XCTAssertEqual(loaded.customTitle, "")
        XCTAssertEqual(loaded.opponents, [rival])
        XCTAssertEqual(loaded.rules?.id, draft.id)
        XCTAssertEqual(loaded.rules?.competitionSettings.completionHours, 72)
        XCTAssertEqual(loaded.rules?.competitionSettings.selectedExerciseIDs, [])
        XCTAssertEqual(loaded.scrollID, "timing")
        XCTAssertTrue(loaded.inRules)
        XCTAssertNil(ATHLTHCompetitionCreationCheckpoint.load(owner: rival, entry: key, defaults: defaults))
        ATHLTHCompetitionCreationCheckpoint.clear(owner: owner, entry: key, defaults: defaults)
        XCTAssertNil(ATHLTHCompetitionCreationCheckpoint.load(owner: owner, entry: key, defaults: defaults))
    }

    func testOnlyOperationalCompetitionBranchesCanBeSelected() throws {
        XCTAssertEqual(ATHLTHTournamentActivity.supportedForCreation, [.running, .walking, .strength])
        for format in ATHLTHCompetitionFormat.allCases {
            XCTAssertTrue(ATHLTHTournamentActivity.canCreate(with: [.running, .strength]), format.rawValue)
            for unavailable in [ATHLTHTournamentActivity.swimming, .hiking, .cycling] {
                XCTAssertFalse(unavailable.isAvailableForCreation)
                XCTAssertFalse(ATHLTHTournamentActivity.canCreate(with: [unavailable]), format.rawValue)
                XCTAssertFalse(ATHLTHTournamentActivity.canCreate(with: [.running, unavailable]), format.rawValue)
                let data = try JSONEncoder().encode(unavailable)
                XCTAssertEqual(try JSONDecoder().decode(ATHLTHTournamentActivity.self, from: data), unavailable)
            }
        }
        XCTAssertFalse(ATHLTHTournamentActivity.canCreate(with: []))
    }

    func testIncompleteParticipantStepIsResumableForEveryFormat() throws {
        let defaults = UserDefaults(suiteName: "athlth.test.competition.\(UUID())")!
        for format in ATHLTHCompetitionFormat.allCases {
            let key = format.rawValue + ".none.running.true"
            let checkpoint = ATHLTHCompetitionCreationCheckpoint(owner: owner, format: format.rawValue,
                leagueStyle: .league, customTitle: "", opponents: [rival], rules: nil,
                inRules: false, scrollID: nil)
            checkpoint.save(entry: key, defaults: defaults)
            let restored = try XCTUnwrap(ATHLTHCompetitionCreationCheckpoint.load(owner: owner, entry: key, defaults: defaults))
            XCTAssertTrue(restored.hasProgress)
            XCTAssertFalse(restored.inRules)
            XCTAssertEqual(restored.format, format.rawValue)
            XCTAssertNotNil(restored.updatedAt)
            ATHLTHCompetitionCreationCheckpoint.clear(owner: owner, entry: key, defaults: defaults)
        }
    }

    func testStudioCompetitionLayoutUsesActualDetailWidth() {
        XCTAssertFalse(ATHLTHCompetitionStudioLayout.usesColumns(width: 799, accessibilityText: false))
        XCTAssertTrue(ATHLTHCompetitionStudioLayout.usesColumns(width: 800, accessibilityText: false))
        XCTAssertFalse(ATHLTHCompetitionStudioLayout.usesColumns(width: 1200, accessibilityText: true))
        for width: CGFloat in [800, 850, 1000, 1350] {
            let content = width - 2 * ATHLTHCompetitionStudioLayout.padding
            let overview = ATHLTHCompetitionStudioLayout.overviewWidth(contentWidth: content)
            let remaining = content - overview - ATHLTHCompetitionStudioLayout.spacing
            XCTAssertGreaterThanOrEqual(overview, 285)
            XCTAssertGreaterThan(remaining, overview)
        }
    }

    func testStudioCompetitionFormatsAdaptToAvailableColumnWidth() {
        XCTAssertEqual(ATHLTHCompetitionStudioLayout.formatColumnCount(width: 469, accessibilityText: false), 1)
        XCTAssertEqual(ATHLTHCompetitionStudioLayout.formatColumnCount(width: 470, accessibilityText: false), 2)
        XCTAssertEqual(ATHLTHCompetitionStudioLayout.formatColumnCount(width: 800, accessibilityText: true), 1)
    }
}
