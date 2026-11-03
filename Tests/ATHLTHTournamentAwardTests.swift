import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHTournamentAwardTests: XCTestCase {
    func testServerIssuedChampionIsRenderedAsTrophy() {
        let tournament = UUID()
        let trophyID = "tournament.\(tournament.uuidString).champion"
        XCTAssertTrue(PrestigeTrophyCatalog.isPrestigeTrophy(trophyID))

        let record = TrophyUnlockRecord(
            stageKey: "arena.tournament.\(tournament.uuidString).champion",
            trophyID: trophyID,
            stageTitle: "Vintercup",
            title: "Mester · Vintercup",
            rarity: .epic,
            category: .challenges,
            verificationSource: .challenge,
            unlockedAt: Date()
        )
        XCTAssertEqual(record.awardClass, .trophy)
    }

    func testRunnerUpAndThirdPlaceRemainMedals() {
        let tournament = UUID().uuidString
        XCTAssertFalse(PrestigeTrophyCatalog.isPrestigeTrophy(
            "tournament.\(tournament).runnerup"
        ))
        XCTAssertFalse(PrestigeTrophyCatalog.isPrestigeTrophy(
            "tournament.\(tournament).third"
        ))
    }
}
