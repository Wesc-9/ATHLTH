import XCTest
@testable import ATHLTH

final class ProfileGearCatalogVisualTests: XCTestCase {
    func testHeadphoneShapeDependsOnModel() {
        XCTAssertEqual(
            ProfileGearCatalogVisualKind.resolve(
                category: .headphones, brand: "Apple", model: "AirPods Max"
            ), .overEar
        )
        XCTAssertEqual(
            ProfileGearCatalogVisualKind.resolve(
                category: .headphones, brand: "Samsung", model: "Galaxy Buds3 Pro"
            ), .inEar
        )
        XCTAssertEqual(
            ProfileGearCatalogVisualKind.resolve(
                category: .headphones, brand: "Shokz", model: "OpenRun Pro 2"
            ), .openEar
        )
    }

    func testCoreCategoriesAlwaysGetLightweightArtwork() {
        XCTAssertEqual(
            ProfileGearCatalogVisualKind.resolve(
                category: .watch, brand: "Garmin", model: "Forerunner"
            ), .watch
        )
        XCTAssertEqual(
            ProfileGearCatalogVisualKind.resolve(
                category: .shoes, brand: "Nike", model: "Pegasus"
            ), .runningShoe
        )
    }
}
