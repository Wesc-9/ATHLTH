import XCTest
@testable import ATHLTH

final class ATHLTHScratchComposerPresentationPolicyTests: XCTestCase {
    func testSoloScratchSessionSavesWithoutLegacySecondScreen() {
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy.savesDirectly(
            isStandalone: true,
            preparesForSharing: false,
            hasPartner: false,
            targetsActivePlan: false
        ))
    }

    func testPartnerPlanAndProposalKeepTheirOriginalConfirmation() {
        let cases: [(Bool, Bool, Bool, Bool)] = [
            (true, true, false, false),
            (true, false, true, false),
            (true, false, false, true),
            (false, false, false, false)
        ]
        for (standalone, sharing, partner, plan) in cases {
            XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.savesDirectly(
                isStandalone: standalone,
                preparesForSharing: sharing,
                hasPartner: partner,
                targetsActivePlan: plan
            ))
        }
    }

    func testUnfinishedScratchComposerRestoresAfterBackgrounding() {
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy.shouldRestoreOnWake(
            isStandalone: true,
            hasScratchSource: true,
            builderWasPresented: true,
            isFinalized: false
        ))
    }

    func testCancelledOrCommittedComposerNeverAutoRestores() {
        let cases: [(Bool, Bool, Bool, Bool)] = [
            (true, true, false, false),
            (true, true, true, true),
            (true, false, true, false),
            (false, true, true, false)
        ]
        for (standalone, hasScratch, presented, finalized) in cases {
            XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.shouldRestoreOnWake(
                isStandalone: standalone,
                hasScratchSource: hasScratch,
                builderWasPresented: presented,
                isFinalized: finalized
            ))
        }
    }
}
