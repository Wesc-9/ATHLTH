import SwiftUI

/// The approved, sunlit ATHLTH Today cover: warm architecture, quiet serif
/// typography and a compact section selector. Pure presentation; never owns
/// workout state, timers or Apple Watch recording.
struct ATHLTHTrainTodayCoverView: View {
    let day: Date
    @Binding var selection: ATHLTHTrainSection

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 49

    private let ink = ATHLTHTrainDesign.ink

    var body: some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top,
                              ATHLTHCoverSafeArea.statusBarTop)
            ZStack(alignment: .topLeading) {
                Image("GoalRecovery")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                // Readable type, but with the architecture and athlete left
                // clearly visible. No fake statistics are part of this image.
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.99, green: 0.975, blue: 0.95).opacity(0.95), location: 0),
                        .init(color: Color(red: 0.99, green: 0.975, blue: 0.95).opacity(0.72), location: 0.36),
                        .init(color: .clear, location: 0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [.clear, Color(red: 0.94, green: 0.89, blue: 0.82).opacity(0.18)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    ATHLTHTrainHeaderRow(selection: $selection)

                    Text(ATHLTHLocalization.choose(english: "Today", norwegian: "I dag"))
                        .font(.system(size: min(headingSize, 71),
                                      weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .padding(.top, 22)
                        .accessibilityAddTraits(.isHeader)

                    Text(ATHLTHLocalization.choose(
                        english: "Stronger habits\nin a more beautiful everyday.",
                        norwegian: "Sterkere vaner\ni en vakrere hverdag."
                    ))
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(ink.opacity(0.73))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24 + safeTop)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // The first pixel is artwork, not a rounded white corner.
            // Only the lower corners are rounded beneath the overlapping card.
            .clipShape(UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 0, bottomLeading: 25,
                                   bottomTrailing: 25, topTrailing: 0),
                style: .continuous
            ))
        }
        .frame(height: (dynamicTypeSize.isAccessibilitySize ? 465 : 378)
                      + ATHLTHCoverSafeArea.statusBarTop)
        .accessibilityElement(children: .contain)
        .accessibilityValue(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
    }

}
