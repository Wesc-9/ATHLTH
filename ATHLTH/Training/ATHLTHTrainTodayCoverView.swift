import SwiftUI

/// The approved, sunlit ATHLTH Today cover: warm architecture, quiet serif
/// typography and a compact section selector. Pure presentation; never owns
/// workout state, timers or Apple Watch recording.
struct ATHLTHTrainTodayCoverView: View {
    let day: Date
    @Binding var selection: ATHLTHTrainSection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 49

    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    var body: some View {
        GeometryReader { geometry in
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
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            eyebrow
                            Spacer(minLength: 2)
                            topNavigation
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            eyebrow
                            topNavigation
                        }
                    }

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
                .padding(.top, 24)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 465 : 378)
        .accessibilityElement(children: .contain)
        .accessibilityValue(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
    }

    private var eyebrow: some View {
        Text(ATHLTHLocalization.choose(english: "TRAINING", norwegian: "TRENING"))
            .font(.caption2.weight(.semibold))
            .tracking(2.4)
            .foregroundStyle(ink.opacity(0.7))
            .lineLimit(1)
    }

    private var topNavigation: some View {
        HStack(spacing: 1) {
            navButton(.today, label: ATHLTHLocalization.choose(
                english: "Today", norwegian: "I dag"
            ))
            navButton(.plan, label: "Plan")
            navButton(.progress, label: ATHLTHLocalization.choose(
                english: "Progress", norwegian: "Fremdrift"
            ))
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.7), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Train sections", norwegian: "Treningsfaner"
        ))
    }

    private func navButton(_ section: ATHLTHTrainSection, label: String) -> some View {
        let selected = selection == section
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                selection = section
            }
        } label: {
            Text(label)
                .font(.system(.caption, design: .default,
                              weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(selected ? ink : ink.opacity(0.77))
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
