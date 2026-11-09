import Foundation
import XCTest
@testable import ATHLTH

final class LibraryFavoriteExerciseArtworkTests: XCTestCase {
    func testExerciseWithPhotoUsesTheExistingLibraryArtwork() {
        XCTAssertTrue(
            LibraryFavoriteExerciseArtworkPolicy.hasArtwork(
                imageURL: URL(fileURLWithPath: "/tmp/repdb-cached-image.webp"),
                isNativeATHLTH: false,
                sourceIdentifier: "dragon-flag"
            )
        )
    }

    func testExercisesWithoutImageKeepFavoriteIcon() {
        XCTAssertFalse(
            LibraryFavoriteExerciseArtworkPolicy.hasArtwork(
                imageURL: nil,
                isNativeATHLTH: false,
                sourceIdentifier: "custom-exercise"
            )
        )
    }

    func testNativeCoreArtworkCanBeDisplayedWithoutAURL() {
        XCTAssertTrue(
            LibraryFavoriteExerciseArtworkPolicy.hasArtwork(
                imageURL: nil,
                isNativeATHLTH: true,
                sourceIdentifier: "athlth-core-windshield-wiper"
            )
        )
        XCTAssertFalse(
            LibraryFavoriteExerciseArtworkPolicy.hasArtwork(
                imageURL: nil,
                isNativeATHLTH: false,
                sourceIdentifier: "athlth-core-windshield-wiper"
            )
        )
    }
}
