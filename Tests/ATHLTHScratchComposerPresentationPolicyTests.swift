import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHScratchComposerPresentationPolicyTests: XCTestCase {
    private struct DraftPointer: Encodable {
        let id: UUID
    }

    func testStandaloneNavigationStageRestoresTheSameChildForTheCorrectAccount() {
        let user = UUID()
        let anotherUser = UUID()
        let suite = "athlth.scratch.route.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Isolated defaults unavailable")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        ATHLTHStandaloneWorkoutDraftStore.setNavigationStage(
            .scratchBuilder, for: user, defaults: defaults
        )
        XCTAssertEqual(
            ATHLTHStandaloneWorkoutDraftStore.navigationStage(
                for: user, defaults: defaults
            ),
            .scratchBuilder
        )
        XCTAssertNil(ATHLTHStandaloneWorkoutDraftStore.navigationStage(
            for: anotherUser, defaults: defaults
        ))
        ATHLTHStandaloneWorkoutDraftStore.clearNavigationStage(
            for: anotherUser, defaults: defaults
        )
        XCTAssertEqual(
            ATHLTHStandaloneWorkoutDraftStore.navigationStage(
                for: user, defaults: defaults
            ),
            .scratchBuilder
        )
        ATHLTHStandaloneWorkoutDraftStore.clearNavigationStage(
            for: user, defaults: defaults
        )
        XCTAssertNil(ATHLTHStandaloneWorkoutDraftStore.navigationStage(
            for: user, defaults: defaults
        ))
    }

    func testNavigationStagesCoverSourceAndAllStandaloneEntryCards() {
        let suite = "athlth.scratch.route.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Isolated defaults unavailable")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let user = UUID()
        let stages: [ATHLTHStandaloneWorkoutDraftStore.NavigationStage] = [
            .source, .scratchTypePicker, .scratchBuilder,
            .savedWorkoutPicker, .recoveryRestPlanner, .legacyEditor
        ]
        for stage in stages {
            ATHLTHStandaloneWorkoutDraftStore.setNavigationStage(
                stage, for: user, defaults: defaults
            )
            XCTAssertEqual(
                ATHLTHStandaloneWorkoutDraftStore.navigationStage(
                    for: user, defaults: defaults
                ),
                stage
            )
        }
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

    func testFriendScratchHidesLegacyFormBehindNewBuilder() {
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy.hidesLegacyStandaloneHost(
            isStandalone: true,
            hasScratchSource: true,
            preparesForSharing: false,
            hasPartner: true,
            builderIsPresented: true
        ))
        // After Save and continue the timeline is no longer showing. The
        // partner confirmation has its own compact review, not the old Form.
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy.showsPartnerInvitationReview(
            isStandalone: true,
            hasPartner: true,
            hasScratchSource: true,
            preparesForSharing: false,
            builderIsPresented: false
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.showsPartnerInvitationReview(
            isStandalone: true,
            hasPartner: true,
            hasScratchSource: false,
            preparesForSharing: false,
            builderIsPresented: false
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.showsPartnerInvitationReview(
            isStandalone: true,
            hasPartner: true,
            hasScratchSource: true,
            preparesForSharing: false,
            builderIsPresented: true
        ))
    }

    func testFriendInviteFixDoesNotBypassExistingSharingOrPlanEdits() {
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.hidesLegacyStandaloneHost(
            isStandalone: true,
            hasScratchSource: true,
            preparesForSharing: true,
            hasPartner: true,
            builderIsPresented: true
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.showsPartnerInvitationReview(
            isStandalone: true,
            hasPartner: true,
            hasScratchSource: true,
            preparesForSharing: true,
            builderIsPresented: false
        ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy.showsPartnerInvitationReview(
            isStandalone: false,
            hasPartner: true,
            hasScratchSource: true,
            preparesForSharing: false,
            builderIsPresented: false
        ))
    }

    func testSharedComposerIsOnlyVisibleWorkoutEditorAcrossAllSources() {
        // A common builder takes the frontmost position in Home, existing
        // plans, invited workouts and Train Together marketplace proposals.
        for isStandalone in [false, true] {
            for hasScratch in [false, true] {
                for sharing in [false, true] {
                    for hasPartner in [false, true] {
                        XCTAssertTrue(
                            ATHLTHScratchComposerPresentationPolicy
                                .hidesLegacyStandaloneHost(
                                    isStandalone: isStandalone,
                                    hasScratchSource: hasScratch,
                                    preparesForSharing: sharing,
                                    hasPartner: hasPartner,
                                    builderIsPresented: true
                                )
                        )
                    }
                }
            }
        }
        // Closing the composer restores an ordinary existing-plan editor,
        // not a persistent blank screen.
        XCTAssertFalse(
            ATHLTHScratchComposerPresentationPolicy
                .hidesLegacyStandaloneHost(
                    isStandalone: false,
                    hasScratchSource: false,
                    preparesForSharing: false,
                    hasPartner: false,
                    builderIsPresented: false
                )
        )
    }

    func testTrainTogetherMarketplaceScratchHandsOffWithoutLegacyForm() {
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy
            .preparesSharedScratchDirectly(
                isStandalone: true,
                hasScratchSource: true,
                preparesForSharing: true
            ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .preparesSharedScratchDirectly(
                isStandalone: true,
                hasScratchSource: false,
                preparesForSharing: true
            ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .preparesSharedScratchDirectly(
                isStandalone: true,
                hasScratchSource: true,
                preparesForSharing: false
            ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .preparesSharedScratchDirectly(
                isStandalone: false,
                hasScratchSource: true,
                preparesForSharing: true
            ))
    }

    func testPickerToEditorHandoffRequiresDismissal() {
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .opensQueuedEditorAfterPickerDismiss(
                queued: true, pickerIsPresented: true
            ))
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .opensQueuedEditorAfterPickerDismiss(
                queued: false, pickerIsPresented: false
            ))
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy
            .opensQueuedEditorAfterPickerDismiss(
                queued: true, pickerIsPresented: false
            ))
    }

    func testQuickRunHidesObsoleteSetupOnlyWhileSharedEditorIsOpen() {
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .showsQuickSetupBehindComposer(composerIsPresented: true))
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy
            .showsQuickSetupBehindComposer(composerIsPresented: false))
    }

    func testPlanStudioSceneRestoreNeverPresentsBothSessionEditors() {
        let both = ATHLTHScratchComposerPresentationPolicy
            .exclusiveEditorRestoration(standalone: true, day: true)
        XCTAssertTrue(both.standalone)
        XCTAssertFalse(both.day)

        let dayOnly = ATHLTHScratchComposerPresentationPolicy
            .exclusiveEditorRestoration(standalone: false, day: true)
        XCTAssertFalse(dayOnly.standalone)
        XCTAssertTrue(dayOnly.day)

        let alone = ATHLTHScratchComposerPresentationPolicy
            .exclusiveEditorRestoration(standalone: true, day: false)
        XCTAssertTrue(alone.standalone)
        XCTAssertFalse(alone.day)

        let none = ATHLTHScratchComposerPresentationPolicy
            .exclusiveEditorRestoration(standalone: false, day: false)
        XCTAssertFalse(none.standalone)
        XCTAssertFalse(none.day)
    }

    func testStrengthLiveWaitsUntilSetupSheetHasDismissed() {
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .startsLiveAfterSetupDismiss(
                queued: true, setupIsPresented: true
            ), "The active recorder must not stack over the setup sheet")
        XCTAssertFalse(ATHLTHScratchComposerPresentationPolicy
            .startsLiveAfterSetupDismiss(
                queued: false, setupIsPresented: false
            ), "Cancelling or a failed start must not open live recording")
        XCTAssertTrue(ATHLTHScratchComposerPresentationPolicy
            .startsLiveAfterSetupDismiss(
                queued: true, setupIsPresented: false
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
