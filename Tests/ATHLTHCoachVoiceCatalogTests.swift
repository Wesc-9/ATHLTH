import XCTest
@testable import ATHLTH

final class ATHLTHCoachVoiceCatalogTests: XCTestCase {
    private func voice(
        _ name: String, _ locale: String = "en-US",
        _ quality: Int = 2, id: String? = nil
    ) -> ATHLTHCoachVoiceDescriptor {
        ATHLTHCoachVoiceDescriptor(
            id: id ?? "\(name)-\(locale)-\(quality)",
            name: name,
            language: locale,
            qualityRank: quality
        )
    }

    func testEnglishShowsOnlyHighQualityNaturalVoices() {
        let installed = [
            voice("Aaron", "en-US", 1),
            voice("Albert", "en-US", 1),
            voice("Bad News", "en-US", 3),
            voice("Bahh", "en-US", 1),
            voice("Bells", "en-US", 1),
            voice("Bobler", "en-US", 1),
            voice("Samantha", "en-US", 3),
            voice("Daniel", "en-GB", 2),
            voice("Ava", "en-US", 2),
            voice("Nora", "nb-NO", 3)
        ]

        let displayed = ATHLTHCoachVoiceCatalog.featured(
            from: installed, languageCode: "en"
        )
        XCTAssertEqual(displayed.map(\.name), ["Samantha", "Ava", "Daniel"])
        XCTAssertEqual(displayed.count, 3)
    }

    func testNorwegianIncludesNorwegianDialectsNotEnglish() {
        let displayed = ATHLTHCoachVoiceCatalog.featured(
            from: [
                voice("Nora", "nb-NO", 3),
                voice("Henrik", "nb-NO", 2),
                voice("Nynorsk", "nn-NO", 2),
                voice("Anna", "en-US", 3)
            ],
            languageCode: "nb"
        )
        XCTAssertEqual(displayed.map(\.name), ["Nora", "Henrik", "Nynorsk"])
    }

    func testEnglishKeepsSelectedEnhancedVoiceInShortList() {
        let installed = [
            voice("One", "en-US", 3),
            voice("Two", "en-US", 3),
            voice("Three", "en-US", 3),
            voice("Four", "en-US", 2),
            voice("Five", "en-US", 2)
        ]
        let selected = installed[4]
        let displayed = ATHLTHCoachVoiceCatalog.featured(
            from: installed, languageCode: "en",
            selectedIdentifier: selected.id
        )

        XCTAssertEqual(displayed.count, 3)
        XCTAssertTrue(displayed.contains { $0.id == selected.id })
    }

    func testBasicAndNoveltyAreNotReintroducedAsFallback() {
        let installed = [
            voice("Aaron", "en-US", 1),
            voice("Bad News", "en-US", 3),
            voice("Bjeller", "nb-NO", 3)
        ]
        XCTAssertTrue(ATHLTHCoachVoiceCatalog.featured(
            from: installed, languageCode: "en"
        ).isEmpty)
        XCTAssertTrue(ATHLTHCoachVoiceCatalog.featured(
            from: installed, languageCode: "nb"
        ).isEmpty)
        XCTAssertTrue(ATHLTHCoachVoiceCatalog.isNovelty(name: "Bubbles"))
    }

    func testHigherQualityVersionOfSameVoiceWins() {
        let installed = [
            voice("Samantha", "en-US", 2, id: "old"),
            voice("Samantha", "en-US", 3, id: "new")
        ]
        XCTAssertEqual(
            ATHLTHCoachVoiceCatalog.featured(
                from: installed, languageCode: "en"
            ).map(\.id),
            ["new"]
        )
    }
}
