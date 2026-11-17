import Foundation
import XCTest
@testable import ATHLTH

final class StrengthBarbellWatchTransferTests: XCTestCase {
    private let oldSnapshot = """
    {
      "workoutID": "11111111-2222-3333-4444-555555555555",
      "title": "Knebøy",
      "exerciseIndex": 0,
      "exerciseCount": 1,
      "exerciseName": "Knebøy",
      "primaryMuscles": ["Quadriceps"],
      "setIndex": 0,
      "setCount": 3,
      "completedSets": 0,
      "totalSets": 3,
      "draftReps": 8,
      "draftWeightKilograms": 60.0,
      "draftRestSeconds": 90,
      "isResting": false,
      "currentExerciseComplete": false,
      "hasNextExercise": false,
      "allExercisesComplete": false,
      "updatedAt": 0
    }
    """

    func testOldWatchPayloadKeepsTotalWeightEntry() throws {
        let snapshot = try JSONDecoder().decode(
            WatchStrengthSessionSnapshot.self,
            from: Data(oldSnapshot.utf8)
        )
        XCTAssertNil(snapshot.barWeightKilograms)
        XCTAssertEqual(snapshot.draftWeightKilograms, 60)
    }

    func testWatchSnapshotExposesOnlyActiveExercisesLoadBasis() throws {
        var dictionary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(oldSnapshot.utf8))
                as? [String: Any]
        )
        dictionary["exerciseQueue"] = [
            [
                "index": 0,
                "name": "Knebøy",
                "primaryMuscles": ["quadriceps"],
                "setCount": 3,
                "coachLoadBasisRaw": "totalKilograms"
            ],
            [
                "index": 1,
                "name": "Skulderpress",
                "primaryMuscles": ["shoulders"],
                "setCount": 3,
                "coachLoadBasisRaw": "kilogramsPerHand"
            ]
        ]
        dictionary["exerciseIndex"] = 1
        let snapshot = try JSONDecoder().decode(
            WatchStrengthSessionSnapshot.self,
            from: JSONSerialization.data(withJSONObject: dictionary)
        )
        XCTAssertEqual(snapshot.currentCoachLoadBasisRaw, "kilogramsPerHand")
        XCTAssertNotNil(
            ATHLTHWatchStrengthLoadBasisLabel.localized(
                raw: snapshot.currentCoachLoadBasisRaw
            )
        )
    }

    func testLegacyWatchSnapshotHasNoGuessedLoadBasis() throws {
        let snapshot = try JSONDecoder().decode(
            WatchStrengthSessionSnapshot.self,
            from: Data(oldSnapshot.utf8)
        )
        XCTAssertNil(snapshot.currentCoachLoadBasisRaw)
        XCTAssertNil(
            ATHLTHWatchStrengthLoadBasisLabel.localized(
                raw: snapshot.currentCoachLoadBasisRaw
            )
        )
        XCTAssertNil(
            ATHLTHWatchStrengthLoadBasisLabel.localized(raw: "unsupported_basis")
        )
    }

    func testNewWatchPayloadCarriesBarButStillStoresTotal() throws {
        var dictionary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(oldSnapshot.utf8))
                as? [String: Any]
        )
        dictionary["barWeightKilograms"] = 20.0
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let snapshot = try JSONDecoder().decode(
            WatchStrengthSessionSnapshot.self, from: data
        )

        XCTAssertEqual(snapshot.barWeightKilograms, 20)
        XCTAssertEqual(snapshot.draftWeightKilograms, 60)
        XCTAssertEqual(
            StrengthBarbellLoad.plates(
                totalKilograms: snapshot.draftWeightKilograms,
                barKilograms: try XCTUnwrap(snapshot.barWeightKilograms)
            ),
            40
        )
    }
}
