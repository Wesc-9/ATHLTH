import Foundation
import XCTest
@testable import ATHLTH

final class LibraryFavoriteExerciseArtworkTests: XCTestCase {
    @MainActor
    func testLegacyAndCanonicalExerciseFavoritesCollapse() throws {
        let library = ExerciseLibraryStore().allExercises
        let old = try XCTUnwrap(library.first { $0.sourceIdentifier == "athlth-native-cable-curl" })
        let new = try XCTUnwrap(library.first { $0.source == .repDB && $0.sourceIdentifier == "cable-curl" })
        let account = UUID()
        let legacy = LibraryFavoriteRecord(userID: account, itemType: .exercise, itemID: old.id.uuidString, title: "Old", subtitle: nil, icon: nil, createdAt: Date())
        let canonical = LibraryFavoriteRecord(userID: account, itemType: .exercise, itemID: new.id.uuidString, title: "New", subtitle: nil, icon: nil, createdAt: Date())
        let projected = LibraryFavoritesStore.canonicalFavorites([legacy, canonical])
        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected.first?.itemID, new.id.uuidString)
        XCTAssertEqual(projected.first?.title, "New")
        XCTAssertEqual(LibraryFavoritesStore.canonicalFavorites([legacy]).first?.itemID, new.id.uuidString)
    }

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
