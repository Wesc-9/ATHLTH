import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHLiveGhostFinishConfirmationTests: XCTestCase {
    private let challenge = UUID()
    private let finished = Date(timeIntervalSince1970: 1_800_000_000)

    private func confirms(
        challengeID: UUID? = nil,
        finishedAt: Date? = nil,
        recordedSeconds: TimeInterval?,
        submittedSeconds: TimeInterval = 1_200
    ) -> Bool {
        ATHLTHLiveGhostFinishConfirmation.matches(
            challengeID: challengeID ?? challenge,
            expectedChallengeID: challenge,
            finishedAt: finishedAt ?? finished,
            recordedSeconds: recordedSeconds,
            submittedSeconds: submittedSeconds
        )
    }

    func testExactPersistedFinishMatches() {
        XCTAssertTrue(confirms(recordedSeconds: 1_200))
    }

    func testSmallSerializationDifferenceIsAccepted() {
        XCTAssertTrue(confirms(recordedSeconds: 1_200.02))
    }

    func testFirstDifferentImmutableResultMustNotBeReportedAsOurSuccess() {
        XCTAssertFalse(confirms(recordedSeconds: 1_220))
    }

    func testAnotherDuelsFinishNeverConfirmsThisDuel() {
        XCTAssertFalse(confirms(challengeID: UUID(), recordedSeconds: 1_200))
    }

    func testMissingFinishCannotConfirmEvenWhenDurationMatches() {
        XCTAssertFalse(ATHLTHLiveGhostFinishConfirmation.matches(
            challengeID: challenge,
            expectedChallengeID: challenge,
            finishedAt: nil,
            recordedSeconds: 1_200,
            submittedSeconds: 1_200
        ))
    }

    func testMissingAndNonFiniteDurationsCannotConfirm() {
        XCTAssertFalse(confirms(recordedSeconds: nil))
        XCTAssertFalse(confirms(recordedSeconds: .nan))
        XCTAssertFalse(confirms(recordedSeconds: 1_200, submittedSeconds: .infinity))
    }
}
