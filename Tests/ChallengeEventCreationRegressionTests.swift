import XCTest
@testable import ATHLTH

final class ChallengeEventCreationRegressionTests:
    XCTestCase {
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
}
