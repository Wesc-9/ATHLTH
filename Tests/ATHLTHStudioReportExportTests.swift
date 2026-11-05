import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHStudioReportExportTests: XCTestCase {
    func testOptInReportHasValidPDFSignatureWithoutWorkoutData() {
        let data = ATHLTHStudioReportRenderer.make(
            workouts: [],
            days: 28,
            includeDetails: false,
            includeEnergy: false,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(
            String(decoding: data.prefix(5), as: UTF8.self),
            "%PDF-"
        )
    }

    func testDetailAndEnergyFlagsAreExplicit() {
        let data = ATHLTHStudioReportRenderer.make(
            workouts: [],
            days: 90,
            includeDetails: true,
            includeEnergy: true,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(
            String(decoding: data.prefix(5), as: UTF8.self),
            "%PDF-"
        )
    }
}
