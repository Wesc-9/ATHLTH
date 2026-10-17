import SwiftUI
import XCTest
@testable import ATHLTH

final class ProfileHeroIdentityLayoutTests: XCTestCase {
    @MainActor
    func testIdentityKeepsSameHeightWithAndWithoutBioAndFocus() {
        let variants: [(String?, String?)] = [
            (nil, nil),
            ("Løping", nil),
            ("Styrke og løping", "Trener mot halvmaraton."),
            ("Løping / styrke / Hyrox",
             "Lang biografi som fyller to linjer uten at navnet skal " +
             "flytte seg eller skyve statistikken ned i headeren.")
        ]

        for width in [190.0, 240.0, 320.0] {
            for (focus, bio) in variants {
                let view = ATHLTHProfileHeroIdentityView(
                    name: "Malin Nordhus Landsverk",
                    username: "@malin",
                    trainingFocus: focus,
                    bio: bio
                )
                let host = UIHostingController(rootView: view)
                host.loadViewIfNeeded()
                let measured = host.sizeThatFits(
                    in: CGSize(width: width, height: 200)
                )

                XCTAssertEqual(
                    measured.height,
                    ATHLTHProfileHeroIdentityView.reservedHeight,
                    accuracy: 1,
                    "Profile identity must have a stable vertical slot"
                )
                XCTAssertLessThanOrEqual(
                    measured.width, width + 1,
                    "Long names and bios must fit the allotted width"
                )
            }
        }
    }

    @MainActor
    func testIdentityRowMovesDownWithoutShiftingStatCards() {
        // The row is offset during rendering in both profile containers.
        // Keep a gap for a two-line biography and ensure a subtle shift.
        XCTAssertGreaterThan(ATHLTHProfileHeroIdentityView.heroRowDownshift, 0)
        XCTAssertLessThan(ATHLTHProfileHeroIdentityView.heroRowDownshift, 12)
    }

    @MainActor
    func testIdentityReservesLessSpaceAboveFixedStatRow() {
        // The compact 108pt slot lowers the entire bottom-aligned identity
        // by 12pt compared with the old 120pt profile header.
        XCTAssertEqual(ATHLTHProfileHeroIdentityView.reservedHeight, 108)
    }
}
