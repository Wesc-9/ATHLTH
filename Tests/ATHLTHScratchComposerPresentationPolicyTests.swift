import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHScratchComposerPresentationPolicyTests: XCTestCase {
    private struct DraftPointer: Encodable {
        let id: UUID
    }

    func testDeletingStandaloneDraftAlsoRemovesBuilderCheckpointAndResumeAction() throws {
        let userID = UUID()
        let otherUserID = UUID()
        let draftID = UUID()
        let suiteName = "athlth.tests.scratch.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Cannot create isolated test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let parent = ATHLTHStandaloneWorkoutDraftStore.parentKey(for: userID)
        let child = ATHLTHStandaloneWorkoutDraftStore.childKey(
            for: userID, draftID: draftID
        )
        defaults.set(Data("parent".utf8), forKey: parent)
        defaults.set(try JSONEncoder().encode(DraftPointer(id: draftID)),
                     forKey: ATHLTHStandaloneWorkoutDraftStore.entryKey(for: userID))
        defaults.set(Data("builder".utf8), forKey: child)
        defaults.set(Data("another user's draft".utf8),
                     forKey: ATHLTHStandaloneWorkoutDraftStore.parentKey(for: otherUserID))

        XCTAssertTrue(ATHLTHStandaloneWorkoutDraftStore.hasDraft(
            for: userID, defaults: defaults
        ))
        ATHLTHStandaloneWorkoutDraftStore.discard(
            for: userID, defaults: defaults
        )
        XCTAssertFalse(ATHLTHStandaloneWorkoutDraftStore.hasDraft(
            for: userID, defaults: defaults
        ))
        XCTAssertNil(defaults.data(forKey: child))
        XCTAssertNotNil(defaults.data(forKey:
            ATHLTHStandaloneWorkoutDraftStore.parentKey(for: otherUserID)))
    }

    func testDeletingBuilderWithoutLegacyParentStillClearsResumeMarker() throws {
        let userID = UUID()
        let draftID = UUID()
        let suiteName = "athlth.tests.scratch.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Cannot create isolated test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(try JSONEncoder().encode(DraftPointer(id: draftID)),
                     forKey: ATHLTHStandaloneWorkoutDraftStore.entryKey(for: userID))
        defaults.set(Data("builder".utf8),
                     forKey: ATHLTHStandaloneWorkoutDraftStore.childKey(
                        for: userID, draftID: draftID))

        ATHLTHStandaloneWorkoutDraftStore.discard(
            for: userID, defaults: defaults
        )
        XCTAssertFalse(ATHLTHStandaloneWorkoutDraftStore.hasDraft(
            for: userID, defaults: defaults
        ))
        XCTAssertNil(defaults.data(forKey:
            ATHLTHStandaloneWorkoutDraftStore.childKey(
                for: userID, draftID: draftID)))
    }

    func testStandaloneScratchHidesOldFormWithoutHidingPartnerEditor() {
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy.hidesLegacyStandaloneHost(
            isStandalone: true, hasScratchSource: true,
            preparesForSharing: false, hasPartner: false
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.hidesLegacyStandaloneHost(
            isStandalone: true, hasScratchSource: false,
            preparesForSharing: false, hasPartner: false
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.hidesLegacyStandaloneHost(
            isStandalone: true, hasScratchSource: true,
            preparesForSharing: false, hasPartner: true
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.hidesLegacyStandaloneHost(
            isStandalone: false, hasScratchSource: true,
            preparesForSharing: false, hasPartner: false
        ))
    }

    func testScratchBackAlwaysOffersDeleteEvenWithEmptyTimeline() {
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy.requiresExitDecision(
            isScratchHost: true, hasEdits: false
        ))
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy.requiresExitDecision(
            isScratchHost: false, hasEdits: true
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.requiresExitDecision(
            isScratchHost: false, hasEdits: false
        ))
    }

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
