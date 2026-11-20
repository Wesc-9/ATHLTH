import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHWatchWorkoutOwnershipTests: XCTestCase {
    private func completedResult() -> WatchWorkoutResult {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return WatchWorkoutResult(
            id: UUID(), kind: .running,
            healthKitWorkoutUUID: UUID(),
            startedAt: date, endedAt: date.addingTimeInterval(900),
            duration: 900, activeCalories: 100,
            distanceMeters: 2_200, averageHeartRate: 135,
            maxHeartRate: 158, routePointCount: 0
        )
    }

    func testMatchingSignedInOwnerAcceptsDelayedWatchResult() {
        let owner = UUID()
        XCTAssertTrue(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: owner, signedInUserID: owner
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: owner, signedInUserID: UUID()
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: owner, signedInUserID: nil
        ))
    }

    func testLegacyUnownedWatchResultIsNotSilentlyAssigned() throws {
        let owner = UUID()
        let legacy = completedResult()
        let bytes = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(WatchWorkoutResult.self, from: bytes)
        XCTAssertNil(decoded.accountOwnerID)
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: decoded.accountOwnerID,
            signedInUserID: owner
        ))
    }

    func testPlannedOfflineWatchResultNeedsSameOwnerAndSameCalendarID() throws {
        let owner = UUID(), planned = UUID()
        var result = completedResult()
        result.accountOwnerID = owner
        result.plannedCalendarSessionID = planned
        result.universalWorkoutID = UUID()
        let replay = try JSONDecoder().decode(
            WatchWorkoutResult.self,
            from: JSONEncoder().encode(result)
        )
        XCTAssertEqual(replay.plannedCalendarSessionID, planned)
        XCTAssertEqual(replay.accountOwnerID, owner)
        XCTAssertTrue(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: replay.accountOwnerID, signedInUserID: owner
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: replay.accountOwnerID, signedInUserID: UUID()
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: replay.accountOwnerID, signedInUserID: nil
        ))
        XCTAssertFalse(
            ATHLTHWatchPlannedCompletionIdentityPolicy.allowsLegacyTimeMatch(
                calendarSessionID: replay.plannedCalendarSessionID,
                structuredSourceID: replay.structuredWorkoutSourceID
            )
        )
        result.accountOwnerID = nil
        XCTAssertFalse(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: result.accountOwnerID, signedInUserID: owner
        ))
    }

    func testOwnerSurvivesWatchResultEncodingAndQueuedDelivery() throws {
        let owner = UUID()
        var result = completedResult()
        result.accountOwnerID = owner
        let bytes = try JSONEncoder().encode([result])
        let decoded = try JSONDecoder().decode([WatchWorkoutResult].self, from: bytes)
        XCTAssertEqual(decoded.first?.accountOwnerID, owner)
        XCTAssertTrue(ATHLTHWatchWorkoutOwnershipPolicy.canApply(
            resultOwnerID: decoded.first?.accountOwnerID,
            signedInUserID: owner
        ))
    }

    func testCompanionLogoutCanExplicitlyClearIdentity() throws {
        let identity = WatchAccountIdentityTransfer(
            ownerID: nil, updatedAt: Date()
        )
        let decoded = try JSONDecoder().decode(
            WatchAccountIdentityTransfer.self,
            from: JSONEncoder().encode(identity)
        )
        XCTAssertNil(decoded.ownerID)
    }
    func testCompletedWatchResultKeepsOriginalATHLTHIdentityOffline() throws {
        var result = completedResult()
        let originalID = UUID()
        result.universalWorkoutID = originalID
        let decoded = try JSONDecoder().decode(
            WatchWorkoutResult.self, from: JSONEncoder().encode(result)
        )
        XCTAssertEqual(decoded.universalWorkoutID, originalID)
        XCTAssertNotEqual(decoded.universalWorkoutID, decoded.id)
        XCTAssertNotEqual(decoded.universalWorkoutID, decoded.healthKitWorkoutUUID)
        XCTAssertNil(completedResult().universalWorkoutID)
    }


    func testSameHealthKitWorkoutCannotBeQueuedWithNewReceipt() {
        let recorded = completedResult()
        var deliveredAgain = completedResult()
        deliveredAgain.healthKitWorkoutUUID = recorded.healthKitWorkoutUUID
        XCTAssertNotEqual(recorded.id, deliveredAgain.id)
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            recorded, handledReceiptIDs: [],
            handledOriginalIDs: [], pending: []
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            deliveredAgain, handledReceiptIDs: [],
            handledOriginalIDs: [], pending: [recorded]
        ))
        XCTAssertFalse(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            deliveredAgain, handledReceiptIDs: [recorded.id],
            handledOriginalIDs: [recorded.healthKitWorkoutUUID!],
            pending: []
        ))
    }

    func testRecoveryCollapsesDuplicateOfflineWatchResultDelivery() {
        let first = completedResult()
        var replay = completedResult()
        replay.healthKitWorkoutUUID = first.healthKitWorkoutUUID
        let recovered = ATHLTHWatchWorkoutResultIdentity.restorePending(
            [replay, first],
            handledReceiptIDs: [], handledOriginalIDs: []
        )
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.healthKitWorkoutUUID,
                       first.healthKitWorkoutUUID)
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.restorePending(
            [replay], handledReceiptIDs: [],
            handledOriginalIDs: [first.healthKitWorkoutUUID!]
        ).isEmpty)
    }

    func testLegacySourceFallbackAndTwoDistinctWorkoutsStayDistinct() {
        var first = completedResult()
        var second = completedResult()
        first.healthKitWorkoutUUID = nil
        second.healthKitWorkoutUUID = nil
        let identity = UUID()
        first.universalWorkoutID = identity
        second.universalWorkoutID = identity
        XCTAssertEqual(ATHLTHWatchWorkoutResultIdentity.originalID(first),
                       identity)
        XCTAssertFalse(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            second, handledReceiptIDs: [], handledOriginalIDs: [],
            pending: [first]
        ))
        second.universalWorkoutID = UUID()
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            second, handledReceiptIDs: [], handledOriginalIDs: [],
            pending: [first]
        ))
        second.universalWorkoutID = nil
        first.universalWorkoutID = nil
        XCTAssertTrue(ATHLTHWatchWorkoutResultIdentity.shouldEnqueue(
            second, handledReceiptIDs: [], handledOriginalIDs: [],
            pending: [first]
        ), "Legacy unknown originals can use their distinct receipt IDs")
    }


    func testWatchFinishCanPublishOnlyOnceForOriginalHealthKitSession() {
        let began = Date(timeIntervalSince1970: 1_900_000_000)
        let policy = ATHLTHWatchResultPublicationPolicy.self
        func mayPublish(
            finishing: Bool = true, ending: Bool = true,
            published: Bool = false, originalStart: Date? = nil,
            hkStart: Date? = nil, end: Date? = nil
        ) -> Bool {
            policy.mayPublish(
                finishing: finishing, ending: ending,
                hasPublishedResult: published,
                originalStartedAt: originalStart ?? began,
                healthKitStartedAt: hkStart ?? began,
                endedAt: end ?? began.addingTimeInterval(600)
            )
        }
        XCTAssertTrue(mayPublish())
        XCTAssertFalse(mayPublish(finishing: false))
        XCTAssertFalse(mayPublish(ending: false))
        XCTAssertFalse(mayPublish(published: true))
        XCTAssertFalse(mayPublish(
            hkStart: began.addingTimeInterval(45)
        ), "Delayed previous workout cannot close a newer recording")
        XCTAssertFalse(mayPublish(
            end: began.addingTimeInterval(-1)
        ))
        XCTAssertTrue(mayPublish(
            hkStart: began.addingTimeInterval(1)
        ), "Minor HealthKit start jitter is permissible")
    }

    func testWatchFinishWithoutOriginalStartCannotEmitUnknownResult() {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertFalse(ATHLTHWatchResultPublicationPolicy.mayPublish(
            finishing: true, ending: true,
            hasPublishedResult: false,
            originalStartedAt: nil,
            healthKitStartedAt: start,
            endedAt: start.addingTimeInterval(180)
        ))
    }


    func testPreparedWatchCardCannotBeConsumedByAnotherActiveSession() {
        let expected = UUID()
        let unrelated = UUID()
        func confirms(
            _ acknowledged: UUID?,
            _ live: UUID?,
            requested: WatchWorkoutKind = .running,
            active: WatchWorkoutKind = .running,
            recording: Bool = true
        ) -> Bool {
            ATHLTHWatchPreparedLaunchConfirmationPolicy.confirms(
                acknowledgedWorkoutID: acknowledged,
                currentWorkoutID: live,
                requestedKind: requested,
                activeKind: active,
                isRecording: recording
            )
        }
        XCTAssertTrue(confirms(expected, expected))
        XCTAssertFalse(confirms(nil, expected),
                       "Denied start cannot acknowledge a competing recording")
        XCTAssertFalse(confirms(expected, unrelated),
                       "A different HealthKit owner cannot consume this card")
        XCTAssertFalse(confirms(expected, nil),
                       "A missing original ID must fail closed")
        XCTAssertFalse(confirms(expected, expected, recording: false),
                       "Preparing, ending or failed is not a started workout")
        XCTAssertFalse(confirms(expected, expected, active: .cycling),
                       "A different sport cannot acknowledge the prepared card")
        XCTAssertFalse(confirms(expected, expected, requested: .strength))
    }

    func testTodayWatchLaunchUsesSamePreparedHealthKitAdmissionAcrossSports() throws {
        let planID = UUID(), scheduledID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let routeID = UUID()
        for kind in WatchWorkoutKind.allCases where kind != .strength {
            let today = WatchTodayWorkoutTransfer(
                planID: planID, workoutID: scheduledID,
                title: "Original planned session",
                summary: "Preserve original recipe",
                kind: kind, scheduledStart: capturedAt,
                durationMinutes: 35, distanceKilometers: 6,
                routeID: kind == .running ? routeID : nil,
                runningWorkout: nil, audioCoach: .disabled,
                updatedAt: capturedAt
            )
            guard let prepared = ATHLTHWatchTodayLaunchAdapter.prepared(
                from: today
            ) else {
                XCTFail("The existing HealthKit sport was discarded: \\(kind)")
                continue
            }
            XCTAssertNotEqual(prepared.id, scheduledID,
                              "A transport card is never the workout ID")
            XCTAssertEqual(prepared.plannedPlanID, planID)
            XCTAssertEqual(prepared.plannedSessionID, scheduledID)
            XCTAssertEqual(prepared.kind, kind)
            XCTAssertEqual(prepared.routeID, today.routeID)
            XCTAssertEqual(prepared.updatedAt, capturedAt)
            XCTAssertEqual(prepared.startMode, .onWatch)
            XCTAssertTrue(ATHLTHWatchPreparedPlanIdentityPolicy.allows(
                planID: prepared.plannedPlanID,
                sessionID: prepared.plannedSessionID
            ))
            let copied = try JSONDecoder().decode(
                WatchPreparedWorkoutTransfer.self,
                from: JSONEncoder().encode(prepared)
            )
            XCTAssertEqual(copied, prepared)
        }
    }

    func testTodayPlannedStrengthCannotDiscardMissingExerciseRecipe() {
        let today = WatchTodayWorkoutTransfer(
            planID: UUID(), workoutID: UUID(),
            title: "Original strength session",
            summary: "Five planned exercises",
            kind: .strength, scheduledStart: nil,
            durationMinutes: 45, distanceKilometers: nil,
            routeID: nil, runningWorkout: nil,
            audioCoach: .disabled, updatedAt: Date()
        )
        XCTAssertNil(ATHLTHWatchTodayLaunchAdapter.prepared(from: today),
                     "Never launch free strength instead of the missing saved recipe")
    }

    func testTodayLaunchReceiptsDedupeOnlyOriginalAccountAndSession() {
        let id = UUID(), owner = UUID(), anotherOwner = UUID()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let receipts = [ATHLTHWatchTodayLaunchReceipt(
            sessionID: id, ownerID: owner, confirmedAt: now
        )]
        XCTAssertTrue(ATHLTHWatchTodayReplayPolicy.wasConfirmed(
            sessionID: id, ownerID: owner,
            receipts: receipts, now: now.addingTimeInterval(10)
        ))
        XCTAssertFalse(ATHLTHWatchTodayReplayPolicy.wasConfirmed(
            sessionID: id, ownerID: anotherOwner,
            receipts: receipts, now: now.addingTimeInterval(10)
        ))
        XCTAssertFalse(ATHLTHWatchTodayReplayPolicy.wasConfirmed(
            sessionID: UUID(), ownerID: owner,
            receipts: receipts, now: now.addingTimeInterval(10)
        ))
        XCTAssertFalse(ATHLTHWatchTodayReplayPolicy.wasConfirmed(
            sessionID: id, ownerID: owner, receipts: receipts,
            now: now.addingTimeInterval(
                ATHLTHWatchTodayReplayPolicy.retention + 1
            )
        ))
    }

    func testPreparedPrescriptionRejectsCrossSportAndMissingStrength() {
        for kind in WatchWorkoutKind.allCases {
            XCTAssertTrue(ATHLTHWatchPreparedRecipeAdmissionPolicy.permits(
                kind: kind, hasRunningRecipe: false,
                hasStrengthRecipe: kind == .strength, hasRoute: false
            ))
            if kind != .running && kind != .walking {
                XCTAssertFalse(ATHLTHWatchPreparedRecipeAdmissionPolicy.permits(
                    kind: kind, hasRunningRecipe: true,
                    hasStrengthRecipe: kind == .strength, hasRoute: false
                ))
            }
            if kind != .strength {
                XCTAssertFalse(ATHLTHWatchPreparedRecipeAdmissionPolicy.permits(
                    kind: kind, hasRunningRecipe: false,
                    hasStrengthRecipe: true, hasRoute: false
                ))
            }
            if !kind.usesOutdoorLocation {
                XCTAssertFalse(ATHLTHWatchPreparedRecipeAdmissionPolicy.permits(
                    kind: kind, hasRunningRecipe: false,
                    hasStrengthRecipe: kind == .strength, hasRoute: true
                ))
            }
        }
        XCTAssertFalse(ATHLTHWatchPreparedRecipeAdmissionPolicy.permits(
            kind: .strength, hasRunningRecipe: false,
            hasStrengthRecipe: false, hasRoute: false
        ))
    }

    func testTodayIndoorSportSurvivesPreparedTransferAndCodec() throws {
        let today = WatchTodayWorkoutTransfer(
            planID: UUID(), workoutID: UUID(), title: "Indoor cycling",
            summary: "Original indoor workout", kind: .cycling,
            scheduledStart: nil, durationMinutes: 30,
            distanceKilometers: nil, routeID: nil, runningWorkout: nil,
            audioCoach: .disabled, indoor: true, updatedAt: Date()
        )
        let copy = try JSONDecoder().decode(
            WatchTodayWorkoutTransfer.self,
            from: JSONEncoder().encode(today)
        )
        XCTAssertEqual(copy.indoor, true)
        let prepared = ATHLTHWatchTodayLaunchAdapter.prepared(from: copy)
        XCTAssertEqual(prepared?.indoor, true)
        XCTAssertEqual(prepared?.kind, .cycling)
    }

}
