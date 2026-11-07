import SwiftUI

/// One compact, readable metric surface for both Routes and My Routes.
/// Estimates are based on the calling screen's existing pace calculation.
/// This view does not calculate, save or change the underlying route.
struct ATHLTHRouteMetricRibbon: View {
    let kilometers: Double
    let estimatedWalk: String
    let estimatedRun: String

    var body: some View {
        HStack(spacing: 0) {
            metric(
                title: ATHLTHLocalization.choose(
                    english: "DISTANCE", norwegian: "DISTANSE"
                ),
                value: String(format: "%.1f km", kilometers),
                symbol: "point.topleft.down.to.point.bottomright.curvepath"
            )
            Divider()
                .frame(height: 34)
            metric(
                title: ATHLTHLocalization.choose(
                    english: "EST. WALK", norwegian: "EST. GANGE"
                ),
                value: estimatedWalk, symbol: "figure.walk"
            )
            Divider()
                .frame(height: 34)
            metric(
                title: ATHLTHLocalization.choose(
                    english: "EST. RUN", norwegian: "EST. LØPING"
                ),
                value: estimatedRun, symbol: "figure.run"
            )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 3)
        .background(ATHLTHPlanDesign.selectedSurface.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.1)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}
