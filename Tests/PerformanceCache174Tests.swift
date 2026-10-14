import CoreGraphics
import XCTest
@testable import ATHLTH

final class PerformanceCache174Tests: XCTestCase {
    private func route() -> TrainingRoute {
        TrainingRoute(
            id: UUID(), ownerID: UUID(), title: "Test route", visibility: .privateOnly,
            coordinates: [
                RouteCoordinate(latitude: 69.65, longitude: 18.95, altitude: nil, sequence: 0),
                RouteCoordinate(latitude: 69.66, longitude: 18.96, altitude: nil, sequence: 1),
                RouteCoordinate(latitude: 69.67, longitude: 18.97, altitude: nil, sequence: 2)
            ], distanceKilometers: 3, elevationGainMeters: nil,
            importedFilename: nil, createdAt: Date()
        )
    }

    func testMiddleGeometryEditInvalidatesThumbnailWithSameEndpointsAndCount() {
        let original = route()
        var changed = original
        changed.coordinates[1].longitude += 0.01
        let size = CGSize(width: 220, height: 118)
        XCTAssertNotEqual(
            RouteMapSnapshotIdentity.key(route: original, size: size, scale: 3),
            RouteMapSnapshotIdentity.key(route: changed, size: size, scale: 3)
        )
        XCTAssertEqual(original.coordinates.first, changed.coordinates.first)
        XCTAssertEqual(original.coordinates.last, changed.coordinates.last)
        XCTAssertEqual(original.coordinates.count, changed.coordinates.count)
    }

    func testThumbnailIdentityIncludesOwnerSizeAndScaleButIgnoresTitle() {
        let original = route()
        let size = CGSize(width: 220, height: 118)
        let key = RouteMapSnapshotIdentity.key(route: original, size: size, scale: 3)
        var renamed = original
        renamed.title = "New title"
        XCTAssertEqual(key, RouteMapSnapshotIdentity.key(route: renamed, size: size, scale: 3))
        renamed.ownerID = UUID()
        XCTAssertNotEqual(key, RouteMapSnapshotIdentity.key(route: renamed, size: size, scale: 3))
        XCTAssertNotEqual(key, RouteMapSnapshotIdentity.key(route: original, size: size, scale: 2))
        XCTAssertNotEqual(key, RouteMapSnapshotIdentity.key(
            route: original, size: CGSize(width: 220, height: 180), scale: 3
        ))
    }

    @MainActor
    func testSearchCacheInvalidatesOnCustomEditDeleteAndAccountSwitch() {
        let owner = UUID(), other = UUID()
        defer {
            for id in [owner, other] {
                UserDefaults.standard.removeObject(forKey: AccountLocalStorage.key("exerciseLibrary", userID: id))
            }
        }
        let library = ExerciseLibraryStore()
        library.switchAccount(owner)
        let entry = library.createCustomExercise(
            ownerID: owner, name: "Unique Zeta Press", instructions: [],
            primaryMuscles: ["Chest"], secondaryMuscles: [], equipment: ["Dumbbell"],
            isVisibleOutsideOwnerLibrary: false
        )
        XCTAssertEqual(library.search(query: "zeta").map(\.id), [entry.id])
        // Exercise the warmed result cache, then edit its indexed text and filters.
        XCTAssertEqual(library.search(query: "zeta").map(\.id), [entry.id])
        var edited = entry.exercise
        edited.name = "Unique Omega Pull"
        edited.equipment = ["Cable"]
        library.updateCustomExercise(edited)
        XCTAssertFalse(library.search(query: "zeta").contains { $0.id == entry.id })
        XCTAssertEqual(library.search(query: "omega", equipment: "Cable").map(\.id), [entry.id])
        XCTAssertTrue(library.search(query: "omega", equipment: "Dumbbell").isEmpty)
        library.switchAccount(other)
        XCTAssertFalse(library.search(query: "omega").contains { $0.id == entry.id })
        library.switchAccount(owner)
        XCTAssertEqual(library.search(query: "omega").map(\.id), [entry.id])
        library.deleteCustomExercise(entry.id)
        XCTAssertFalse(library.search(query: "omega").contains { $0.id == entry.id })
    }

    @MainActor
    func testSearchPreservesNorwegianNamesTokensAndFilters() {
        let library = ExerciseLibraryStore()
        let expected = library.search(query: "knebøy").map(\.id)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(library.search(query: "  KNEBØY  ").map(\.id), expected)
        let multiToken = library.search(query: "barbell squat")
        XCTAssertFalse(multiToken.isEmpty)
        XCTAssertEqual(library.search(query: "barbell squat").map(\.id), multiToken.map(\.id))
        XCTAssertTrue(library.search(query: "barbell squat", equipment: "not-real-equipment").isEmpty)
        XCTAssertEqual(library.search(query: "barbell squat").map(\.id), multiToken.map(\.id))
    }
}
