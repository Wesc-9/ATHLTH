import XCTest
@testable import ATHLTH

final class WorkoutVisualRecipeTests: XCTestCase {
    func testLegacyWorkoutInsightStillDecodesWithoutVisualRecipe() throws {
        let data = Data(
            #"{"headline":"Steady effort","summary":"Pace stayed consistent."}"#
                .utf8
        )

        let insight =
            try JSONDecoder().decode(
                WorkoutAIInsight.self,
                from: data
            )

        XCTAssertEqual(
            insight.headline,
            "Steady effort"
        )
        XCTAssertNil(insight.visualRecipe)
    }

    func testWorkoutInsightDecodesVisualRecipe() throws {
        let data = Data(
            """
            {
              "headline": "Strong finish",
              "summary": "Your pace increased late in the session.",
              "visualRecipe": {
                "palette": "sage",
                "scene": "mountain",
                "light": "daylight",
                "motif": "route",
                "energy": "steady",
                "variant": 2
              }
            }
            """.utf8
        )

        let insight =
            try JSONDecoder().decode(
                WorkoutAIInsight.self,
                from: data
            )

        XCTAssertEqual(
            insight.visualRecipe?.palette,
            "sage"
        )
        XCTAssertEqual(
            insight.visualRecipe?.scene,
            "mountain"
        )
        XCTAssertEqual(
            insight.visualRecipe?.variant,
            2
        )
    }
}
