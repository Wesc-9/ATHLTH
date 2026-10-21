import SwiftUI
import XCTest
@testable import ATHLTH

final class TrophyMedalSystemTests: XCTestCase {
    func testEveryTrainingCategoryHasBronzeSilverAndGold() {
        let categories: [TrophyCategory] = [
            .walking, .endurance, .strength, .consistency,
            .goals, .recovery, .challenges
        ]
        for category in categories {
            let tiers = Set(TrophyCatalog.allSeries
                .filter { $0.category == category }
                .flatMap { $0.stages }
                .map { ATHLTHMedalMetal(rarity: $0.rarity) })
            XCTAssertEqual(tiers, Set(ATHLTHMedalMetal.allCases),
                           "\(category.rawValue) must include all medal tiers")
        }
    }

    func testAllCategoriesHaveDistinctEmblems() {
        let emblems = TrophyCategory.allCases.map(\.medalSystemImage)
        XCTAssertEqual(emblems.count, TrophyCategory.allCases.count)
        XCTAssertEqual(Set(emblems).count, emblems.count)
    }

    func testRarityMapsToExactlyThreeMaterialFinishes() {
        XCTAssertEqual(ATHLTHMedalMetal(rarity: .core), .bronze)
        XCTAssertEqual(ATHLTHMedalMetal(rarity: .rare), .silver)
        XCTAssertEqual(ATHLTHMedalMetal(rarity: .epic), .gold)
        XCTAssertEqual(ATHLTHMedalMetal(rarity: .signature), .gold)
    }

    func testPrestigeCupsRemainSeparateFromCategoryMedals() {
        XCTAssertTrue(PrestigeTrophyCatalog.isPrestigeTrophy(
            PrestigeTrophyCatalog.marathonID))
        XCTAssertTrue(PrestigeTrophyCatalog.isPrestigeTrophy(
            PrestigeTrophyCatalog.strength500SessionsID))
        XCTAssertFalse(PrestigeTrophyCatalog.isPrestigeTrophy(
            TrophyCatalog.runningDistance.id))
        XCTAssertFalse(PrestigeTrophyCatalog.isPrestigeTrophy(
            TrophyCatalog.strengthSessions.id))
    }

    func testMedalColoursAreOpaqueMetallicColours() {
        for metal in ATHLTHMedalMetal.allCases {
            XCTAssertEqual(metal.highlights.count, 5)
            XCTAssertEqual(metal.face.count, 3)
        }
    }
}
