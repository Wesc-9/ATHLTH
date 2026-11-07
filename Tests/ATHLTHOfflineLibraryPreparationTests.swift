import CoreLocation
import Foundation
import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHOfflineLibraryPreparationTests: XCTestCase {
    private func plan(_ title: String = "Offline strength") -> TrainingPlan {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return TrainingPlan(
            id: UUID(), ownerID: UUID(), title: title, summary: "Plan",
            visibility: .privateOnly, version: 1,
            weeks: [
                TrainingPlanWeek(
                    id: UUID(), weekNumber: 1, title: "Week 1",
                    days: [
                        TrainingPlanDay(
                            id: UUID(), dayIndex: 1,
                            title: "Monday", sessions: []
                        )
                    ]
                )
            ],
            tags: [], createdAt: now, updatedAt: now, startDate: now
        )
    }

    func testNewPlanNeedsLocalCopyAndIdenticalPlanDoesNot() {
        let plan = plan()
        XCTAssertTrue(
            ATHLTHOfflineLibraryPreparationPolicy.needsLocalSnapshot(
                plan: plan, routes: [], existing: nil
            )
        )
        let pack = AthleteOfflinePack(
            plan: plan, routes: [], downloadedAt: Date(),
            mapRouteIDs: [], exerciseImageIDs: [], missingAssets: 0
        )
        XCTAssertFalse(
            ATHLTHOfflineLibraryPreparationPolicy.needsLocalSnapshot(
                plan: plan, routes: [], existing: pack
            )
        )
        XCTAssertFalse(
            ATHLTHOfflineLibraryPreparationPolicy.needsMedia(
                plan: plan, routes: [], existing: pack
            )
        )
    }

    func testAPlanEditInvalidatesSnapshotWithoutDeletingPreviousCopy() {
        let original = plan()
        let pack = AthleteOfflinePack(
            plan: original, routes: [], downloadedAt: Date(),
            mapRouteIDs: [], exerciseImageIDs: [], missingAssets: 0
        )
        var edited = original
        edited.title = "Changed training"
        XCTAssertTrue(
            ATHLTHOfflineLibraryPreparationPolicy.needsLocalSnapshot(
                plan: edited, routes: [], existing: pack
            )
        )
        XCTAssertEqual(pack.plan.title, original.title)
    }

    func testMediaRetryIsBoundedAndReattemptsAfterReconnect() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(
            ATHLTHOfflineLibraryPreparationPolicy.canRetryMedia(
                lastAttempt: nil, now: now
            )
        )
        XCTAssertFalse(
            ATHLTHOfflineLibraryPreparationPolicy.canRetryMedia(
                lastAttempt: now.addingTimeInterval(-60), now: now
            )
        )
        XCTAssertTrue(
            ATHLTHOfflineLibraryPreparationPolicy.canRetryMedia(
                lastAttempt: now.addingTimeInterval(-15 * 60), now: now
            )
        )
    }

    func testOfflineRouteTraceIsAlwaysLocalAndBoundsSafe() {
        let coords: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: 66.31, longitude: 14.12),
            CLLocationCoordinate2D(latitude: 66.32, longitude: 14.18),
            CLLocationCoordinate2D(latitude: 66.34, longitude: 14.22)
        ]
        let points = ATHLTHOfflineRouteTraceGeometry.normalizedPoints(coords)
        XCTAssertEqual(points.count, 3)
        XCTAssertTrue(points.allSatisfy {
            (0...1).contains($0.x) && (0...1).contains($0.y)
        })
        XCTAssertTrue(ATHLTHOfflineRouteTraceGeometry.normalizedPoints([]).isEmpty)
    }
}
