import Foundation
import XCTest
@testable import ATHLTH

final class GarminImportNormalizerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func input(
        id: String = "123", type: String = "running", duration: Double = 1800,
        elapsed: Double? = 1920, distance: Double? = 5000,
        averageHR: Double? = 145
    ) -> GarminActivityInput {
        GarminActivityInput(
            activityID: id, activityType: type, deviceModel: "Synthetic test watch",
            startedAt: start, elapsedSeconds: elapsed, durationSeconds: duration,
            distanceMeters: distance, activeEnergyKilocalories: 350,
            averageHeartRate: averageHR, maximumHeartRate: 171
        )
    }

    func testMapsUnitsAndPreservesElapsedTime() throws {
        let result = try GarminImportNormalizer.activity(input())
        XCTAssertEqual(result.workout.id, "garmin:123")
        XCTAssertEqual(result.workout.provider, .garmin)
        XCTAssertEqual(result.workout.kind, .running)
        XCTAssertEqual(result.workout.duration, 1800)
        XCTAssertEqual(result.workout.endedAt, start.addingTimeInterval(1920))
        XCTAssertEqual(result.workout.distanceMeters, 5000)
        XCTAssertEqual(result.workout.averageHeartRate, 145)
        XCTAssertEqual(result.deviceModel, "Synthetic test watch")
        XCTAssertNil(result.workout.route)
    }

    func testMapsSupportedSportsAndRetainsUnknownSports() throws {
        XCTAssertEqual(try GarminImportNormalizer.activity(input(type: "walking")).workout.kind, .walking)
        XCTAssertEqual(try GarminImportNormalizer.activity(input(type: "strength_training")).workout.kind, .strength)
        let cycling = try GarminImportNormalizer.activity(input(type: "cycling"))
        XCTAssertEqual(cycling.workout.kind, .custom)
        XCTAssertEqual(cycling.originalActivityType, "cycling")
    }

    func testMissingAndInvalidMeasurementsAreNotInvented() throws {
        let result = try GarminImportNormalizer.activity(input(distance: -1, averageHR: .nan))
        XCTAssertNil(result.workout.distanceMeters)
        XCTAssertNil(result.workout.averageHeartRate)
        XCTAssertNil(try GarminImportNormalizer.activity(input(averageHR: nil)).workout.averageHeartRate)
        XCTAssertThrowsError(try GarminImportNormalizer.activity(input(id: " ")))
        XCTAssertThrowsError(try GarminImportNormalizer.activity(input(duration: .infinity)))
        XCTAssertThrowsError(try GarminImportNormalizer.activity(input(duration: 2000, elapsed: 1900)))
    }

    func testRepeatDeliveryUsesStableProviderIdentity() throws {
        let items = try GarminImportNormalizer.normalize([
            input(), input(id: "123", distance: 5100), input(id: "456")
        ])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.workout.id, "garmin:123")
        XCTAssertEqual(items.first?.workout.distanceMeters, 5100)
    }

    func testCrossProviderDuplicateIsOnlyACandidate() throws {
        let garmin = try GarminImportNormalizer.activity(input()).workout
        let apple = WearableWorkoutRecord(
            id: "apple:1", provider: .appleWatch, kind: .running,
            startedAt: start.addingTimeInterval(15), endedAt: nil,
            duration: 1800, activeEnergyKilocalories: nil,
            distanceMeters: 5050, averageHeartRate: nil, maximumHeartRate: nil,
            route: nil
        )
        XCTAssertTrue(GarminImportNormalizer.isPossibleDuplicate(garmin, apple))
        XCTAssertFalse(GarminImportNormalizer.isPossibleDuplicate(garmin, garmin))
    }

    func testProductionSourceFailsClosed() async {
        let source = GarminDataSource()
        XCTAssertFalse(source.isAuthorized)
        XCTAssertTrue(source.capabilities.isEmpty)
        do {
            _ = try await source.refreshWorkouts(since: start)
            XCTFail("Unapproved Garmin access must not return data")
        } catch {
            XCTAssertEqual(error as? GarminImportError, .accessNotApproved)
        }
    }
}
