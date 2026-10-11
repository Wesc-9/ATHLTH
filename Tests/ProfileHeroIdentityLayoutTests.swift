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
}
