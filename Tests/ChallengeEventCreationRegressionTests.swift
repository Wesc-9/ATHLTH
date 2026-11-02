import XCTest
@testable import ATHLTH

final class ChallengeEventCreationRegressionTests:
    XCTestCase {
    func testAdvancedHillClimbThreshold() {
        let easy = ATHLTHChallengeHillThresholds.required(
            repetitions: 3, climbPerRepeatMeters: 5
        )
        XCTAssertEqual(easy.gain, 15)
        XCTAssertEqual(easy.descent, 8)
        let hard = ATHLTHChallengeHillThresholds.required(
            repetitions: 4, climbPerRepeatMeters: 20
        )
        XCTAssertEqual(hard.gain, 80)
        XCTAssertEqual(hard.descent, 36)
    }

    func testInvalidHillRuleUsesConservativeDefault() {
        let fallback = ATHLTHChallengeHillThresholds.required(
            repetitions: 0, climbPerRepeatMeters: .nan
        )
        XCTAssertEqual(fallback.gain, 8)
        XCTAssertEqual(fallback.descent, 4.8, accuracy: 0.0001)
    }


    func testChallengePreviewShowsCreatorWhenAlone() {
        XCTAssertEqual(
            ATHLTHChallengePreviewPeople.label(
                creatorName: "Stian", invitedNames: []
            ),
            "Stian"
        )
    }

    func testChallengePreviewShowsTwoNamesAndTotalCount() {
        XCTAssertEqual(
            ATHLTHChallengePreviewPeople.label(
                creatorName: "Stian", invitedNames: ["Malin"]
            ),
            "Stian vs Malin"
        )
    }

    func testChallengePreviewShowsThreeUsernames() {
        XCTAssertEqual(
            ATHLTHChallengePreviewPeople.label(
                creatorName: "stian", invitedNames: ["malin", "ola"]
            ),
            "stian vs malin vs ola"
        )
    }

    func testChallengePreviewShowsThreeUsernamesAndMoreForGroups() {
        XCTAssertEqual(
            ATHLTHChallengePreviewPeople.label(
                creatorName: "stian",
                invitedNames: ["malin", "ola", "kari", "per"]
            ),
            "stian vs malin vs ola · " + ATHLTHLocalization.choose(
                english: "and others", norwegian: "med flere"
            )
        )
    }

    func testChallengePreviewRemovesUsernameAtPrefixes() {
        XCTAssertEqual(
            ATHLTHChallengePreviewPeople.label(
                creatorName: "@runner1", invitedNames: ["@runner2"]
            ),
            "runner1 vs runner2"
        )
    }


    func testChallengeEndReminderIsNorwegianWithUsefulSubtitle() {
        let title = ATHLTHChallengeReminderText.title(
            for: .ending, norwegian: true
        )
        XCTAssertEqual(title, "Utfordringen avsluttes i morgen!")

        let message = ATHLTHChallengeReminderText.message(
            for: .ending, challengeTitle: "Løp 5 km",
            norwegian: true
        )
        XCTAssertTrue(message.contains("Løp 5 km"))
        XCTAssertTrue(message.contains("24 timer"))
        XCTAssertTrue(message.contains("fremdriften"))
    }

    func testOneWordOkIsNeverEntireReminderBody() {
        let message = ATHLTHChallengeReminderText.message(
            for: .ending, challengeTitle: " Ok ",
            norwegian: true
        )
        XCTAssertFalse(message.lowercased() == "ok")
        XCTAssertTrue(message.contains("24 timer"))
        XCTAssertFalse(message.contains("«Ok»"))
    }

    func testChallengeRemindersHaveProperEnglishCopy() {
        XCTAssertEqual(
            ATHLTHChallengeReminderText.title(for: .ending, norwegian: false),
            "Challenge ends tomorrow!"
        )
        let message = ATHLTHChallengeReminderText.message(
            for: .ending, challengeTitle: "5K",
            norwegian: false
        )
        XCTAssertTrue(message.contains("5K"))
        XCTAssertTrue(message.contains("24 hours"))
    }

    func testMeetupReminderMentionsMeetingPointInNorwegian() {
        XCTAssertEqual(
            ATHLTHChallengeReminderText.title(for: .meetup, norwegian: true),
            "Fellestreningen starter om én time"
        )
        let message = ATHLTHChallengeReminderText.message(
            for: .meetup, challengeTitle: "Ok",
            meetupPlace: "Torget", norwegian: true
        )
        XCTAssertTrue(message.contains("Torget"))
    }

    func testBlankChallengeNameUsesAutomaticTitle() {
        let resolved =
            ChallengeCreationPolicy
                .resolvedTitle(
                    "   ",
                    sport: .running,
                    scoring:
                        .fastestDistance
                )

        XCTAssertEqual(
            resolved,
            ChallengeCreationPolicy
                .automaticTitle(
                    sport: .running,
                    scoring:
                        .fastestDistance
                )
        )
    }

    func testCustomChallengeNameIsTrimmedAndBounded() {
        let input =
            "  " +
            String(
                repeating: "A",
                count: 90
            ) +
            "  "

        let resolved =
            ChallengeCreationPolicy
                .resolvedTitle(
                    input,
                    sport: .strength,
                    scoring:
                        .heaviestWeight
                )

        XCTAssertEqual(
            resolved.count,
            60
        )
        XCTAssertFalse(
            resolved.hasPrefix(" ")
        )
    }

    func testAutogeneratedDuelTitleContainsActivityNotAthletes() {
        let result = ChallengeCreationPolicy.resolvedTitle(
            "",
            sport: .running,
            scoring: .fastestDistance,
            creatorName: "Stian Johansen",
            invitedNames: ["Stian Test"],
            creatorUsername: "stianj",
            invitedUsernames: ["stian_test"]
        )
        let expected = ChallengeCreationPolicy.automaticTitle(
            sport: .running, scoring: .fastestDistance
        ).replacingOccurrences(of: " · ", with: " • ")
        XCTAssertEqual(result, expected)
        XCTAssertFalse(result.contains("stianj"))
        XCTAssertFalse(result.contains("stian_test"))
        XCTAssertFalse(result.contains("Johansen"))
    }

    func testAutogeneratedTitleSupportsSpecialRunningScoring() {
        let result = ChallengeCreationPolicy.resolvedTitle(
            "",
            sport: .running,
            scoring: .fastestDistance,
            creatorName: "Creator",
            invitedNames: ["Rival"],
            scoringTitle: "Løping • Raskest"
        )
        XCTAssertEqual(result, "Løping • Raskest")
    }

    func testManualChallengeTitleStillOverridesUsernameFormat() {
        let result = ChallengeCreationPolicy.resolvedTitle(
            "  Morgenløp  ",
            sport: .running,
            scoring: .fastestDistance,
            creatorName: "Fullt navn",
            invitedNames: ["Testnavn"],
            creatorUsername: "runner1",
            invitedUsernames: ["runner2"]
        )
        XCTAssertEqual(result, "Morgenløp")
    }

    func testChallengeTitleFallsBackWhenUsernameNotSet() {
        let result = ChallengeCreationPolicy.resolvedTitle(
            " ",
            sport: .running,
            scoring: .fastestDistance,
            creatorName: "Løper 1",
            invitedNames: ["Løper 2"],
            creatorUsername: "",
            invitedUsernames: [nil]
        )
        XCTAssertEqual(
            result,
            ChallengeCreationPolicy.automaticTitle(
                sport: .running, scoring: .fastestDistance
            ).replacingOccurrences(of: " · ", with: " • ")
        )
    }

    func testPublicChallengeDoesNotRequireDirectInvite() {
        XCTAssertFalse(
            ChallengeCreationPolicy
                .requiresDirectInvite(
                    visibility:
                        .publicProfile
                )
        )

        XCTAssertTrue(
            ChallengeCreationPolicy
                .requiresDirectInvite(
                    visibility:
                        .friends
                )
        )

        XCTAssertTrue(
            ChallengeCreationPolicy
                .requiresDirectInvite(
                    visibility:
                        .privateOnly
                )
        )
    }

    func testEventMayBeCreatedWithoutMeetingPoint() {
        let now =
            Date(
                timeIntervalSince1970:
                    1_800_000_000
            )
        var draft =
            CommunityEventDraft()
        draft.title = "Sunday run"
        draft.meetingName = ""
        draft.startsAt =
            now.addingTimeInterval(
                3_600
            )

        XCTAssertTrue(
            draft.isValidForCreation(
                now: now
            )
        )
    }

    func testEventStillRequiresTitleAndFutureStart() {
        let now =
            Date(
                timeIntervalSince1970:
                    1_800_000_000
            )
        var draft =
            CommunityEventDraft()
        draft.title = " "
        draft.startsAt =
            now.addingTimeInterval(
                3_600
            )

        XCTAssertFalse(
            draft.isValidForCreation(
                now: now
            )
        )

        draft.title = "Workout"
        draft.startsAt =
            now.addingTimeInterval(
                -1
            )

        XCTAssertFalse(
            draft.isValidForCreation(
                now: now
            )
        )
    }

    func testEventCoverDefaultsFollowActivity() {
        XCTAssertEqual(
            CommunityEventCoverPolicy
                .defaultArtwork(
                    for: .running
                ),
            "GoalRunning"
        )
        XCTAssertEqual(
            CommunityEventCoverPolicy
                .defaultArtwork(
                    for: .strength
                ),
            "GoalStrength"
        )
        XCTAssertEqual(
            CommunityEventCoverPolicy
                .defaultArtwork(
                    for: .hike
                ),
            "GoalMountain"
        )
    }


    func testLegacyChallengeRulesAllowGhostToolsByDefault() {
        let rules =
            ATHLTHChallengeRules(
                scoring:
                    .fastestDistance,
                verificationPolicy:
                    .verifiedRequired,
                targetDistanceMeters:
                    5_000,
                targetDurationSeconds:
                    nil,
                timeBasis:
                    .elapsed,
                route: nil,
                gpsRequired: true,
                minimumRouteMatchPercent:
                    nil,
                exerciseName: nil,
                fixedWeightKilograms:
                    nil,
                startsAt: Date(),
                endsAt: nil,
                allowMultipleAttempts:
                    true,
                lockRulesAtStart:
                    true,
                meetup: nil
            )

        XCTAssertTrue(
            rules.targetGhostAllowed
        )
        XCTAssertTrue(
            rules.liveGhostAllowed
        )
    }
}
