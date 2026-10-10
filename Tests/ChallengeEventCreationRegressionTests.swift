import XCTest
@testable import ATHLTH

final class ChallengeEventCreationRegressionTests:
    XCTestCase {
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
