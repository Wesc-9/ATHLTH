import SwiftUI

/// The actual first screen of Train → Plan → Create. It replaces the
/// previously unreachable/duplicated mode selector; no legacy mode card
/// is rendered behind this screen.
struct ATHLTHPlanEntryChoiceView: View {
    enum Choice: String, CaseIterable {
        case simple
        case advanced
        case coach
    }

    @Binding var choice: Choice
    let onOpenLibrary: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let paper = ATHLTHTrainDesign.canvas
    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let outline = ATHLTHTrainDesign.rule

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                progressHeader
                scenicHero

                modeCard(
                    .simple,
                    title: tr("Simple", "Enkel"),
                    subtitle: tr(
                        "Get started with a clear weekly structure and only the important choices.",
                        "Kom raskt i gang med en enkel ukestruktur og de viktigste valgene."
                    ),
                    icon: "list.clipboard",
                    photo: "PlanEntrySimple",
                    features: [],
                    height: 111
                )

                modeCard(
                    .advanced,
                    title: tr("Advanced", "Avansert"),
                    subtitle: tr(
                        "Build your plan in detail with full control of workouts, progression and structure.",
                        "Bygg planen mer detaljert med full kontroll over økter, progresjon og struktur."
                    ),
                    icon: "chart.bar.fill",
                    photo: "PlanEntryAdvanced",
                    features: [
                        ("chart.bar.fill", tr("More control", "Mer kontroll")),
                        ("list.bullet", tr("Detailed setup", "Detaljert oppsett")),
                        ("gearshape", tr("Tailored", "Skreddersydd"))
                    ],
                    height: 133
                )

                modeCard(
                    .coach,
                    title: tr("Create with Coach", "Lag plan med Coach"),
                    subtitle: tr(
                        "Tell ATHLTH Coach about your goals and get a complete training plan for your everyday life.",
                        "Fortell oss om deg, så lager ATHLTH Coach en komplett treningsplan tilpasset dine mål, din hverdag og din tilgjengelige tid."
                    ),
                    icon: "brain.head.profile",
                    photo: "GoalAdventure",
                    features: [],
                    height: 124
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("PLAN LIBRARY", "PLANBIBLIOTEK"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(muted)
                        .padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)

                    Button(action: onOpenLibrary) {
                        photoSurface(
                            title: tr("Plan library", "Planbibliotek"),
                            subtitle: tr(
                                "Explore ready-made plans for running, strength and more.",
                                "Utforsk ferdige planer for løping, styrke og mer."
                            ),
                            image: "GoalMountain",
                            icon: "book.closed",
                            selected: false,
                            isLibrary: true,
                            features: [],
                            height: 91
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Open plan library", "Åpne planbibliotek"))
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
            .padding(.horizontal, 17)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(paper.ignoresSafeArea())
    }

    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                // The Close action is attached to the wizard, not duplicated
                // here. A neutral title slot preserves the reference layout.
                Text("ATHLTH / PLAN")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.7)
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("1 / 5")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(width: 48, alignment: .trailing)
                    .accessibilityLabel(tr("Step 1 of 5", "Steg 1 av 5"))
            }
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index == 0 ? bronze :
                            Color(red: 0.87, green: 0.85, blue: 0.82))
                        .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var scenicHero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                Image("PlanGoalHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }

            LinearGradient(
                stops: [
                    .init(color: paper, location: 0),
                    .init(color: paper.opacity(0.99), location: 0.29),
                    .init(color: paper.opacity(0.87), location: 0.49),
                    .init(color: paper.opacity(0.19), location: 0.81),
                    .init(color: paper.opacity(0.03), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.7)
                    .foregroundStyle(muted)

                Text(tr(
                    "How do you want to\nbuild your plan?",
                    "Hvordan vil du\nbygge planen?"
                ))
                .font(.system(
                    size: typeSize.isAccessibilitySize ? 33 : 37,
                    weight: .regular,
                    design: .serif
                ))
                .tracking(-0.9)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

                Text(tr(
                    "Choose what fits your everyday life, your goals and how detailed you want to plan.",
                    "Velg metode som passer din hverdag, dine mål og hvor detaljert du ønsker å planlegge."
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 242, alignment: .leading)
            }
            .padding(.leading, 7)
            .padding(.trailing, 88)
        }
        .frame(height: typeSize.isAccessibilitySize ? 252 : 219)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private func modeCard(
        _ option: Choice,
        title: String,
        subtitle: String,
        icon: String,
        photo: String,
        features: [(String, String)],
        height: CGFloat
    ) -> some View {
        Button {
            choice = option
        } label: {
            photoSurface(
                title: title, subtitle: subtitle,
                image: photo, icon: icon,
                selected: choice == option,
                isLibrary: false, features: features,
                height: height
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
        .accessibilityAddTraits(choice == option ? .isSelected : [])
        .accessibilityHint(tr("Choose then continue", "Velg og trykk Fortsett"))
    }

    private func photoSurface(
        title: String,
        subtitle: String,
        image: String,
        icon: String,
        selected: Bool,
        isLibrary: Bool,
        features: [(String, String)],
        height: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                GeometryReader { proxy in
                    Image(image)
                        .resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.99), location: 0),
                        .init(color: .white.opacity(0.96), location: 0.32),
                        .init(color: .white.opacity(0.79), location: 0.58),
                        .init(color: .white.opacity(0.08), location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(bronze)
                        .frame(width: 44, height: 44)
                        .background(
                            ATHLTHTrainDesign.paleGold.opacity(0.76),
                            in: Circle()
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(title)
                                .font(.system(size: 21, weight: .medium, design: .serif))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            if !isLibrary && title == tr("Create with Coach", "Lag plan med Coach") {
                                Text("AI")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(bronze, in: Capsule())
                            }
                        }

                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(muted)
                            .lineLimit(typeSize.isAccessibilitySize ? 6 : 4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 232, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: selected ? 25 : 16,
                                      weight: selected ? .medium : .semibold))
                        .foregroundStyle(bronze)
                        .frame(width: 27, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .leading)
            }
            .frame(height: typeSize.isAccessibilitySize ? height + 48 : height)
            .clipped()

            if !features.isEmpty {
                HStack(spacing: 0) {
                    ForEach(features.indices, id: \.self) { index in
                        if index > 0 {
                            Rectangle()
                                .fill(outline.opacity(0.35))
                                .frame(width: 0.7, height: 18)
                        }
                        Label(features[index].1, systemImage: features[index].0)
                            .font(.system(size: 10))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                            .frame(maxWidth: .infinity, minHeight: 35)
                    }
                }
                .padding(.horizontal, 6)
                .background(.white.opacity(0.92))
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 19))
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(
                    selected ? bronze.opacity(0.95) : outline.opacity(0.38),
                    lineWidth: selected ? 1.4 : 0.7
                )
                .allowsHitTesting(false)
        }
        .shadow(color: ink.opacity(selected ? 0.075 : 0.045),
                radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 19))
    }
}
