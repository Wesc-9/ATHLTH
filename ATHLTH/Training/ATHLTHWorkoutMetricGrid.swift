import SwiftUI

/// Common compact stat design used by every completed workout detail. Content
/// comes from each sport's verified measurements; only presentation is shared.
struct ATHLTHWorkoutDisplayMetric: Hashable {
    let icon: String
    let label: String
    let value: String
}

struct ATHLTHWorkoutMetricGrid: View {
    let metrics: [ATHLTHWorkoutDisplayMetric]
    var columnCount: Int = 2

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: max(1, min(columnCount, 3))
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: metric.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(height: 19)

                    Text(metric.value)
                        .font(.system(
                            size: columnCount >= 3 ? 17 : 19,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(metric.label)
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, minHeight: 71, alignment: .leading)
                .padding(11)
                .background(
                    ATHLTHPlanDesign.warmSurface.opacity(0.62),
                    in: RoundedRectangle(
                        cornerRadius: 15, style: .continuous
                    )
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}
