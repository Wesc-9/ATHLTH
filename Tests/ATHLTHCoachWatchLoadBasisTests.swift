import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHCoachWatchLoadBasisTests: XCTestCase {
    func testExerciseSnapshotPreservesWeightBasisAndStableLibraryIdentity() throws {
        var snapshot = ExerciseSnapshot(
            name: "Dumbbell Shoulder Press",
            instructions: [],
            primaryMuscles: ["shoulders"],
            secondaryMuscles: [],
            equipment: ["dumbbells"],
            imageURL: nil
        )
        let id = UUID()
        snapshot.libraryExerciseID = id
        snapshot.coachLoadBasis = .kilogramsPerHand

        let decoded = try JSONDecoder().decode(
            ExerciseSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded.libraryExerciseID, id)
        XCTAssertEqual(decoded.coachLoadBasis, .kilogramsPerHand)
        XCTAssertEqual(decoded.name, snapshot.name)
    }

    func testExerciseLibrarySnapshotCarriesSelectedWeightInterpretation() {
        var exercise = Exercise(
            id: UUID(),
            origin: .custom,
            ownerID: UUID(),
            name: "Dumbbell Press",
            instructions: [],
            primaryMuscles: ["shoulders"],
            secondaryMuscles: [],
            equipment: ["dumbbells"],
            imageURL: nil,
            isVisibleOutsideOwnerLibrary: false
        )
        exercise.coachLoadBasis = .kilogramsPerHand
        let snapshot = exercise.snapshot
        XCTAssertEqual(snapshot.libraryExerciseID, exercise.id)
        XCTAssertEqual(snapshot.coachLoadBasis, .kilogramsPerHand)
    }

    func testNewWatchQueueRoundTripsWeightBasisAndLibraryID() throws {
        var queueItem = WatchStrengthExerciseSummary(
            index: 0,
            name: "Dumbbell Shoulder Press",
            primaryMuscles: ["shoulders"],
            setCount: 3
        )
        let id = UUID()
        queueItem.libraryExerciseID = id
        queueItem.coachLoadBasisRaw =
            ATHLTHStrengthLoadBasis.kilogramsPerHand.rawValue

        let decoded = try JSONDecoder().decode(
            WatchStrengthExerciseSummary.self,
            from: JSONEncoder().encode(queueItem)
        )
        XCTAssertEqual(decoded.libraryExerciseID, id)
        XCTAssertEqual(
            decoded.coachLoadBasisRaw.flatMap(ATHLTHStrengthLoadBasis.init(rawValue:)),
            .kilogramsPerHand
        )
    }

    func testOldWatchQueueStaysDecodableWithoutWeightBasis() throws {
        let oldQueue = """
        {
          "index": 0,
          "name": "Bench Press",
          "primaryMuscles": ["chest"],
          "setCount": 3,
          "equipment": ["barbell"]
        }
        """
        let decoded = try JSONDecoder().decode(
            WatchStrengthExerciseSummary.self,
            from: Data(oldQueue.utf8)
        )
        XCTAssertNil(decoded.libraryExerciseID)
        XCTAssertNil(decoded.coachLoadBasisRaw)
        XCTAssertEqual(decoded.equipment, ["barbell"])
    }

    func testUnknownWatchWeightBasisDoesNotGetInvented() throws {
        var item = WatchStrengthExerciseSummary(
            index: 0, name: "Cable Row",
            primaryMuscles: ["back"], setCount: 3
        )
        item.coachLoadBasisRaw = "unsupported_basis"
        let decoded = try JSONDecoder().decode(
            WatchStrengthExerciseSummary.self,
            from: JSONEncoder().encode(item)
        )
        XCTAssertNil(
            decoded.coachLoadBasisRaw.flatMap(ATHLTHStrengthLoadBasis.init(rawValue:))
        )
    }
}
