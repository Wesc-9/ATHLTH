import SwiftUI

/// Train → Plan → New plan. The previous Plan card owns templates and Coach;
/// this screen only chooses the depth of manual plan creation.
struct ATHLTHPlanEntryChoiceView: View {
    enum Choice: String, CaseIterable {
        case simple
        case advanced
        // Kept for legacy draft compatibility; Coach opens from the Plan landing page.
        case coach
    }

    @Binding var choice: Choice
    let onChoose: (Choice) -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let paper = ATHLTHTrainDesign.canvas
    private let ink = ATHLTHTrainDesign.ink
    private let bronze = ATHLTHTrainDesign.bronze

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        GeometryReader { viewport in
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(tr("Choose how to build your plan", "Velg hvordan du vil lage planen"))
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if viewport.size.height > 650 {
                    Text(tr("You can customise your plan later.", "Du kan tilpasse planen senere."))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                }
                GeometryReader { available in
                    if typeSize.isAccessibilitySize {
                        ScrollView {
                            cards(cardHeight: 430)
                        }
                    } else {
                        let horizontal = available.size.width > 500 && available.size.width > available.size.height
                        cards(
                            cardHeight: max(0, horizontal ? available.size.height : (available.size.height - 12) / 2),
                            horizontal: horizontal
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(paper.ignoresSafeArea())
    }

    private func cards(cardHeight: CGFloat, horizontal: Bool = false) -> some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 12))
        return layout {
                modeCard(
                    .simple,
                    title: tr("Simple", "Enkel"),
                    description: tr(
                        "Create a plan quickly with just a few choices. Ideal for getting started.",
                        "Lag en plan raskt med få valg. Perfekt for deg som ønsker det enkelt."
                    ),
                    image: "GoalEndurance",
                    symbol: "bolt",
                    features: [
                        tr("Easy step-by-step guide", "Enkel steg-for-steg-guide"),
                        tr("Ready workouts and suggestions", "Ferdige økter og forslag"),
                        tr("A quick and clear plan", "En rask og oversiktlig plan")
                    ],
                    buttonTitle: tr("Choose simple", "Velg enkel"),
                    emphasized: true,
                    cardHeight: cardHeight
                )

                modeCard(
                    .advanced,
                    title: tr("Advanced", "Avansert"),
                    description: tr(
                        "Full control of workouts, exercise details and progression.",
                        "Full kontroll og detaljstyring av økter og progresjon."
                    ),
                    image: "StrengthFeedGym",
                    symbol: "slider.horizontal.3",
                    features: [
                        tr("Detailed week structure", "Detaljert ukeoppsett"),
                        tr("Custom workouts and exercises", "Tilpassede økter og øvelser"),
                        tr("Advanced goals and progression", "Avanserte valg og progresjon")
                    ],
                    buttonTitle: tr("Choose advanced", "Velg avansert"),
                    emphasized: false,
                    cardHeight: cardHeight
                )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Label(tr("Back", "Tilbake"), systemImage: "chevron.left")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 42)
                    .background(.white.opacity(0.93), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(
                            ATHLTHTrainDesign.rule.opacity(0.45),
                            lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Return to Plan", "Tilbake til Plan"))

            Text(tr("New training plan", "Ny treningsplan"))
                .font(.headline)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)

            // Preserve the centered title without introducing a second back button.
            Color.clear
                .frame(width: 85, height: 1)
                .accessibilityHidden(true)
        }
    }

    private func modeCard(
        _ selectedMode: Choice,
        title: String,
        description: String,
        image: String,
        symbol: String,
        features: [String],
        buttonTitle: String,
        emphasized: Bool,
        cardHeight: CGFloat
    ) -> some View {
        Button {
            choice = selectedMode
            onChoose(selectedMode)
        } label: {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.78), location: 0),
                            .init(color: .black.opacity(0.58), location: 0.36),
                            .init(color: .black.opacity(0.14), location: 0.72),
                            .init(color: .black.opacity(0.28), location: 1)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.56)],
                        startPoint: .center, endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        if cardHeight >= 338 {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                emphasized ? bronze.opacity(0.93) : .black.opacity(0.40),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.54), lineWidth: 0.9)
                            }
                            .padding(.bottom, 12)
                        }

                        Text(title)
                            .font(.system(
                                size: cardHeight < 260 ? 28 : 36,
                                weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                            .padding(.bottom, 7)

                        if cardHeight >= 180 {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.94))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 270, alignment: .leading)
                            .padding(.bottom, 8)
                        }

                        if cardHeight >= 300 {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(features, id: \.self) { feature in
                                HStack(alignment: .firstTextBaseline, spacing: 9) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(
                                            Color(red: 0.88, green: 0.74, blue: 0.52))
                                        .font(.system(size: 17))
                                    Text(feature)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.white.opacity(0.95))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        }
                        Spacer(minLength: 6)

                        HStack(spacing: 9) {
                            Spacer()
                            Text(buttonTitle)
                            Image(systemName: "arrow.right")
                            Spacer()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            bronze.gradient,
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .strokeBorder(.white.opacity(0.29), lineWidth: 0.8)
                        }
                    }
                    .padding(cardHeight < 260 ? 14 : 19)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.48), lineWidth: 0.9)
                    .allowsHitTesting(false)
            }
            .shadow(color: ink.opacity(0.12), radius: 15, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            title + ". " + description + ". " + features.joined(separator: ". ")
        )
        .accessibilityHint(tr(
            "Open this plan setup", "Åpner oppsettet for denne planen"))
    }
}
