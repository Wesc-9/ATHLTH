import Foundation
import XCTest
@testable import ATHLTH

final class ChallengeAcceptanceScoringTests: XCTestCase {
    private let originalStart = Date(timeIntervalSince1970: 1_800_000_000)
    private var acceptedAt: Date { originalStart.addingTimeInterval(1_800) }

    private func challenge(
        inviteState: ChallengeParticipantState = .invited,
        response: Date? = nil,
        status: ATHLTHChallengeStatus = .invited
    ) -> ATHLTHChallenge {
        let owner = UUID()
        let guest = UUID()
        let rules = ATHLTHChallengeRules(
            scoring: .mostDistance,
            verificationPolicy: .verifiedRequired,
            targetDistanceMeters: nil,
            targetDurationSeconds: nil,
            timeBasis: .elapsed,
            route: nil,
            gpsRequired: false,
            minimumRouteMatchPercent: nil,
            exerciseName: nil,
            fixedWeightKilograms: nil,
            startsAt: originalStart,
            endsAt: originalStart.addingTimeInterval(7_200),
            allowMultipleAttempts: true,
            lockRulesAtStart: false,
            meetup: nil
        )
        return ATHLTHChallenge(
            creatorID: owner,
            title: "Running duel",
            sport: .running,
            status: status,
            participants: [
                ChallengeParticipant(userID: owner, displayName: "Owner", state: .creator),
                ChallengeParticipant(
                    userID: guest,
                    displayName: "Guest",
                    state: inviteState,
                    respondedAt: response
                )
            ],
            rules: rules,
            visibility: .privateOnly
        )
    }

    private func attempt(
        _ challenge: ATHLTHChallenge,
        participantID: UUID,
        startedAt: Date?,
        verification: ChallengeAttemptVerification = .athlth,
        submittedAt: Date? = nil
    ) -> ChallengeAttempt {
        ChallengeAttempt(
            id: UUID(),
            challengeID: challenge.id,
            participantID: participantID,
            userID: nil,
            participantName: "Athlete",
            submittedAt: submittedAt ?? acceptedAt.addingTimeInterval(1_200),
            startedAt: startedAt,
            endedAt: startedAt?.addingTimeInterval(600),
            verification: verification,
            sourceWorkoutID: UUID(),
            durationSeconds: 600,
            distanceMeters: 3_000,
            weightKilograms: nil,
            reps: nil,
            volumeKilograms: nil,
            routeMatchPercent: nil,
            score: 3_000,
            detail: "Run",
            manualNote: nil,
            isEligible: true,
            ineligibilityReason: nil
        )
    }

    func testInvitedOrDeclinedOpponentNeverUnlocksWorkoutScoring() {
        for state: ChallengeParticipantState in [.invited, .declined, .withdrawn] {
            let subject = challenge(inviteState: state)
            XCTAssertNil(subject.scoringStartDate)
            XCTAssertFalse(
                subject.canCountWorkout(
                    startedAt: acceptedAt.addingTimeInterval(600),
                    participantID: subject.participants[0].id
                )
            )
        }
    }

    func testAcceptanceTimeOverridesEarlierScheduledStart() {
        let subject = challenge(inviteState: .accepted, response: acceptedAt, status: .active)
        XCTAssertEqual(subject.scoringStartDate, acceptedAt)
        XCTAssertFalse(subject.canCountWorkout(
            startedAt: acceptedAt.addingTimeInterval(-1),
            participantID: subject.participants[0].id
        ))
        XCTAssertTrue(subject.canCountWorkout(
            startedAt: acceptedAt,
            participantID: subject.participants[0].id
        ))
        XCTAssertTrue(subject.canCountWorkout(
            startedAt: acceptedAt.addingTimeInterval(600),
            participantID: subject.participants[1].id
        ))
    }

    func testOldWorkoutUploadedAfterAcceptanceStillDoesNotCount() {
        let subject = challenge(inviteState: .accepted, response: acceptedAt, status: .active)
        let history = attempt(
            subject,
            participantID: subject.participants[0].id,
            startedAt: acceptedAt.addingTimeInterval(-600),
            submittedAt: acceptedAt.addingTimeInterval(1_000)
        )
        XCTAssertFalse(subject.countsAttempt(history))
    }

    func testGuestCannotCountTrainingBeforeTheirOwnAcceptance() {
        var subject = challenge(inviteState: .accepted, response: acceptedAt, status: .active)
        let laterGuest = ChallengeParticipant(
            userID: UUID(),
            displayName: "Later guest",
            state: .accepted,
            respondedAt: acceptedAt.addingTimeInterval(900)
        )
        subject.participants.append(laterGuest)
        XCTAssertFalse(subject.canCountWorkout(
            startedAt: acceptedAt.addingTimeInterval(600),
            participantID: laterGuest.id
        ))
        XCTAssertTrue(subject.canCountWorkout(
            startedAt: acceptedAt.addingTimeInterval(900),
            participantID: laterGuest.id
        ))
    }

    func testMissingAcceptanceTimestampFailsClosed() {
        let subject = challenge(inviteState: .accepted, response: nil)
        XCTAssertNil(subject.scoringStartDate)
    }

    func testManualAttemptUsesSubmissionTimeButVerifiedRequiresWorkoutStart() {
        let subject = challenge(inviteState: .accepted, response: acceptedAt, status: .active)
        let user = subject.participants[0].id
        let manual = attempt(subject, participantID: user, startedAt: nil, verification: .manual)
        XCTAssertTrue(subject.countsAttempt(manual))
        let invalidVerified = attempt(subject, participantID: user, startedAt: nil)
        XCTAssertFalse(subject.countsAttempt(invalidVerified))
    }

    func testInvalidAfterAcceptanceAttemptRemainsVisibleButUnscored() {
        let subject = challenge(inviteState: .accepted, response: acceptedAt, status: .active)
        var attempted = attempt(
            subject,
            participantID: subject.participants[0].id,
            startedAt: acceptedAt.addingTimeInterval(300)
        )
        attempted.isEligible = false
        attempted.ineligibilityReason = "Route mismatch"
        XCTAssertTrue(subject.showsAttempt(attempted))
        XCTAssertFalse(subject.countsAttempt(attempted))
    }

    func testPreAcceptanceAttemptDoesNotAppearEvenIfUploadedLater() {
        let subject = challenge(inviteState: .accepted, response: acceptedAt, status: .active)
        let early = attempt(
            subject,
            participantID: subject.participants[0].id,
            startedAt: acceptedAt.addingTimeInterval(-300),
            submittedAt: acceptedAt.addingTimeInterval(900)
        )
        XCTAssertFalse(subject.showsAttempt(early))
        XCTAssertFalse(subject.countsAttempt(early))
    }

    func testCancelledChallengeAndEndedWindowRejectAttempts() {
        let cancelled = challenge(inviteState: .accepted, response: acceptedAt, status: .cancelled)
        XCTAssertNil(cancelled.scoringStartDate)
        let live = challenge(inviteState: .accepted, response: acceptedAt, status: .active)
        XCTAssertFalse(live.canCountWorkout(
            startedAt: originalStart.addingTimeInterval(7_201),
            participantID: live.participants[0].id
        ))
    }
}
