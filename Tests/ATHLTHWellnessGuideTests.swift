import XCTest
@testable import ATHLTH

final class ATHLTHWellnessGuideTests: XCTestCase {
    func testOfflineCatalogHasBreathingAndStretchingInstructions() {
        let guides = ATHLTHWellnessGuide.all
        XCTAssertGreaterThanOrEqual(guides.count, 25)
        XCTAssertEqual(Set(guides.map(\.id)).count, guides.count)
        XCTAssertEqual(guides.filter { $0.category == .zen }.count, 3)
        XCTAssertGreaterThanOrEqual(guides.filter { $0.category == .stretching }.count, 22)
        XCTAssertTrue(guides.allSatisfy {
            $0.seconds > 0 && !$0.title.isEmpty && !$0.instructions.isEmpty
        })
    }

    func testBreathingExercisesDoNotForceBreathHolds() {
        let breathing = ATHLTHWellnessGuide.all.filter { $0.category == .zen }
        XCTAssertTrue(breathing.allSatisfy { $0.inhale >= 0 && $0.exhale >= 0 })
        XCTAssertTrue(breathing.allSatisfy {
            $0.inhale == 0 || $0.exhale > 0
        })
    }
}
