import XCTest
@testable import ATHLTH

final class StrengthMuscleProfileTests: XCTestCase {
    func testBenchPressMusclesMapToExpectedBodyRegions() {
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Pectoralis Major"
            ),
            [.chest]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Anterior Deltoid"
            ),
            [.frontDelts]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Triceps Brachii"
            ),
            [.triceps]
        )
    }

    func testLowerBodyRepDBMusclesMapToExpectedRegions() {
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Gluteus Maximus"
            ),
            [.glutes]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Gluteus Medius"
            ),
            [.outerHip]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Quadriceps"
            ),
            [.quads]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Hamstrings"
            ),
            [.hamstrings]
        )
        XCTAssertEqual(
            StrengthMuscleResolver.regions(
                for: "Gastrocnemius"
            ),
            [.calves]
        )
    }

    func testRepDBBodyPartFallbackAlwaysProducesVisualRegions() {
        let supported = [
            "Chest",
            "Shoulders",
            "Back",
            "Core",
            "Lower Arms",
            "Lower Legs",
            "Upper Arms",
            "Upper Legs",
            "Full Body"
        ]

        for bodyPart in supported {
            XCTAssertFalse(
                StrengthMuscleResolver
                    .fallbackRegions(
                        forBodyPart:
                            bodyPart
                    )
                    .isEmpty,
                bodyPart
            )
        }
    }
}
