import SwiftUI

struct ATHLTHTrophyPlateShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.88, y: rect.minY + rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.maxX * 0.72, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.28, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.maxX * 0.12, y: rect.minY + rect.height * 0.16))
        path.closeSubpath()

        return path
    }
}

private enum TrophyVisualForm {
    case emblem
    case medal
    case shield
    case cup
}

struct ATHLTHTrophyCoreView: View {
    let trophy: TrophyProgressItem
    var size: CGFloat = 112
    var showLabel = false
    var inscription: TrophyInscription? = nil
    var athleteName: String? = nil

    private var visualForm: TrophyVisualForm {
        if trophy.category == .challenges {
            return .cup
        }

        if trophy.category == .signature {
            return .emblem
        }

        switch trophy.category {
        case .walking, .endurance:
            return trophy.displayRarity >= .rare
                ? .medal
                : .emblem
        case .strength:
            return trophy.displayRarity >= .epic
                ? .cup
                : .shield
        case .recovery, .consistency:
            return .shield
        case .goals:
            return trophy.displayRarity >= .epic
                ? .medal
                : .emblem
        case .challenges:
            return .cup
        case .signature:
            return .emblem
        }
    }

    private var artworkGradient: LinearGradient {
        let colors: [Color]

        if !trophy.isUnlocked {
            colors = [
                Color(.systemGray5),
                Color(.systemGray4),
                Color(.systemGray3)
            ]
        } else {
            switch trophy.displayRarity {
            case .core:
                colors = [
                    trophy.category
                        .trophyAccent
                        .opacity(0.72),
                    trophy.category
                        .trophyAccent
                        .opacity(0.34),
                    Color.black.opacity(0.78)
                ]
            case .rare:
                colors = [
                    Color.white.opacity(0.82),
                    trophy.category
                        .trophyAccent
                        .opacity(0.92),
                    Color(
                        red: 0.16,
                        green: 0.18,
                        blue: 0.22
                    )
                ]
            case .epic:
                colors = [
                    trophy.category
                        .trophyAccent,
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.84),
                    Color.black.opacity(0.90)
                ]
            case .signature:
                colors = [
                    Color(
                        red: 0.08,
                        green: 0.08,
                        blue: 0.10
                    ),
                    ATHLTHTheme
                        .premiumGold,
                    trophy.category
                        .trophyAccent
                        .opacity(0.86),
                    Color.black
                ]
            }
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var markColor: Color {
        trophy.isUnlocked
            ? .white
            : Color.secondary.opacity(0.42)
    }

    var body: some View {
        VStack(
            spacing:
                showLabel
                    ? 8
                    : 0
        ) {
            artwork
                .frame(
                    width: size,
                    height: size * 1.10
                )
                .accessibilityElement(
                    children: .ignore
                )
                .accessibilityLabel(
                    trophy.isUnlocked
                        ? "\(trophy.title), \(trophy.stageLabel), unlocked"
                        : "\(trophy.title), locked"
                )

            if showLabel {
                VStack(spacing: 2) {
                    Text(trophy.title)
                        .font(
                            .caption
                                .weight(.bold)
                        )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(trophy.stageLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if trophy.isPrestigeTrophy {
            prestigeTrophyArtwork
        } else {
            // Achievements always remain ATHLTH emblems. Their rarity evolves
            // Core → Rare → Epic → Signature without turning into a trophy.
            emblemArtwork
        }
    }

    private var emblemArtwork: some View {
        ZStack {
            ATHLTHTrophyPlateShape()
                .fill(artworkGradient)
                .overlay {
                    ATHLTHTrophyPlateShape()
                        .stroke(
                            Color.white.opacity(
                                trophy.isUnlocked
                                    ? 0.48
                                    : 0.18
                            ),
                            lineWidth: 1.2
                        )
                }

            ATHLTHTrophyPlateShape()
                .fill(
                    Color.black.opacity(
                        trophy.isUnlocked
                            ? 0.10
                            : 0.035
                    )
                )
                .padding(size * 0.10)

            VStack(spacing: size * 0.07) {
                Text(
                    trophy.displayRarity
                        .title
                        .uppercased()
                )
                .font(
                    .system(
                        size:
                            max(
                                6,
                                size * 0.065
                            ),
                        weight: .bold
                    )
                )
                .tracking(size * 0.012)
                .foregroundStyle(
                    .white.opacity(
                        trophy.isUnlocked
                            ? 0.76
                            : 0.42
                    )
                )

                ATHLTHMarkShape()
                    .fill(markColor)
                    .frame(
                        width: size * 0.38,
                        height: size * 0.27
                    )

                Image(
                    systemName:
                        trophy.systemImage
                )
                .font(
                    .system(
                        size: size * 0.11,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .white.opacity(
                        trophy.isUnlocked
                            ? 0.72
                            : 0.30
                    )
                )
            }

            lockedOverlay
        }
        .shadow(
            color:
                trophy.isUnlocked
                    ? trophy.category
                        .trophyAccent
                        .opacity(0.24)
                    : .clear,
            radius: 16,
            y: 8
        )
    }

    private var medalArtwork: some View {
        ZStack {
            VStack(spacing: -size * 0.07) {
                HStack(spacing: size * 0.04) {
                    Capsule()
                        .fill(
                            trophy.isUnlocked
                                ? trophy.category
                                    .trophyAccent
                                    .opacity(0.78)
                                : Color.gray.opacity(0.25)
                        )
                        .frame(
                            width: size * 0.18,
                            height: size * 0.42
                        )
                        .rotationEffect(
                            .degrees(-13)
                        )

                    Capsule()
                        .fill(
                            trophy.isUnlocked
                                ? trophy.category
                                    .trophyAccent
                                    .opacity(0.48)
                                : Color.gray.opacity(0.20)
                        )
                        .frame(
                            width: size * 0.18,
                            height: size * 0.42
                        )
                        .rotationEffect(
                            .degrees(13)
                        )
                }

                ZStack {
                    Circle()
                        .fill(artworkGradient)
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.white.opacity(0.50),
                                    lineWidth: 1.4
                                )
                        }

                    Circle()
                        .stroke(
                            Color.white.opacity(0.18),
                            lineWidth: size * 0.045
                        )
                        .padding(size * 0.08)

                    VStack(spacing: size * 0.04) {
                        ATHLTHMarkShape()
                            .fill(markColor)
                            .frame(
                                width: size * 0.34,
                                height: size * 0.24
                            )

                        Image(
                            systemName:
                                trophy.systemImage
                        )
                        .font(
                            .system(
                                size: size * 0.10,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            .white.opacity(0.72)
                        )
                    }

                    lockedOverlay
                }
                .frame(
                    width: size * 0.78,
                    height: size * 0.78
                )
            }
        }
        .shadow(
            color:
                trophy.isUnlocked
                    ? trophy.category
                        .trophyAccent
                        .opacity(0.24)
                    : .clear,
            radius: 14,
            y: 7
        )
    }

    private var shieldArtwork: some View {
        ZStack {
            Image(
                systemName:
                    "shield.fill"
            )
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                artworkGradient
            )
            .padding(size * 0.04)

            VStack(spacing: size * 0.05) {
                ATHLTHMarkShape()
                    .fill(markColor)
                    .frame(
                        width: size * 0.36,
                        height: size * 0.25
                    )

                Image(
                    systemName:
                        trophy.systemImage
                )
                .font(
                    .system(
                        size: size * 0.11,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    .white.opacity(0.72)
                )
            }
            .offset(y: -size * 0.02)

            lockedOverlay
        }
        .shadow(
            color:
                trophy.isUnlocked
                    ? trophy.category
                        .trophyAccent
                        .opacity(0.22)
                    : .clear,
            radius: 15,
            y: 8
        )
    }

    private var cupArtwork: some View {
        ZStack {
            Image(
                systemName:
                    "trophy.fill"
            )
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                artworkGradient
            )
            .padding(
                .horizontal,
                size * 0.07
            )
            .padding(
                .vertical,
                size * 0.02
            )

            ZStack {
                RoundedRectangle(
                    cornerRadius:
                        size * 0.06,
                    style: .continuous
                )
                .fill(
                    Color.black.opacity(
                        trophy.isUnlocked
                            ? 0.12
                            : 0.04
                    )
                )
                .frame(
                    width: size * 0.45,
                    height: size * 0.34
                )

                VStack(spacing: size * 0.03) {
                    ATHLTHMarkShape()
                        .fill(markColor)
                        .frame(
                            width: size * 0.28,
                            height: size * 0.20
                        )

                    Image(
                        systemName:
                            trophy.systemImage
                    )
                    .font(
                        .system(
                            size: size * 0.085,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.74)
                    )
                }
            }
            .offset(y: -size * 0.09)

            lockedOverlay
        }
        .shadow(
            color:
                trophy.isUnlocked
                    ? trophy.category
                        .trophyAccent
                        .opacity(0.30)
                    : .clear,
            radius: 18,
            y: 9
        )
    }

    private var prestigeTrophyArtwork: some View {
        let athlete =
            inscription?.athlete ??
            athleteName?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .uppercased() ??
            "ATHLTH"
        let achievement =
            inscription?.achievement ??
            trophy.title.uppercased()
        let engraving =
            inscription?.inscription ??
            ATHLTHLocalization.choose(
                english:
                    "VERIFIED PERFORMANCE",
                norwegian:
                    "VERIFISERT PRESTASJON"
            )
            .uppercased()

        return ZStack {
            Image(
                systemName: "trophy.fill"
            )
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                trophy.isUnlocked
                    ? LinearGradient(
                        colors: [
                            Color(
                                red: 1.0,
                                green: 0.88,
                                blue: 0.46
                            ),
                            ATHLTHTheme
                                .premiumGold,
                            Color(
                                red: 0.58,
                                green: 0.36,
                                blue: 0.08
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [
                            Color(
                                .systemGray4
                            ),
                            Color(
                                .systemGray3
                            )
                        ],
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
            )
            .padding(
                .horizontal,
                size * 0.035
            )
            .padding(
                .vertical,
                size * 0.01
            )

            if trophy.isUnlocked {
                VStack(
                    spacing:
                        size >= 150
                            ? size * 0.017
                            : 0
                ) {
                    Text(athlete)
                        .font(
                            .system(
                                size:
                                    max(
                                        5.5,
                                        size * 0.043
                                    ),
                                weight:
                                    .bold
                            )
                        )
                        .tracking(
                            size * 0.006
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.58
                        )

                    Text(achievement)
                        .font(
                            .system(
                                size:
                                    max(
                                        6,
                                        size * 0.048
                                    ),
                                weight:
                                    .heavy
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.52
                        )

                    if size >= 150 {
                        Text(engraving)
                            .font(
                                .system(
                                    size:
                                        max(
                                            5.5,
                                            size *
                                            0.032
                                        ),
                                    weight:
                                        .semibold
                                )
                            )
                            .tracking(
                                size * 0.003
                            )
                            .lineLimit(2)
                            .minimumScaleFactor(
                                0.55
                            )
                    }
                }
                .multilineTextAlignment(
                    .center
                )
                .foregroundStyle(
                    Color(
                        red: 0.98,
                        green: 0.89,
                        blue: 0.62
                    )
                )
                .padding(
                    .horizontal,
                    size * 0.045
                )
                .padding(
                    .vertical,
                    size * 0.035
                )
                .frame(
                    width: size * 0.56,
                    height:
                        size >= 150
                            ? size * 0.29
                            : size * 0.16
                )
                .background(
                    LinearGradient(
                        colors: [
                            Color.black
                                .opacity(
                                    0.86
                                ),
                            Color(
                                red: 0.20,
                                green: 0.14,
                                blue: 0.07
                            )
                            .opacity(0.92)
                        ],
                        startPoint:
                            .top,
                        endPoint:
                            .bottom
                    ),
                    in:
                        RoundedRectangle(
                            cornerRadius:
                                size * 0.035,
                            style:
                                .continuous
                        )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius:
                            size * 0.035,
                        style:
                            .continuous
                    )
                    .stroke(
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.62),
                        lineWidth:
                            max(
                                0.7,
                                size * 0.006
                            )
                    )
                }
                .offset(
                    y:
                        size >= 150
                            ? -size * 0.015
                            : -size * 0.025
                )
            }

            lockedOverlay
        }
        .shadow(
            color:
                trophy.isUnlocked
                    ? ATHLTHTheme
                        .premiumGold
                        .opacity(0.34)
                    : .clear,
            radius: 20,
            y: 10
        )
    }

    @ViewBuilder
    private var lockedOverlay: some View {
        if !trophy.isUnlocked {
            Image(
                systemName: "lock.fill"
            )
            .font(
                .system(
                    size: size * 0.115,
                    weight: .bold
                )
            )
            .foregroundStyle(
                .white.opacity(0.88)
            )
            .padding(size * 0.10)
            .background(
                Color.black.opacity(0.20),
                in: Circle()
            )
        }
    }
}

struct TrophyCabinetSection: View {
    @EnvironmentObject private var trophies: TrophyStore

    var body: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Trophy cabinet",
                            norwegian: "Troféskap"
                        )
                    )
                        .font(.title3.weight(.bold))
                    Text(
                        ATHLTHLocalization.choose(
                            english: "The achievements you choose to display.",
                            norwegian: "Trofeene du selv velger å vise."
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    TrophyCollectionView(
                        startInCabinet: true
                    )
                } label: {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "Open cabinet",
                            norwegian: "Åpne skap"
                        )
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }
            }

            if trophies.showcaseTrophies.isEmpty {
                HStack(spacing: 14) {
                    ATHLTHMarkShape()
                        .fill(.secondary.opacity(0.25))
                        .frame(width: 38, height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your cabinet is waiting")
                            .font(.subheadline.weight(.semibold))
                        Text("Unlocked trophies can be pinned here from the collection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(trophies.showcaseTrophies) { trophy in
                            NavigationLink {
                                TrophyDetailView(trophyID: trophy.id)
                            } label: {
                                ATHLTHTrophyCoreView(
                                    trophy: trophy,
                                    size: 94,
                                    showLabel: true
                                )
                                .frame(width: 112)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

struct TrophyProgressCard: View {
    @EnvironmentObject private var trophies: TrophyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trophy Progress")
                        .font(.headline)
                    Text("What your next effort is building toward.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    TrophyCollectionView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }
            }

            if trophies.nextTrophies.isEmpty {
                Text("Your trophy progress will appear here as ATHLTH reads verified activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(trophies.nextTrophies.prefix(3))) { trophy in
                    NavigationLink {
                        TrophyDetailView(trophyID: trophy.id)
                    } label: {
                        trophyProgressRow(trophy)
                    }
                    .buttonStyle(.plain)

                    if trophy.id != trophies.nextTrophies.prefix(3).last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private func trophyProgressRow(_ trophy: TrophyProgressItem) -> some View {
        HStack(spacing: 12) {
            ATHLTHTrophyCoreView(trophy: trophy, size: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(trophy.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(trophy.nextStage?.title ?? trophy.stageLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(Int((trophy.progress * 100).rounded()))%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.055))
                        Capsule()
                            .fill(ATHLTHTheme.accent)
                            .frame(width: proxy.size.width * trophy.progress)
                    }
                }
                .frame(height: 5)

                Text(progressDescription(trophy))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func progressDescription(_ trophy: TrophyProgressItem) -> String {
        if let completed = trophy.journeyMilestonesCompleted,
           let total = trophy.journeyMilestonesTotal {
            return "\(completed) of \(total) milestones"
        }

        guard let next = trophy.nextStage else {
            return "Complete"
        }

        return ATHLTHLocalization.format(
                            english: "Next · %@",
                            norwegian: "Neste · %@",
                            next.displayTarget
                        )
    }
}

struct TrophyCollectionView: View {
    @EnvironmentObject private var trophies: TrophyStore

    @State private var selectedTab:
        TrophyHubTab
    @State private var filter:
        TrophyCollectionFilter = .all

    init(
        startInCabinet: Bool = false
    ) {
        _selectedTab = State(
            initialValue:
                startInCabinet
                    ? .cabinet
                    : .collection
        )
    }

    private var filtered:
        [TrophyProgressItem] {
        switch filter {
        case .all:
            return trophies.trophies
        case .category(
            let category
        ):
            return trophies.trophies
                .filter {
                    $0.category ==
                        category
                }
        }
    }

    private var unlocked:
        [TrophyProgressItem] {
        trophies.trophies
            .filter(\.isUnlocked)
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                premiumHero
                premiumTabControl

                switch selectedTab {
                case .collection:
                    collectionContent
                case .cabinet:
                    cabinetContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(
                        red: 0.965,
                        green: 0.965,
                        blue: 0.982
                    ),
                    Color(
                        red: 0.985,
                        green: 0.980,
                        blue: 0.970
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(
            ATHLTHLocalization.choose(
                english: "Trophies",
                norwegian: "Troféer"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private var premiumHero:
        some View {
        ZStack(
            alignment: .leading
        ) {
            LinearGradient(
                colors: [
                    Color(
                        red: 0.08,
                        green: 0.09,
                        blue: 0.12
                    ),
                    Color(
                        red: 0.19,
                        green: 0.17,
                        blue: 0.13
                    ),
                    Color(
                        red: 0.10,
                        green: 0.11,
                        blue: 0.16
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ATHLTHMarkShape()
                .fill(
                    Color.white
                        .opacity(0.055)
                )
                .frame(
                    width: 210,
                    height: 150
                )
                .rotationEffect(
                    .degrees(-8)
                )
                .offset(
                    x: 190,
                    y: 8
                )

            HStack(
                alignment: .center,
                spacing: 16
            ) {
                ZStack {
                    ATHLTHTrophyPlateShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black,
                                    ATHLTHTheme
                                        .premiumGold,
                                    Color(
                                        red: 0.16,
                                        green: 0.14,
                                        blue: 0.10
                                    )
                                ],
                                startPoint:
                                    .topLeading,
                                endPoint:
                                    .bottomTrailing
                            )
                        )

                    ATHLTHMarkShape()
                        .fill(.white)
                        .frame(
                            width: 43,
                            height: 31
                        )
                }
                .frame(
                    width: 82,
                    height: 92
                )
                .shadow(
                    color:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.24),
                    radius: 18,
                    y: 9
                )

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(
                        "ATHLTH TROPHIES"
                    )
                    .font(
                        .caption2.bold()
                    )
                    .tracking(2.0)
                    .foregroundStyle(
                        .white.opacity(0.60)
                    )

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "%d unlocked",
                            norwegian:
                                "%d låst opp",
                            trophies
                                .unlockedCount
                        )
                    )
                    .font(
                        .system(
                            size: 28,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                    Text(
                        selectedTab ==
                            .collection
                            ? ATHLTHLocalization.choose(
                                english:
                                    "Every milestone becomes part of your ATHLTH story.",
                                norwegian:
                                    "Hver milepæl blir en del av ATHLTH-historien din."
                            )
                            : ATHLTHLocalization.choose(
                                english:
                                    "Curate four trophies for your public showcase.",
                                norwegian:
                                    "Velg fire trofeer som skal vises på profilen din."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .white.opacity(0.66)
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Spacer(
                    minLength: 0
                )
            }
            .padding(20)
        }
        .frame(height: 150)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white
                    .opacity(0.10),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.12),
            radius: 20,
            y: 10
        )
    }

    private var premiumTabControl:
        some View {
        HStack(spacing: 6) {
            ForEach(
                TrophyHubTab.allCases
            ) { tab in
                Button {
                    withAnimation(
                        .snappy(
                            duration: 0.20
                        )
                    ) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(
                            .subheadline
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            selectedTab ==
                                tab
                                ? Color.white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .frame(height: 44)
                        .background(
                            selectedTab ==
                                tab
                                ? Color(
                                    red: 0.12,
                                    green: 0.13,
                                    blue: 0.17
                                )
                                : Color.clear,
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        15,
                                    style:
                                        .continuous
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            Color.black.opacity(0.055),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var collectionContent:
        some View {
        filters

        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: 150,
                        maximum: 230
                    ),
                    spacing: 12
                )
            ],
            spacing: 12
        ) {
            ForEach(filtered) {
                trophy in
                NavigationLink {
                    TrophyDetailView(
                        trophyID:
                            trophy.id
                    )
                } label: {
                    collectionCard(
                        trophy
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var cabinetContent:
        some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Your trophy cabinet",
                                norwegian:
                                    "Troféskapet ditt"
                            )
                        )
                        .font(
                            .title3
                                .weight(.bold)
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Tap a trophy below to place it in one of four showcase slots.",
                                norwegian:
                                    "Trykk på et trofé under for å plassere det i én av fire plasser."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()

                    Text(
                        "\(trophies.showcaseIDs.count)/\(TrophyStore.showcaseLimit)"
                    )
                    .font(
                        .caption
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                    .padding(
                        .horizontal,
                        10
                    )
                    .padding(
                        .vertical,
                        6
                    )
                    .background(
                        Color.black
                            .opacity(
                                0.72
                            ),
                        in: Capsule()
                    )
                }
            }

            cabinetCase

            if unlocked.isEmpty {
                ContentUnavailableView {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "No unlocked trophies yet",
                            norwegian:
                                "Ingen opplåste trofeer ennå"
                        ),
                        systemImage:
                            "trophy"
                    )
                } description: {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Train, walk, run, recover and complete goals to build your collection.",
                            norwegian:
                                "Tren, gå, løp, restituer og fullfør mål for å bygge samlingen din."
                        )
                    )
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding(
                    .vertical,
                    18
                )
            } else {
                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Choose from unlocked trophies",
                            norwegian:
                                "Velg blant opplåste trofeer"
                        )
                    )
                    .font(
                        .headline
                            .weight(
                                .bold
                            )
                    )

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum:
                                        155,
                                    maximum:
                                        240
                                ),
                                spacing: 10
                            )
                        ],
                        spacing: 10
                    ) {
                        ForEach(
                            unlocked
                        ) { trophy in
                            cabinetPickerRow(
                                trophy
                            )
                        }
                    }
                }
            }
        }
    }

    private var cabinetCase:
        some View {
        VStack(spacing: 0) {
            cabinetShelf(
                startIndex: 0
            )

            cabinetShelf(
                startIndex: 2
            )
        }
        .padding(
            .horizontal,
            14
        )
        .padding(
            .top,
            14
        )
        .padding(
            .bottom,
            12
        )
        .background(
            LinearGradient(
                colors: [
                    Color(
                        red: 0.12,
                        green: 0.11,
                        blue: 0.10
                    ),
                    Color(
                        red: 0.22,
                        green: 0.18,
                        blue: 0.13
                    ),
                    Color(
                        red: 0.08,
                        green: 0.08,
                        blue: 0.09
                    )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 26,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 26,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.24),
                lineWidth: 1
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.16),
            radius: 20,
            y: 10
        )
    }

    private func cabinetShelf(
        startIndex: Int
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                cabinetSlot(
                    index:
                        startIndex
                )

                cabinetSlot(
                    index:
                        startIndex + 1
                )
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            ATHLTHTheme
                                .premiumGold
                                .opacity(
                                    0.48
                                ),
                            Color.white
                                .opacity(
                                    0.16
                                ),
                            Color.black
                                .opacity(
                                    0.50
                                )
                        ],
                        startPoint:
                            .leading,
                        endPoint:
                            .trailing
                    )
                )
                .frame(height: 5)
                .shadow(
                    color:
                        Color.black
                            .opacity(0.34),
                    radius: 5,
                    y: 3
                )
        }
        .padding(
            .bottom,
            10
        )
    }

    @ViewBuilder
    private func cabinetSlot(
        index: Int
    ) -> some View {
        if trophies
            .showcaseTrophies
            .indices
            .contains(index) {
            let trophy =
                trophies
                    .showcaseTrophies[
                        index
                    ]

            Button {
                withAnimation(
                    .snappy(
                        duration: 0.20
                    )
                ) {
                    trophies
                        .toggleShowcase(
                            trophy.id
                        )
                }
            } label: {
                VStack(spacing: 5) {
                    ATHLTHTrophyCoreView(
                        trophy:
                            trophy,
                        size: 88
                    )

                    Text(
                        trophy.title
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.72
                    )
                }
                .frame(
                    maxWidth:
                        .infinity
                )
                .frame(height: 118)
                .background(
                    Color.white
                        .opacity(0.035),
                    in:
                        RoundedRectangle(
                            cornerRadius:
                                17,
                            style:
                                .continuous
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english:
                        "Double tap to remove from the cabinet.",
                    norwegian:
                        "Dobbelttrykk for å fjerne fra skapet."
                )
            )
        } else {
            VStack(spacing: 8) {
                Image(
                    systemName:
                        "plus"
                )
                .font(
                    .system(
                        size: 18,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.72)
                )

                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Empty slot",
                        norwegian:
                            "Tom plass"
                    )
                )
                .font(
                    .caption2
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    .white.opacity(0.44)
                )
            }
            .frame(
                maxWidth: .infinity
            )
            .frame(height: 118)
            .background(
                Color.black.opacity(0.24),
                in:
                    RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
                .stroke(
                    Color.white
                        .opacity(0.08),
                    style:
                        StrokeStyle(
                            lineWidth: 1,
                            dash: [5, 5]
                        )
                )
            }
        }
    }

    private func cabinetPickerRow(
        _ trophy:
            TrophyProgressItem
    ) -> some View {
        let selected =
            trophies.isShowcased(
                trophy.id
            )
        let limitReached =
            trophies.showcaseIDs
                .count >=
            TrophyStore
                .showcaseLimit

        return Button {
            guard selected ||
                !limitReached
            else {
                return
            }

            withAnimation(
                .snappy(
                    duration: 0.20
                )
            ) {
                trophies
                    .toggleShowcase(
                        trophy.id
                    )
            }
        } label: {
            HStack(spacing: 10) {
                ATHLTHTrophyCoreView(
                    trophy:
                        trophy,
                    size: 54
                )

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {
                    Text(
                        trophy.title
                    )
                    .font(
                        .caption
                            .weight(
                                .bold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)

                    Text(
                        trophy.stageLabel
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
                }

                Spacer()

                Image(
                    systemName:
                        selected
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .font(
                    .system(
                        size: 20,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    selected
                        ? ATHLTHTheme
                            .premiumGold
                        : Color.secondary
                            .opacity(0.34)
                )
            }
            .padding(10)
            .background(
                selected
                    ? ATHLTHTheme
                        .champagneSoft
                        .opacity(0.78)
                    : Color.white
                        .opacity(0.92),
                in:
                    RoundedRectangle(
                        cornerRadius: 18,
                        style:
                            .continuous
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    selected
                        ? ATHLTHTheme
                            .premiumGold
                            .opacity(0.50)
                        : Color.black
                            .opacity(0.05),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .opacity(
            !selected &&
            limitReached
                ? 0.52
                : 1
        )
        .disabled(
            !selected &&
            limitReached
        )
    }

    private var filters:
        some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 8) {
                ForEach(
                    TrophyCollectionFilter
                        .allCases
                ) { option in
                    Button {
                        withAnimation(
                            .snappy
                        ) {
                            filter =
                                option
                        }
                    } label: {
                        Text(
                            option.title
                        )
                        .font(
                            .caption
                                .weight(
                                    .semibold
                                )
                        )
                        .foregroundStyle(
                            filter == option
                                ? .white
                                : ATHLTHTheme
                                    .primaryText
                        )
                        .padding(
                            .horizontal,
                            13
                        )
                        .padding(
                            .vertical,
                            8
                        )
                        .background(
                            filter == option
                                ? Color(
                                    red: 0.16,
                                    green: 0.18,
                                    blue: 0.25
                                )
                                : Color.white
                                    .opacity(0.88),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func collectionCard(
        _ trophy:
            TrophyProgressItem
    ) -> some View {
        VStack(spacing: 10) {
            ATHLTHTrophyCoreView(
                trophy:
                    trophy,
                size: 96
            )

            VStack(spacing: 3) {
                Text(trophy.title)
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .multilineTextAlignment(
                        .center
                    )
                    .lineLimit(2)

                Text(
                    trophy.stageLabel
                )
                .font(
                    .caption2
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    trophy.isUnlocked
                        ? trophy.category
                            .trophyAccent
                        : .secondary
                )

                Label(
                    trophy
                        .verificationSource
                        .title,
                    systemImage:
                        trophy
                            .verificationSource
                            .systemImage
                )
                .font(
                    .system(
                        size: 9
                    )
                )
                .foregroundStyle(
                    .secondary
                )
            }

            if !trophy.isComplete {
                ProgressView(
                    value:
                        trophy.progress
                )
                .tint(
                    trophy.category
                        .trophyAccent
                )
            }

            if trophies
                .isShowcased(
                    trophy.id
                ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "In cabinet",
                        norwegian:
                            "I troféskapet"
                    ),
                    systemImage:
                        "checkmark.circle.fill"
                )
                .font(
                    .system(
                        size: 9.5,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .premiumGold
                )
            }
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 190
        )
        .background(
            LinearGradient(
                colors: [
                    Color.white
                        .opacity(0.98),
                    trophy.category
                        .trophyAccent
                        .opacity(
                            trophy
                                .isUnlocked
                                ? 0.055
                                : 0.018
                        )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in:
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
            .stroke(
                trophy.isUnlocked
                    ? trophy.category
                        .trophyAccent
                        .opacity(0.14)
                    : Color.black
                        .opacity(0.045),
                lineWidth: 1
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.045),
            radius: 14,
            y: 7
        )
    }
}

private enum TrophyHubTab:
    String,
    CaseIterable,
    Identifiable {
    case collection
    case cabinet

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .collection:
            return ATHLTHLocalization.choose(
                english: "Collection",
                norwegian: "Samling"
            )
        case .cabinet:
            return ATHLTHLocalization.choose(
                english: "Cabinet",
                norwegian: "Troféskap"
            )
        }
    }
}

struct TrophyDetailView: View {
    @EnvironmentObject private var trophies: TrophyStore
    @EnvironmentObject private var social: SocialStore

    let trophyID: String

    @State private var sharingToATHLTH = false
    @State private var shareSucceeded = false
    @State private var shareError: String?

    private var trophy: TrophyProgressItem? {
        trophies.trophies.first { $0.id == trophyID }
    }

    private var history: [TrophyUnlockRecord] {
        trophies.unlocks
            .filter { $0.trophyID == trophyID }
            .sorted { $0.unlockedAt > $1.unlockedAt }
    }

    var body: some View {
        Group {
            if let trophy {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 16) {
                            ATHLTHTrophyCoreView(
                                trophy: trophy,
                                size: 190
                            )

                            VStack(spacing: 5) {
                                Text(trophy.title)
                                    .font(.largeTitle.bold())
                                    .multilineTextAlignment(.center)

                                Text(trophy.stageLabel.uppercased())
                                    .font(.caption.bold())
                                    .tracking(1.2)
                                    .foregroundStyle(ATHLTHTheme.accent)

                                Text(trophy.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 12)

                        statusCard(trophy)
                        verificationCard(trophy)

                        if !history.isEmpty {
                            historyCard
                        }

                        if trophy.isUnlocked {
                            Button {
                                trophies.toggleShowcase(trophy.id)
                            } label: {
                                Label(
                                    trophies.isShowcased(trophy.id)
                                        ? ATHLTHLocalization.choose(
                                            english: "Remove from Trophy Cabinet",
                                            norwegian: "Fjern fra troféskapet"
                                        )
                                        : ATHLTHLocalization.choose(
                                            english: "Show in Trophy Cabinet",
                                            norwegian: "Vis i troféskapet"
                                        ),
                                    systemImage: trophies.isShowcased(trophy.id)
                                        ? "rectangle.stack.badge.minus"
                                        : "rectangle.stack.badge.plus"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(trophies.isShowcased(trophy.id) ? .secondary : ATHLTHTheme.accent)
                            .disabled(
                                !trophies.isShowcased(trophy.id) &&
                                trophies.showcaseIDs.count >= TrophyStore.showcaseLimit
                            )

                            if let unlock = history.first {
                                Button {
                                    Task {
                                        sharingToATHLTH = true
                                        defer {
                                            sharingToATHLTH = false
                                        }

                                        let shared =
                                            await social
                                                .shareTrophyUnlock(
                                                    unlock
                                                )

                                        shareSucceeded = shared
                                        shareError =
                                            shared
                                                ? nil
                                                : social.errorMessage
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if sharingToATHLTH {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(
                                                systemName:
                                                    shareSucceeded ||
                                                    isSharedInFeed(unlock)
                                                        ? "checkmark.circle.fill"
                                                        : "person.2.fill"
                                            )
                                        }

                                        Text(
                                            shareSucceeded ||
                                            isSharedInFeed(unlock)
                                                ? "Shared to ATHLTH"
                                                : "Share to ATHLTH"
                                        )
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(ATHLTHTheme.accentDeep)
                                .disabled(
                                    sharingToATHLTH ||
                                    shareSucceeded ||
                                    isSharedInFeed(unlock)
                                )
                            }

                            if let shareError {
                                Text(shareError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }

                            if !trophies.isShowcased(trophy.id) &&
                               trophies.showcaseIDs.count >= TrophyStore.showcaseLimit {
                                Text(
                                    ATHLTHLocalization.choose(
                                        english: "Your cabinet can display up to four trophies.",
                                        norwegian: "Troféskapet kan vise opptil fire trofeer."
                                    )
                                )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Trophy")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Trophy unavailable", systemImage: "trophy")
            }
        }
    }

    private func isSharedInFeed(
        _ unlock: TrophyUnlockRecord
    ) -> Bool {
        social.feed.contains {
            $0.activity.actorID == social.currentUserID &&
            $0.activity.eventKey == "trophy-\(unlock.stageKey)"
        }
    }

    private func statusCard(_ trophy: TrophyProgressItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trophy.isComplete ? "Unlocked" : "Progress")
                    .font(.headline)

                Spacer()

                Text(trophy.displayRarity.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        trophy.category.trophyAccent.opacity(0.12),
                        in: Capsule()
                    )
                    .foregroundStyle(trophy.category.trophyAccent)
            }

            if trophy.isComplete {
                if let unlockedAt = trophy.unlockedAt {
                    Label(
                        unlockedAt.formatted(.dateTime.day().month(.wide).year()),
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(ATHLTHTheme.accent)
                }
            } else {
                ProgressView(value: trophy.progress)
                    .tint(ATHLTHTheme.accent)

                HStack {
                    Text("\(Int((trophy.progress * 100).rounded()))%")
                        .font(.title3.bold())

                    Spacer()

                    if let next = trophy.nextStage {
                        Text(ATHLTHLocalization.format(
                            english: "Next · %@",
                            norwegian: "Neste · %@",
                            next.displayTarget
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let completed = trophy.journeyMilestonesCompleted,
               let total = trophy.journeyMilestonesTotal {
                Divider()

                HStack {
                    Label(ATHLTHLocalization.counted(
                            completed,
                            englishSingular: "milestone",
                            englishPlural: "milestones",
                            norwegianSingular: "milepæl",
                            norwegianPlural: "milepæler"
                        ), systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text(ATHLTHLocalization.format(
                            english: "%d total",
                            norwegian: "%d totalt",
                            total
                        ))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .trophyDetailCard()
    }

    private func verificationCard(_ trophy: TrophyProgressItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verification")
                .font(.headline)

            Label(
                trophy.verificationSource.title,
                systemImage: trophy.verificationSource.systemImage
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ATHLTHTheme.accent)

            Text(verificationText(trophy.verificationSource))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .trophyDetailCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evolution")
                .font(.headline)

            ForEach(history) { unlock in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(unlock.category.trophyAccent.opacity(0.10))
                            .frame(width: 38, height: 38)

                        ATHLTHMarkShape()
                            .fill(unlock.category.trophyAccent)
                            .frame(width: 20, height: 15)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(unlock.stageTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(unlock.unlockedAt.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(unlock.rarity.title)
                        .font(.caption2.bold())
                        .foregroundStyle(unlock.category.trophyAccent)
                }
            }
        }
        .padding()
        .trophyDetailCard()
    }

    private func verificationText(_ source: TrophyVerificationSource) -> String {
        switch source {
        case .appleHealth:
            return "Built from qualifying workout or sleep data stored in Apple Health."
        case .athlth:
            return "Built from training detail recorded directly inside ATHLTH."
        case .goal:
            return "Built from the milestones and completion state of an ATHLTH Goal."
        case .challenge:
            return "Built from ATHLTH Challenge participation, verified results and final leaderboards."
        case .mixed:
            return "Built from multiple verified ATHLTH data sources."
        }
    }
}

struct TrophyUnlockRevealView: View {
    @EnvironmentObject private var trophies: TrophyStore
    let unlock: TrophyUnlockRecord

    private var trophy: TrophyProgressItem? {
        trophies.trophies.first { $0.id == unlock.trophyID }
    }

    @State private var revealed = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black,
                    unlock.category.trophyAccent.opacity(0.28),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("NEW ATHLTH TROPHY")
                    .font(.caption.bold())
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.72))

                if let trophy {
                    ATHLTHTrophyCoreView(
                        trophy: trophy,
                        size: 220
                    )
                    .scaleEffect(revealed ? 1 : 0.72)
                    .opacity(revealed ? 1 : 0)
                    .rotation3DEffect(
                        .degrees(revealed ? 0 : -18),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .animation(
                        .spring(response: 0.7, dampingFraction: 0.72),
                        value: revealed
                    )
                }

                VStack(spacing: 6) {
                    Text(unlock.title)
                        .font(.largeTitle.bold())
                    Text(unlock.stageTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(unlock.category.trophyAccent)

                    Label(
                        "ATHLTH · VERIFIED · \(unlock.verificationSource.title.uppercased())",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption.bold())
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.66))
                    .padding(.top, 6)

                    Text(
                        unlock.unlockedAt.formatted(
                            .dateTime.day().month(.wide).year()
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.48))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

                Button("Continue") {
                    trophies.dismissCurrentReveal()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 8)
            }
            .padding(28)
        }
        .onAppear {
            revealed = true
        }
        .sensoryFeedback(.success, trigger: revealed)
    }
}

enum TrophyCollectionFilter: Hashable, Identifiable, CaseIterable {
    case all
    case category(TrophyCategory)

    static var allCases: [TrophyCollectionFilter] {
        [.all] + TrophyCategory.allCases.map { .category($0) }
    }

    var id: String {
        switch self {
        case .all: return "all"
        case .category(let category): return category.rawValue
        }
    }

    var title: String {
        switch self {
        case .all:
            return ATHLTHLocalization.choose(
                english: "All",
                norwegian: "Alle"
            )
        case .category(let category): return category.title
        }
    }
}

private extension TrophyCategory {
    var trophyAccent: Color {
        switch self {
        case .signature:
            return Color(red: 0.92, green: 0.72, blue: 0.26)
        case .walking:
            return Color(red: 0.28, green: 0.70, blue: 0.48)
        case .endurance:
            return Color(red: 0.18, green: 0.64, blue: 0.92)
        case .strength:
            return Color(red: 0.90, green: 0.38, blue: 0.22)
        case .consistency:
            return Color(red: 0.24, green: 0.72, blue: 0.40)
        case .goals:
            return Color(red: 0.50, green: 0.39, blue: 0.92)
        case .recovery:
            return Color(red: 0.31, green: 0.70, blue: 0.75)
        case .challenges:
            return Color(red: 0.72, green: 0.38, blue: 0.92)
        }
    }

    var trophyGradient: [Color] {
        switch self {
        case .signature:
            return [
                Color(red: 0.18, green: 0.16, blue: 0.12),
                trophyAccent,
                Color(red: 0.08, green: 0.08, blue: 0.08)
            ]
        case .walking:
            return [
                Color(red: 0.08, green: 0.22, blue: 0.15),
                trophyAccent,
                Color(red: 0.06, green: 0.10, blue: 0.08)
            ]
        case .strength:
            return [
                Color(red: 0.12, green: 0.12, blue: 0.13),
                trophyAccent.opacity(0.88),
                Color.black
            ]
        default:
            return [
                trophyAccent.opacity(0.92),
                trophyAccent.opacity(0.48),
                Color.black.opacity(0.90)
            ]
        }
    }
}

private extension View {
    func trophyDetailCard() -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }
}
