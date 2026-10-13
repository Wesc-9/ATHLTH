import Foundation
import XCTest
@testable import ATHLTH

final class CommunityTrainTogetherAgendaTests: XCTestCase {
    private func post(
        host: UUID,
        date: Date,
        status: TrainTogetherPostStatus = .open
    ) -> TrainTogetherPost {
        TrainTogetherPost(
            id: UUID(),
            creatorID: host,
            creatorDisplayName: "Athlete",
            creatorUsername: nil,
            creatorAvatarURL: nil,
            title: "Morning run",
            workoutKind: "running",
            scheduledStart: date,
            durationMinutes: 40,
            distanceKilometers: 5,
            level: "all",
            broadArea: "Bodø",
            note: nil,
            maxGuests: 5,
            acceptedGuests: 1,
            status: status,
            participationMode: .physical,
            joinPolicy: .request,
            workoutPayload: nil,
            sourcePlannedSessionID: nil,
            socialWorkoutSessionID: nil,
            createdAt: Date(),
            updatedAt: nil
        )
    }

    private func request(
        for post: TrainTogetherPost,
        athlete: UUID,
        state: TrainTogetherRequestState
    ) -> TrainTogetherRequest {
        TrainTogetherRequest(
            id: UUID(),
            postID: post.id,
            requesterID: athlete,
            requesterDisplayName: "Guest",
            requesterUsername: nil,
            requesterAvatarURL: nil,
            message: nil,
            state: state,
            createdAt: Date(),
            respondedAt: nil,
            updatedAt: nil
        )
    }

    func testHostAndAcceptedParticipantSeeTheirUpcomingWorkout() {
        let host = UUID()
        let guest = UUID()
        let now = Date()
        let entry = post(host: host, date: now.addingTimeInterval(3600))
        let accepted = request(for: entry, athlete: guest, state: .accepted)
        let policy = ATHLTHCommunityAgendaPolicy.includesTrainTogetherPost

        XCTAssertTrue(policy(entry, [], host, now))
        XCTAssertTrue(policy(entry, [accepted], guest, now))
        XCTAssertFalse(policy(entry, [], guest, now))
    }

    func testPendingDeclinedAndUnrelatedRequestsAreExcluded() {
        let host = UUID()
        let guest = UUID()
        let now = Date()
        let entry = post(host: host, date: now.addingTimeInterval(3600))
        let pending = request(for: entry, athlete: guest, state: .pending)
        let declined = request(for: entry, athlete: guest, state: .declined)
        let stranger = request(for: entry, athlete: UUID(), state: .accepted)

        XCTAssertFalse(ATHLTHCommunityAgendaPolicy.includesTrainTogetherPost(
            entry, requests: [pending, declined, stranger],
            userID: guest, now: now
        ))
    }

    func testPastCancelledAndCompletedPostsNeverAppear() {
        let host = UUID()
        let now = Date()
        for status in [TrainTogetherPostStatus.cancelled, .completed] {
            let entry = post(
                host: host,
                date: now.addingTimeInterval(3600),
                status: status
            )
            XCTAssertFalse(ATHLTHCommunityAgendaPolicy.includesTrainTogetherPost(
                entry, requests: [], userID: host, now: now
            ))
        }
        let old = post(host: host, date: now.addingTimeInterval(-3600))
        XCTAssertFalse(ATHLTHCommunityAgendaPolicy.includesTrainTogetherPost(
            old, requests: [], userID: host, now: now
        ))
    }

    func testPublicWorkoutsDoNotLeakIntoPersonalAgenda() {
        let host = UUID()
        let now = Date()
        let publicWorkout = post(host: host, date: now.addingTimeInterval(3600))
        let entries = ATHLTHCommunityAgendaPolicy.entries(
            events: [], clubEvents: [], clubRSVPs: [],
            clubs: [], challenges: [],
            trainTogetherPosts: [publicWorkout], trainTogetherRequests: [],
            userID: UUID(), now: now
        )
        XCTAssertTrue(entries.isEmpty)
    }
    func testClubChallengeMustBeJoinedWhenEnrollmentRequired() {
        let now = Date()
        let end = now.addingTimeInterval(3600)
        let host = UUID()
        let guest = UUID()
        let check = ATHLTHCommunityAgendaPolicy.includesClubChallenge

        XCTAssertTrue(check(
            now, end, "active", host, host,
            true, nil, now
        ))
        XCTAssertTrue(check(
            now, end, "active", host, guest,
            true, "joined", now
        ))
        XCTAssertFalse(check(
            now, end, "active", host, guest,
            true, nil, now
        ))
        XCTAssertFalse(check(
            now, end, "active", host, guest,
            true, "declined", now
        ))
        XCTAssertTrue(check(
            now, end, "active", host, guest,
            false, nil, now
        ))
    }

    func testClubChallengeExcludesExpiredDraftCancelledAndCompleted() {
        let now = Date()
        let host = UUID()
        let check = ATHLTHCommunityAgendaPolicy.includesClubChallenge
        for status in ["draft", "cancelled", "completed"] {
            XCTAssertFalse(check(
                now, now.addingTimeInterval(3600), status,
                host, host, false, nil, now
            ))
        }
        XCTAssertFalse(check(
            now.addingTimeInterval(-7200), now.addingTimeInterval(-3600),
            "active", host, host, false, nil, now
        ))
    }

}
