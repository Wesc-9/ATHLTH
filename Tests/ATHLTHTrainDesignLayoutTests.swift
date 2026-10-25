import SwiftUI
import XCTest
@testable import ATHLTH

final class ATHLTHTrainDesignLayoutTests: XCTestCase {
    @MainActor
    func testSharedChromeAndActivityTilesFitCompactAndWideLayoutsWithLargeText() {
        for width in [320.0, 390.0, 768.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for section in [ATHLTHTrainSection.today, .plan, .progress] {
                    let content = VStack(alignment: .leading, spacing: 24) {
                        ATHLTHTrainMasthead(
                            title: "En gjennomtenkt treningsuke",
                            subtitle: "Alle planlagte økter og faktisk gjennomført trening",
                            onLibrary: {})
                        ATHLTHTrainNavigation(selection: .constant(section))
                        ATHLTHTrainActivityTile(title: "Styrketrening", symbol: "dumbbell")
                        ATHLTHTrainMetricTile(title: "Registrerte økter", value: "124", symbol: "calendar")
                    }
                    .padding(17)
                    .environment(\.dynamicTypeSize, size)
                    let host = UIHostingController(rootView: content)
                    host.loadViewIfNeeded()
                    let measured = host.sizeThatFits(in: CGSize(width: width, height: 5_000))
                    XCTAssertLessThanOrEqual(measured.width, width + 1)
                    XCTAssertGreaterThan(measured.height, 0)
                }
            }
        }
    }
}
