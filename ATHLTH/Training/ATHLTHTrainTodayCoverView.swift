import SwiftUI

/// Dedicated image-led Train cover. It owns only presentation; the session
/// and active workout remain in ATHLTHTrainView, outside this view's identity.
struct ATHLTHTrainTodayCoverView: View {
    let day: Date
    @Binding var selection: ATHLTHTrainSection
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 39
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image("GoalMountain")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        ATHLTHTrainDesign.paper.opacity(0.94),
                        ATHLTHTrainDesign.paper.opacity(0.76),
                        ATHLTHTrainDesign.paper.opacity(0.04)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.white.opacity(0.32), .clear, .black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        ATHLTHTrainNavigation(selection: $selection, compact: true)
                    }
                    Spacer().frame(height: 18)
                    Text(ATHLTHLocalization.choose(
                        english: "TRAINING", norwegian: "TRENING"
                    ))
                    .font(.caption.weight(.semibold))
                    .tracking(3)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .padding(.bottom, 9)

                    Text(ATHLTHLocalization.choose(english: "Today", norwegian: "I dag"))
                        .font(.system(size: headingSize, weight: .regular, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .accessibilityAddTraits(.isHeader)
                        .minimumScaleFactor(0.85)

                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.inkLift)
                        .padding(.top, 3)

                    Capsule()
                        .fill(ATHLTHTrainDesign.gold)
                        .frame(width: 37, height: 2)
                        .padding(.top, 17)
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 360 : 292)
        .accessibilityElement(children: .contain)
    }
}
