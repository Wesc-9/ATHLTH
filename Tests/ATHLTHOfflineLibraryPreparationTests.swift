import CoreLocation
import Foundation
import XCTest
import UIKit
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

    func testRouteGeometryChangeStillInvalidatesOfflineSnapshot() {
        var saved = plan()
        let owner = saved.ownerID
        let routeID = UUID()
        saved.weeks[0].days[0].sessions.append(PlannedSession(
            id: UUID(), title: "Route run", kind: .running,
            scheduledStart: nil, durationMinutes: 30,
            targetDistanceKilometers: nil,
            targetPaceSecondsPerKilometer: nil, routeID: routeID,
            exercises: [], notes: nil
        ))
        let route = TrainingRoute(
            id: routeID, ownerID: owner, title: "Route",
            visibility: .privateOnly,
            coordinates: [
                RouteCoordinate(latitude: 63.40, longitude: 10.39,
                                altitude: nil, sequence: 0),
                RouteCoordinate(latitude: 63.41, longitude: 10.40,
                                altitude: nil, sequence: 1)
            ], distanceKilometers: 1.6, elevationGainMeters: nil,
            importedFilename: nil, createdAt: Date()
        )
        let pack = AthleteOfflinePack(
            plan: saved, routes: [route], downloadedAt: .now,
            mapRouteIDs: [routeID], exerciseImageIDs: [], missingAssets: 0
        )
        XCTAssertFalse(ATHLTHOfflineLibraryPreparationPolicy.needsLocalSnapshot(
            plan: saved, routes: [route], existing: pack
        ))
        var changed = route
        changed.coordinates[1].longitude += 0.003
        XCTAssertTrue(ATHLTHOfflineLibraryPreparationPolicy.needsLocalSnapshot(
            plan: saved, routes: [changed], existing: pack
        ))
    }

    func testOfflineRouteThumbnailCacheCannotLeakBetweenAccounts() throws {
        let accountA = UUID(), accountB = UUID(), routeID = UUID()
        var saved = plan()
        saved.ownerID = accountA
        let route = TrainingRoute(
            id: routeID, ownerID: accountA, title: "Offline A",
            visibility: .privateOnly,
            coordinates: [
                RouteCoordinate(latitude: 63.40, longitude: 10.39,
                                altitude: nil, sequence: 0),
                RouteCoordinate(latitude: 63.41, longitude: 10.40,
                                altitude: nil, sequence: 1)
            ], distanceKilometers: 1.0, elevationGainMeters: nil,
            importedFilename: nil, createdAt: .now
        )
        let pack = AthleteOfflinePack(
            plan: saved, routes: [route], downloadedAt: .now,
            mapRouteIDs: [routeID], exerciseImageIDs: [], missingAssets: 0
        )
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let userFolder = support
            .appendingPathComponent("AthleteOfflinePacks", isDirectory: true)
            .appendingPathComponent(accountA.uuidString, isDirectory: true)
        let packFolder = userFolder.appendingPathComponent(
            saved.id.uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packFolder, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: userFolder) }

        try JSONEncoder().encode(pack).write(
            to: packFolder.appendingPathComponent("pack.json"), options: .atomic
        )
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
            .pngData { context in
                context.cgContext.setFillColor(UIColor.red.cgColor)
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
        let imagePath = packFolder.appendingPathComponent(
            routeID.uuidString + ".png"
        )
        try png.write(to: imagePath, options: .atomic)

        let store = AthleteOfflinePackStore()
        store.load(userID: accountA)
        XCTAssertNotNil(AthleteOfflinePackStore.cachedRouteSnapshot(
            routeID: routeID, userID: accountA
        ))
        XCTAssertNil(AthleteOfflinePackStore.cachedRouteSnapshot(
            routeID: routeID, userID: accountB
        ))
        XCTAssertNotNil(AthleteOfflinePackStore.cachedRouteSnapshot(
            routeID: routeID, userID: accountA
        ))

        // Invalidate on reload, even if a bitmap was previously cached.
        try FileManager.default.removeItem(at: imagePath)
        store.load(userID: accountA)
        XCTAssertNil(AthleteOfflinePackStore.cachedRouteSnapshot(
            routeID: routeID, userID: accountA
        ))
    }

    func testUnchangedOfflineSnapshotPerformanceBaseline() {
        let saved = plan()
        let pack = AthleteOfflinePack(
            plan: saved, routes: [], downloadedAt: .now,
            mapRouteIDs: [], exerciseImageIDs: [], missingAssets: 0
        )
        // An XCTest metric, not an assumed device-specific time threshold.
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<100 {
                XCTAssertFalse(ATHLTHOfflineLibraryPreparationPolicy.needsLocalSnapshot(
                    plan: saved, routes: [], existing: pack
                ))
            }
        }
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
