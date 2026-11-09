import XCTest
@testable import ATHLTH

@MainActor
final class ATHLTHRecoveryWellnessLibraryTests: XCTestCase {
    func testCuratedLibraryHasTwentyTwoStretchingGuidesAndThreeBreathingGuides() {
        let all = ATHLTHWellnessGuide.all
        XCTAssertEqual(all.filter { $0.category == .stretching }.count, 22)
        XCTAssertEqual(all.filter { $0.category == .zen }.count, 3)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count,
                       "Catalog identifiers must remain unique for saved workouts")
    }

    func testEveryStretchHasValidInstructionsAndDuration() {
        for guide in ATHLTHWellnessBlockFactory.stretching {
            XCTAssertFalse(guide.titleNO.isEmpty, guide.id)
            XCTAssertFalse(guide.titleEN.isEmpty, guide.id)
            XCTAssertFalse(guide.detailNO.isEmpty, guide.id)
            XCTAssertFalse(guide.detailEN.isEmpty, guide.id)
            XCTAssertGreaterThanOrEqual(guide.seconds, 30, guide.id)
            XCTAssertLessThanOrEqual(guide.seconds, 180, guide.id)
            XCTAssertTrue(["upper", "back", "hips", "legs"].contains(guide.focusKey),
                          "Guide should appear under a muscle-group filter: \(guide.id)")
        }
    }

    func testPlanAndLibraryUseIdenticalTimedExerciseBlocks() {
        for guide in ATHLTHWellnessBlockFactory.stretching {
            let block = ATHLTHWellnessBlockFactory.block(for: guide, phase: .main)
            XCTAssertEqual(block.kind, .note)
            XCTAssertEqual(block.wellnessKind, .stretching)
            XCTAssertEqual(block.durationSeconds, Double(guide.seconds))
            XCTAssertEqual(block.notes, guide.instructions)
            XCTAssertNil(block.repetitions)
            XCTAssertNil(block.targetWeightKilograms)
            XCTAssertEqual(block.phase, .main)
        }
    }

    func testBreathingGuidesRemainRestorativeAndDoNotBecomeStrengthSets() {
        for guide in ATHLTHWellnessGuide.all where guide.category == .zen {
            let block = ATHLTHWellnessBlockFactory.block(for: guide, phase: .main)
            XCTAssertEqual(block.wellnessKind, .meditation)
            XCTAssertEqual(block.phase, .recovery)
            XCTAssertEqual(block.kind, .note)
        }
    }
}
