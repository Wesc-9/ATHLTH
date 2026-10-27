import SwiftUI

/// Lightweight illustration for the first plan step. Everything is native
/// SwiftUI so it renders offline without a heavyweight image asset.
struct ATHLTHPlanModeIllustration: View {
    private let gold = ATHLTHPlanDesign.accent
    private let ink = ATHLTHPlanDesign.ink
    private let cream = Color(red: 0.97, green: 0.947, blue: 0.907)

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [cream.opacity(0.85), cream.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 110
                    )
                )
                .frame(width: 215, height: 215)

            clipboard
                .rotationEffect(.degrees(9))
                .offset(x: -2, y: -7)

            Image(systemName: "dumbbell.fill")
                .font(.system(size: 59, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.22, blue: 0.24),
                                 Color(red: 0.40, green: 0.40, blue: 0.39)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .rotationEffect(.degrees(-17))
                .shadow(color: ink.opacity(0.16), radius: 4, y: 7)
                .offset(x: -27, y: 55)

            bottle
                .offset(x: 73, y: 38)
        }
        .frame(width: 190, height: 177)
        .accessibilityHidden(true)
    }

    private var clipboard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(red: 0.98, green: 0.974, blue: 0.953))
                .frame(width: 105, height: 143)
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(gold.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: ink.opacity(0.10), radius: 12, x: 4, y: 9)

            VStack(alignment: .leading, spacing: 15) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(gold.opacity(0.7))
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule()
                                .fill(gold.opacity(0.17))
                                .frame(width: index == 1 ? 45 : 50, height: 4)
                            Capsule()
                                .fill(gold.opacity(0.10))
                                .frame(width: 33, height: 4)
                        }
                    }
                }
            }
            .padding(.top, 29)

            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [gold.opacity(0.71), gold.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 37, height: 15)
                .offset(y: -6)
        }
    }

    private var bottle: some View {
        VStack(spacing: -1) {
            RoundedRectangle(cornerRadius: 4)
                .fill(ink.opacity(0.83))
                .frame(width: 28, height: 12)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.94, green: 0.91, blue: 0.85),
                                 Color(red: 0.86, green: 0.82, blue: 0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 87)
                .overlay {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(gold.opacity(0.55))
                }
        }
        .shadow(color: ink.opacity(0.12), radius: 5, x: 3, y: 5)
    }
}

/// Mode selection does not navigate. The explicit CTA in the plan wizard
/// advances only after the user has seen both choices.
/// Complete photo-first mode card for the first real Plan creation step.
/// Uses existing bundled photographs, and never persists a second plan model.
struct ATHLTHPlanEntryModeCard: View {
    struct Feature: Identifiable {
        let symbol: String
        let title: String
        var id: String { symbol + title }
    }

    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let features: [Feature]
    var compact = false
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let gold = ATHLTHTrainDesign.gold
    private let paper = ATHLTHTrainDesign.canvas

    private var imageName: String {
        symbol == "sparkles" ? "PlanEntrySimple" : "PlanEntryAdvanced"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                photoSection
                featureSection
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(
                        selected ? bronze.opacity(0.95) : ATHLTHTrainDesign.rule.opacity(0.37),
                        lineWidth: selected ? 1.2 : 0.7
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: ink.opacity(selected ? 0.085 : 0.04), radius: 13, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle + (selected ?
            ATHLTHLocalization.choose(english: ". Selected", norwegian: ". Valgt") : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Select planning mode, then continue.",
            norwegian: "Velg hvordan du vil bygge planen, og trykk så Fortsett."
        ))
    }

    private var photoSection: some View {
        ZStack(alignment: .leading) {
            GeometryReader { bounds in
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }

            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.98), location: 0.31),
                    .init(color: .white.opacity(0.79), location: 0.50),
                    .init(color: .white.opacity(0.22), location: 0.76),
                    .init(color: .white.opacity(0.04), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: compact ? 7 : 9) {
                    Text(title)
                        .font(.system(size: compact ? 27 : 31,
                                      weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: compact ? 11.5 : 12.5))
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? 5 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, compact ? 15 : 18)
                .padding(.top, compact ? 17 : 20)
                .padding(.trailing, compact ? 123 : 141)

                Spacer(minLength: 0)
            }

            Image(systemName: selected ? "checkmark" : "circle")
                .font(.system(size: selected ? 14 : 30, weight: .medium))
                .foregroundStyle(selected ? .white : ink.opacity(0.29))
                .frame(width: 33, height: 33)
                .background {
                    if selected {
                        Circle().fill(gold.gradient)
                    }
                }
                .overlay {
                    if selected {
                        Circle().strokeBorder(.white.opacity(0.8), lineWidth: 0.7)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
                .accessibilityHidden(true)
        }
        .frame(height: typeSize.isAccessibilitySize ? 176 : (compact ? 111 : 124))
        .clipped()
    }

    private var featureSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element.id) { entry in
                    if entry.offset > 0 {
                        Rectangle()
                            .fill(ATHLTHTrainDesign.rule.opacity(0.36))
                            .frame(width: 0.7, height: 20)
                    }
                    feature(entry.element)
                        .frame(maxWidth: .infinity, minHeight: compact ? 39 : 42)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features) { feature($0) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .background(.white)
    }

    private func feature(_ item: Feature) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .foregroundStyle(bronze)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.system(size: compact ? 9.5 : 10.5))
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 3)
    }
}

/// Paired, image-backed shortcuts at the bottom of the first Plan step.
struct ATHLTHPlanExistingChoice: View {
    let title: String
    let subtitle: String
    let symbol: String
    var compact = false
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze

    private var photo: String {
        symbol == "bookmark" ? "GoalMountain" : "GoalAdventure"
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                GeometryReader { bounds in
                    Image(photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.99), location: 0),
                        .init(color: .white.opacity(0.88), location: 0.46),
                        .init(color: .white.opacity(0.37), location: 0.82),
                        .init(color: .white.opacity(0.1), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 18 : 20, weight: .regular))
                        .foregroundStyle(bronze)
                        .frame(width: compact ? 37 : 40,
                               height: compact ? 37 : 40)
                        .background(
                            ATHLTHTrainDesign.paleGold.opacity(0.74),
                            in: Circle()
                        )

                    Spacer(minLength: 1)

                    Text(title)
                        .font(.system(size: compact ? 16 : 18,
                                      weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(alignment: .bottom, spacing: 3) {
                        Text(subtitle)
                            .font(.system(size: compact ? 10 : 11))
                            .foregroundStyle(muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.80))
                    }
                }
                .padding(compact ? 11 : 13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: typeSize.isAccessibilitySize ? 150 : (compact ? 90 : 106))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(
                        ATHLTHTrainDesign.rule.opacity(0.37),
                        lineWidth: 0.7
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: ink.opacity(0.045), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Open this plan collection.",
            norwegian: "Åpne disse planene."
        ))
    }
}
