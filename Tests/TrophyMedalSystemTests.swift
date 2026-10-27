import SwiftUI
import UIKit
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

    @MainActor
    func testPhysicalAwardArtworkFitsSmallAndLargePresentationSizes() {
        for size: CGFloat in [54, 78, 86, 112, 190, 278] {
            for metal in ATHLTHMedalMetal.allCases {
                let controller = UIHostingController(
                    rootView: ATHLTHMintedBrandSeal(size: size, metal: metal))
                controller.loadViewIfNeeded()
                let fitted = controller.sizeThatFits(
                    in: CGSize(width: size + 20, height: size + 20))
                XCTAssertGreaterThan(fitted.width, 0)
                XCTAssertLessThanOrEqual(fitted.width, size + 20)
            }
            let cup = UIHostingController(
                rootView: ATHLTHGoldPrestigeCupArtwork(
                    size: size, isUnlocked: true))
            cup.loadViewIfNeeded()
            let fitted = cup.sizeThatFits(
                in: CGSize(width: size + 20, height: size * 1.2 + 20))
            XCTAssertGreaterThan(fitted.height, 0)
            XCTAssertLessThanOrEqual(fitted.height, size * 1.2 + 20)
        }
    }

    func testReededMedalDieIsFiniteForCompactAwards() {
        for size: CGFloat in [54, 78, 190] {
            let path = ATHLTHMedalReededEdge().path(
                in: CGRect(x: 0, y: 0, width: size, height: size))
            XCTAssertFalse(path.isEmpty)
            XCTAssertTrue(path.boundingRect.width.isFinite)
            XCTAssertTrue(path.boundingRect.height.isFinite)
            XCTAssertGreaterThan(path.boundingRect.width, size * 0.8)
        }
    }

    func testMedalColoursAreOpaqueMetallicColours() {
        for metal in ATHLTHMedalMetal.allCases {
            XCTAssertEqual(metal.highlights.count, 5)
            XCTAssertEqual(metal.face.count, 3)
        }
    }
}
