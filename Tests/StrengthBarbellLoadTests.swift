import Foundation
import XCTest
@testable import ATHLTH

final class StrengthBarbellLoadTests: XCTestCase {
    func testKneboyPlatesAddedToBarExactlyOnce() {
        XCTAssertEqual(
            StrengthBarbellLoad.total(platesKilograms: 40, barKilograms: 20), 60
        )
        XCTAssertEqual(
            StrengthBarbellLoad.plates(totalKilograms: 60, barKilograms: 20), 40
        )
    }

    func testEmptyBarAndZeroPlates() {
        XCTAssertEqual(
            StrengthBarbellLoad.total(platesKilograms: 0, barKilograms: 20), 20
        )
        XCTAssertEqual(
            StrengthBarbellLoad.total(platesKilograms: 50, barKilograms: 0), 50
        )
        XCTAssertEqual(
            StrengthBarbellLoad.plates(totalKilograms: 15, barKilograms: 20), 0
        )
    }

    func testSwitchingBarPreservesEnteredPlates() {
        XCTAssertEqual(
            StrengthBarbellLoad.totalPreservingPlates(
                totalKilograms: 60, previousBarKilograms: 20,
                newBarKilograms: 15
            ), 55
        )
        XCTAssertEqual(
            StrengthBarbellLoad.totalPreservingPlates(
                totalKilograms: 20, previousBarKilograms: 20,
                newBarKilograms: 25
            ), 25
        )
    }

    func testFractionalPlatesAndBar() {
        XCTAssertEqual(
            StrengthBarbellLoad.total(platesKilograms: 22.5, barKilograms: 17.5),
            40
        )
        XCTAssertEqual(
            StrengthBarbellLoad.plates(totalKilograms: 40, barKilograms: 17.5),
            22.5
        )
    }

    func testBodyweightAndDumbbellsDoNotGetABar() {
        XCTAssertTrue(StrengthBarbellExercisePolicy.usesBarEquipment(
            name: "Knebøy", equipment: ["Barbell"]
        ))
        XCTAssertFalse(StrengthBarbellExercisePolicy.usesBarEquipment(
            name: "Knebøy med manualer", equipment: ["Dumbbell"]
        ))
        XCTAssertFalse(StrengthBarbellExercisePolicy.usesBarEquipment(
            name: "Air squat", equipment: ["bodyweight"]
        ))
        XCTAssertFalse(StrengthBarbellExercisePolicy.usesBarEquipment(
            name: "Goblet squat", equipment: ["Kettlebell"]
        ))
    }
}
