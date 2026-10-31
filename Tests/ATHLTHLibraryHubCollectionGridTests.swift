import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHLibraryHubCollectionGridTests: XCTestCase {
    @MainActor
    func testPersonalLibraryTilesFitTwoColumnsWithoutVerticalLetterStacking() {
        for width in [146.0, 165.0, 190.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let tile = LibraryHubCollectionRow(
                    title: "Mine treningsplaner",
                    detail: "Opprettede og planlagte",
                    symbol: "calendar",
                    tint: .brown,
                    count: 0,
                    grid: true
                )
                .environment(\.dynamicTypeSize, size)
                let host = UIHostingController(rootView: tile)
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(in: CGSize(width: width, height: 800))
                XCTAssertLessThanOrEqual(measured.width, width + 1)
                XCTAssertGreaterThan(measured.height, 0)
            }
        }
    }
}
