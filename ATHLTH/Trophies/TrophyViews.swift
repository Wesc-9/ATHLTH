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

/// A single consistent award renderer in profile, collection, details
/// and unlock animations. The previous Core/Rare/Epic/Signature variants
/// mixed shields, flat SF trophy icons and dark badges.
struct ATHLTHTrophyCoreView: View {
    let trophy: TrophyProgressItem
    var size: CGFloat = 112
    var showLabel = false
    var showActivityIconInside = true
    var revealRarity: TrophyRarity? = nil
    var inscription: TrophyInscription? = nil
    var athleteName: String? = nil

    var body: some View {
        VStack(spacing: showLabel ? 8 : 0) {
            Group {
                if trophy.isPrestigeTrophy {
                    ATHLTHGoldPrestigeCupArtwork(
                        size: size,
                        isUnlocked: trophy.isUnlocked,
                        engravedName: inscription?.athlete ?? athleteName
                    )
                } else {
                    ATHLTHMetalMedalArtwork(
                        trophy: trophy,
                        size: size,
                        showActivityIcon: showActivityIconInside,
                        rarityOverride: revealRarity
                    )
                    .frame(width: size, height: size * 1.10)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                trophy.isUnlocked
                    ? "\(trophy.title), \(trophy.stageLabel), \(trophy.isPrestigeTrophy ? "gullpokal" : ATHLTHMedalMetal(rarity: revealRarity ?? trophy.displayRarity).title)"
                    : "\(trophy.title), \(ATHLTHLocalization.choose(english: "Locked", norwegian: "Låst"))"
            )

            if showLabel {
                VStack(spacing: 2) {
                    Text(trophy.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)

                    Text(trophy.isPrestigeTrophy
                         ? ATHLTHLocalization.choose(
                             english: "Prestige trophy", norwegian: "Prestisjepokal"
                           )
                         : ATHLTHMedalMetal(rarity: revealRarity ?? trophy.displayRarity).title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
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
                            english: "Display your favourite medals and most prestigious gold cups.",
                            norwegian: "Vis favorittmedaljene dine og de største gullpokalene."
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
                            english: "Open shelf",
                            norwegian: "Åpne hylle"
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
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Your trophy cabinet is waiting",
                                norwegian:
                                    "Troféskapet ditt venter"
                            )
                        )
                            .font(.subheadline.weight(.semibold))
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    "Earn medals or a gold prestige cup, then choose up to four for your profile.",
                                norwegian:
                                    "Tjen medaljer eller prestisjepokaler i gull, og velg opptil fire til profilen."
                            )
                        )
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
                                    size:
                                        trophy.isPrestigeTrophy
                                            ? 106
                                            : 86,
                                    showLabel: true,
                                    inscription:
                                        trophies
                                            .inscription(
                                                for:
                                                    trophy.id
                                            )
                                )
                                .offset(
                                    y:
                                        trophy.isPrestigeTrophy
                                            ? -6
                                            : 4
                                )
                                .frame(
                                    width:
                                        trophy.isPrestigeTrophy
                                            ? 126
                                            : 108
                                )
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
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Medal progress",
                            norwegian:
                                "Medaljefremdrift"
                        )
                    )
                        .font(.headline)
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Advance from bronze through silver to gold.",
                            norwegian:
                                "Gå fra bronse via sølv til gull."
                        )
                    )
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

            if trophies.nextAchievements.isEmpty {
                Text(
                    ATHLTHLocalization.choose(
                        english:
                            "Medal progress appears here as ATHLTH reads verified activity.",
                        norwegian:
                            "Medaljefremdrift vises her når ATHLTH leser verifisert aktivitet."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(trophies.nextAchievements.prefix(3))) { trophy in
                    NavigationLink {
                        TrophyDetailView(trophyID: trophy.id)
                    } label: {
                        trophyProgressRow(trophy)
                    }
                    .buttonStyle(.plain)

                    if trophy.id != trophies.nextAchievements.prefix(3).last?.id {
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
    @State private var showingShelfPicker: Bool
    @State private var replacementTrophyID:
        String?

    init(
        startInCabinet: Bool = false,
        replacingTrophyID: String? = nil
    ) {
        _selectedTab = State(
            initialValue:
                startInCabinet
                    ? .shelf
                    : .collection
        )
        _showingShelfPicker = State(
            initialValue:
                replacingTrophyID != nil
        )
        _replacementTrophyID = State(
            initialValue:
                replacingTrophyID
        )
    }

    private var filtered:
        [TrophyProgressItem] {
        switch filter {
        case .all:
            return trophies.trophies
                .filter {
                    !$0.isPrestigeTrophy
                }
        case .category(
            let category
        ):
            return trophies.trophies
                .filter {
                    !$0.isPrestigeTrophy &&
                    $0.category ==
                        category
                }
        }
    }

    private var prestige:
        [TrophyProgressItem] {
        trophies.prestigeTrophies
    }

    private var unlocked:
        [TrophyProgressItem] {
        trophies
            .unlockedCabinetCandidates
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
                case .trophies:
                    trophiesContent
                case .shelf:
                    shelfContent
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
                english:
                    "Medals & Trophies",
                norwegian:
                    "Medaljer og pokaler"
            )
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .sheet(
            isPresented:
                $showingShelfPicker
        ) {
            shelfPickerSheet
                .presentationDetents(
                    [.medium, .large]
                )
                .presentationDragIndicator(
                    .visible
                )
        }
    }

    private var shelfPickerCandidates:
        [TrophyProgressItem] {
        unlocked.filter {
            !trophies
                .isShowcased($0.id)
        }
    }

    private var shelfPickerSheet:
        some View {
        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    replacementTrophyID == nil
                                        ? "Choose an award"
                                        : "Replace trophy",
                                norwegian:
                                    replacementTrophyID == nil
                                        ? "Velg en utmerkelse"
                                        : "Bytt trofé"
                            )
                        )
                        .font(
                            .title2
                                .weight(.bold)
                        )

                        Text(
                            ATHLTHLocalization.choose(
                                english:
                                    replacementTrophyID == nil
                                        ? "Medals and gold cups are shown together, highest tier first."
                                        : "Choose an unlocked award to replace the selected trophy in the same shelf position.",
                                norwegian:
                                    replacementTrophyID == nil
                                        ? "Medaljer og gullpokaler vises samlet, fra høyeste nivå."
                                        : "Velg en opplåst utmerkelse som skal erstatte troféet i samme plass på hyllen."
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    if shelfPickerCandidates
                        .isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "No unlocked awards available",
                                norwegian:
                                    "Ingen ledige utmerkelser"
                            ),
                            systemImage:
                                "trophy",
                            description: Text(
                                ATHLTHLocalization.choose(
                                    english:
                                        "Unlock another medal or gold cup to add it here.",
                                    norwegian:
                                        "Lås opp en ny medalje eller gullpokal for å legge den til her."
                                )
                            )
                        )
                        .padding(.top, 28)
                    } else {
                        ForEach(
                            [
                                TrophyRarity
                                    .signature,
                                .epic,
                                .rare,
                                .core
                            ],
                            id: \.self
                        ) { rarity in
                            let items =
                                shelfPickerCandidates
                                    .filter {
                                        $0
                                            .displayRarity ==
                                        rarity
                                    }

                            if !items.isEmpty {
                                VStack(
                                    alignment:
                                        .leading,
                                    spacing: 8
                                ) {
                                    HStack {
                                        Text(
                                            rarity
                                                .title
                                                .uppercased()
                                        )
                                        .font(
                                            .caption
                                                .weight(
                                                    .bold
                                                )
                                        )
                                        .tracking(1.1)

                                        Spacer()

                                        Text(
                                            items.count
                                                .formatted()
                                        )
                                        .font(
                                            .caption2
                                                .weight(
                                                    .semibold
                                                )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .mutedText
                                        )
                                    }
                                    .foregroundStyle(
                                        rarity ==
                                            .signature
                                            ? ATHLTHTheme
                                                .premiumGold
                                            : ATHLTHTheme
                                                .primaryText
                                    )

                                    ForEach(
                                        items
                                    ) {
                                        item in
                                        cabinetPickerRow(
                                            item
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(
                Color(
                    .systemGroupedBackground
                )
            )
            .navigationTitle(
                ATHLTHLocalization.choose(
                    english:
                        "Trophy shelf",
                    norwegian:
                        "Trofehylle"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {
                    Button(
                        ATHLTHLocalization.choose(
                            english: "Done",
                            norwegian: "Ferdig"
                        )
                    ) {
                        replacementTrophyID =
                            nil
                        showingShelfPicker =
                            false
                    }
                }
            }
        }
    }

    private var heroEyebrow:
        String {
        switch selectedTab {
        case .collection:
            return "ATHLTH ACHIEVEMENTS"
        case .trophies:
            return ATHLTHLocalization.choose(
                english:
                    "ATHLTH GOLD TROPHIES",
                norwegian:
                    "ATHLTH GULLPOKALER"
            )
        case .shelf:
            return ATHLTHLocalization.choose(
                english:
                    "YOUR TROPHY SHELF",
                norwegian:
                    "DIN TROFEHYLLE"
            )
        }
    }

    private var heroCountText:
        String {
        let count: Int

        switch selectedTab {
        case .collection:
            count =
                trophies
                    .unlockedAchievementCount
        case .trophies:
            count =
                trophies
                    .unlockedPrestigeTrophyCount
        case .shelf:
            count =
                trophies
                    .showcaseTrophies
                    .count
        }

        if selectedTab == .shelf {
            return ATHLTHLocalization.choose(
                english:
                    "\(count)/\(TrophyStore.showcaseLimit) selected",
                norwegian:
                    "\(count)/\(TrophyStore.showcaseLimit) valgt"
            )
        }

        return ATHLTHLocalization.format(
            english:
                "%d unlocked",
            norwegian:
                "%d låst opp",
            count
        )
    }

    private var heroSubtitle:
        String {
        switch selectedTab {
        case .collection:
            return ATHLTHLocalization.choose(
                english:
                    "Build clean performance emblems that evolve with your training.",
                norwegian:
                    "Bygg prestasjonsemblemer som utvikler seg med treningen din."
            )
        case .trophies:
            return ATHLTHLocalization.choose(
                english:
                    "Verified gold trophies mark the performances that stand apart.",
                norwegian:
                    "Verifiserte gullpokaler markerer prestasjonene som virkelig skiller seg ut."
            )
        case .shelf:
            return ATHLTHLocalization.choose(
                english:
                    "Only the awards you choose are displayed here and on your profile.",
                norwegian:
                    "Her vises kun utmerkelsene du selv velger – også på profilen din."
            )
        }
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
                ATHLTHMintedBrandSeal(
                    size: 86,
                    metal: .gold
                )
                .frame(width: 86, height: 92)
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
                    Text(heroEyebrow)
                    .font(
                        .caption2.bold()
                    )
                    .tracking(2.0)
                    .foregroundStyle(
                        .white.opacity(0.60)
                    )

                    Text(heroCountText)
                    .font(
                        .system(
                            size: 28,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)

                    Text(heroSubtitle)
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
                            .system(
                                size: 12,
                                weight:
                                    .semibold
                            )
                        )
                        .minimumScaleFactor(
                            0.80
                        )
                        .lineLimit(1)
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
    private var trophiesContent:
        some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Gold trophies",
                    norwegian:
                        "Gullpokaler"
                )
            )
            .font(
                .title3
                    .weight(.bold)
            )

            Text(
                ATHLTHLocalization.choose(
                    english:
                        "Harder, verified milestones. Half marathon and marathon are joined by 30K and 50K ultra-distance trophies.",
                    norwegian:
                        "Vanskeligere, verifiserte milepæler. Halvmaraton og maraton får nå selskap av 30K og 50K ultra-distanser."
                )
            )
            .font(.caption)
            .foregroundStyle(
                ATHLTHTheme
                    .mutedText
            )

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 155,
                            maximum: 240
                        ),
                        spacing: 10
                    )
                ],
                spacing: 10
            ) {
                ForEach(prestige) {
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
    }

    @ViewBuilder
    private var shelfContent:
        some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(
                alignment:
                    .firstTextBaseline
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Trophy shelf",
                            norwegian:
                                "Trofehylle"
                        )
                    )
                    .font(
                        .title3
                            .weight(.bold)
                    )

                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "A curated display of up to four awards you choose.",
                            norwegian:
                                "En kuratert hylle med opptil fire utmerkelser du velger selv."
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
            }

            cabinetCase

            if trophies
                .showcaseTrophies
                .isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "Open an unlocked award and choose “Show on trophy shelf”.",
                        norwegian:
                            "Åpne en opplåst utmerkelse og velg «Vis på trofehyllen»."
                    ),
                    systemImage:
                        "sparkles"
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .frame(
                    maxWidth:
                        .infinity,
                    alignment:
                        .center
                )
                .padding(.top, 2)
            }
        }
    }

    private var cabinetCase:
        some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color(
                            red: 0.055,
                            green: 0.060,
                            blue: 0.075
                        ),
                        Color(
                            red: 0.12,
                            green: 0.105,
                            blue: 0.085
                        ),
                        Color(
                            red: 0.035,
                            green: 0.038,
                            blue: 0.050
                        )
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                )
            )

            RadialGradient(
                colors: [
                    ATHLTHTheme
                        .premiumGold
                        .opacity(0.22),
                    .clear
                ],
                center: .top,
                startRadius: 4,
                endRadius: 240
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 28,
                    style: .continuous
                )
            )

            VStack(spacing: 4) {
                HStack {
                    Label(
                        ATHLTHLocalization.choose(
                            english:
                                "TROPHY SHELF",
                            norwegian:
                                "TROFEHYLLE"
                        ),
                        systemImage:
                            "sparkles"
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .tracking(1.3)
                    .foregroundStyle(
                        .white
                            .opacity(0.66)
                    )

                    Spacer()

                    Text(
                        "\(trophies.showcaseTrophies.count) / \(TrophyStore.showcaseLimit)"
                    )
                    .font(
                        .caption2
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                }
                .padding(
                    .horizontal,
                    4
                )
                .padding(
                    .bottom,
                    4
                )

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
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white
                            .opacity(0.24),
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.34),
                        Color.white
                            .opacity(0.06)
                    ],
                    startPoint:
                        .topLeading,
                    endPoint:
                        .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .shadow(
            color:
                ATHLTHTheme
                    .premiumGold
                    .opacity(0.10),
            radius: 24,
            y: 10
        )
        .animation(
            .snappy(
                duration: 0.30
            ),
            value:
                trophies
                    .showcaseIDs
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

            NavigationLink {
                TrophyDetailView(
                    trophyID:
                        trophy.id
                )
            } label: {
                VStack(spacing: 5) {
                    ATHLTHTrophyCoreView(
                        trophy:
                            trophy,
                        size:
                            trophy.isPrestigeTrophy
                                ? 104
                                : 78,
                        inscription:
                            trophies
                                .inscription(
                                    for:
                                        trophy.id
                                )
                    )
                    .offset(
                        y:
                            trophy.isPrestigeTrophy
                                ? -8
                                : 4
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
                .frame(height: 128)
                .background(
                    Color.white
                        .opacity(
                            trophy.isPrestigeTrophy
                                ? 0.055
                                : 0.030
                        ),
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
            .transition(
                .scale(
                    scale: 0.84
                )
                .combined(
                    with: .opacity
                )
            )
            .shadow(
                color:
                    trophy
                        .isPrestigeTrophy
                        ? ATHLTHTheme
                            .premiumGold
                            .opacity(0.34)
                        : trophy
                            .category
                            .trophyAccent
                            .opacity(0.22),
                radius: 16,
                y: 4
            )
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english:
                        "Double tap to open this award. You can remove it from the trophy shelf in the detail view.",
                    norwegian:
                        "Dobbelttrykk for å åpne utmerkelsen. Du kan fjerne den fra trofehyllen i detaljvisningen."
                )
            )
        } else {
            Button {
                showingShelfPicker =
                    true
            } label: {
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
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english:
                        "Double tap to choose an unlocked achievement or trophy.",
                    norwegian:
                        "Dobbelttrykk for å velge en opplåst medalje eller gullpokal."
                )
            )
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
            guard !selected
            else {
                return
            }

            if let replacementTrophyID {
                withAnimation(
                    .snappy(
                        duration: 0.20
                    )
                ) {
                    trophies
                        .replaceShowcase(
                            replacementTrophyID,
                            with:
                                trophy.id
                        )
                }
                self.replacementTrophyID =
                    nil
                showingShelfPicker = false
                return
            }

            guard !limitReached
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
            showingShelfPicker = false
        } label: {
            HStack(spacing: 10) {
                ATHLTHTrophyCoreView(
                    trophy:
                        trophy,
                    size: 54,
                    inscription:
                        trophies
                            .inscription(
                                for:
                                    trophy.id
                            )
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
                        "\(trophy.awardClass.title) · \(trophy.displayRarity.title)"
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
            if trophy.isPrestigeTrophy {
                ATHLTHTrophyCoreView(
                    trophy:
                        trophy,
                    size: 96,
                    inscription:
                        trophies
                            .inscription(
                                for:
                                    trophy.id
                            )
                )
            } else {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(
                                Color.black
                                    .opacity(0.065),
                                lineWidth: 4
                            )

                        Circle()
                            .trim(
                                from: 0,
                                to:
                                    trophy.isComplete
                                        ? 1
                                        : trophy.progress
                            )
                            .stroke(
                                AngularGradient(
                                    colors:
                                        trophy
                                            .displayRarity
                                            .progressPalette,
                                    center: .center
                                ),
                                style:
                                    StrokeStyle(
                                        lineWidth: 4,
                                        lineCap:
                                            .round
                                    )
                            )
                            .rotationEffect(
                                .degrees(-90)
                            )

                        ATHLTHTrophyCoreView(
                            trophy:
                                trophy,
                            size: 86,
                            showActivityIconInside:
                                false,
                            inscription:
                                trophies
                                    .inscription(
                                        for:
                                            trophy.id
                                    )
                        )
                    }
                    .frame(
                        width: 112,
                        height: 112
                    )

                    collectionActivityBadge(
                        trophy
                    )
                }
            }

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

                if trophy.isPrestigeTrophy {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Gold Trophy",
                            norwegian:
                                "Gullpokal"
                        )
                    )
                    .font(
                        .caption2
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .premiumGold
                    )
                } else if trophy.stageLabel
                    .lowercased() !=
                    trophy.displayRarity
                        .title
                        .lowercased() {
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
                        ATHLTHTheme
                            .mutedText
                    )
                }

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
                GeometryReader {
                    proxy in
                    ZStack(
                        alignment:
                            .leading
                    ) {
                        Capsule()
                            .fill(
                                Color.black
                                    .opacity(
                                        0.06
                                    )
                            )

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors:
                                        trophy
                                            .displayRarity
                                            .progressPalette,
                                    startPoint:
                                        .leading,
                                    endPoint:
                                        .trailing
                                )
                            )
                            .frame(
                                width:
                                    proxy
                                        .size
                                        .width *
                                    trophy
                                        .progress
                            )
                    }
                }
                .frame(height: 6)

                if let progressText =
                        trophy
                            .concreteProgressText {
                    Text(progressText)
                        .font(
                            .system(
                                size: 9.5,
                                weight:
                                    .semibold,
                                design:
                                    .rounded
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(
                            0.72
                        )
                }
            }

            if trophies
                .isShowcased(
                    trophy.id
                ) {
                Label(
                    ATHLTHLocalization.choose(
                        english:
                            "On shelf",
                        norwegian:
                            "På trofehyllen"
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
                        .opacity(0.985),
                    Color.black
                        .opacity(
                            trophy
                                .isUnlocked
                                ? 0.018
                                : 0.010
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
                Color.black
                    .opacity(
                        trophy.isUnlocked
                            ? 0.065
                            : 0.040
                    ),
                lineWidth: 0.9
            )
        }
        .shadow(
            color:
                Color.black.opacity(0.045),
            radius: 14,
            y: 7
        )
    }
    private func collectionActivityBadge(
        _ trophy:
            TrophyProgressItem
    ) -> some View {
        Image(
            systemName:
                trophy.systemImage
        )
        .font(
            .system(
                size: 13,
                weight: .bold
            )
        )
        .foregroundStyle(
            trophy.isUnlocked
                ? Color.white
                : Color.white
                    .opacity(0.46)
        )
        .frame(
            width: 30,
            height: 30
        )
        .background(
            LinearGradient(
                colors: [
                    Color(
                        red: 0.20,
                        green: 0.22,
                        blue: 0.24
                    ),
                    Color(
                        red: 0.08,
                        green: 0.09,
                        blue: 0.10
                    )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: Circle()
        )
        .overlay {
            Circle()
                .stroke(
                    trophy.isUnlocked
                        ? ATHLTHTheme
                            .premiumGold
                            .opacity(0.56)
                        : Color.white
                            .opacity(0.18),
                    lineWidth: 1
                )
        }
        .shadow(
            color:
                Color.black
                    .opacity(0.10),
            radius: 5,
            y: 2
        )
        .accessibilityHidden(true)
    }

}

private enum TrophyHubTab:
    String,
    CaseIterable,
    Identifiable {
    case collection
    case trophies
    case shelf

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .collection:
            return ATHLTHLocalization.choose(
                english: "Achievements",
                norwegian: "Medaljer"
            )
        case .trophies:
            return ATHLTHLocalization.choose(
                english: "Trophies",
                norwegian: "Pokaler"
            )
        case .shelf:
            return ATHLTHLocalization.choose(
                english: "Shelf",
                norwegian: "Troféskap"
            )
        }
    }
}

struct TrophyDetailView: View {
    @EnvironmentObject private var trophies: TrophyStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: AppSessionStore

    let trophyID: String

    @State private var sharingToATHLTH = false
    @State private var shareSucceeded = false
    @State private var shareError: String?
    @State private var inscription:
        TrophyInscription?
    @State private var shelfFeedback =
        0

    private var trophy: TrophyProgressItem? {
        trophies.trophies.first { $0.id == trophyID }
    }

    private var history: [TrophyUnlockRecord] {
        trophies.unlocks
            .filter { $0.trophyID == trophyID }
            .sorted { $0.unlockedAt > $1.unlockedAt }
    }

    private var athleteName: String {
        let username =
            session.profile.username
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        if !username.isEmpty {
            return username
        }

        let displayName =
            session.profile.displayName
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

        return displayName.isEmpty
            ? "ATHLTH ATHLETE"
            : displayName
    }

    var body: some View {
        Group {
            if let trophy {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 16) {
                            ATHLTHTrophyCoreView(
                                trophy: trophy,
                                size: 190,
                                inscription:
                                    inscription,
                                athleteName:
                                    athleteName
                            )

                            VStack(spacing: 5) {
                                Text(trophy.title)
                                    .font(.largeTitle.bold())
                                    .multilineTextAlignment(.center)

                                if trophy.isPrestigeTrophy {
                                    Text(
                                        ATHLTHLocalization.choose(
                                            english:
                                                "GOLD TROPHY",
                                            norwegian:
                                                "GULLPOKAL"
                                        )
                                    )
                                    .font(.caption.bold())
                                    .tracking(1.2)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .premiumGold
                                    )
                                } else if trophy.stageLabel
                                    .lowercased() !=
                                    trophy.displayRarity
                                        .title
                                        .lowercased() {
                                    Text(
                                        trophy.stageLabel
                                            .uppercased()
                                    )
                                    .font(.caption.bold())
                                    .tracking(1.2)
                                    .foregroundStyle(
                                        ATHLTHTheme
                                            .mutedText
                                    )
                                }

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
                                        english: "Your trophy shelf can display up to four achievements or trophies.",
                                        norwegian: "Troféskapet kan vise opptil fire medaljer eller gullpokaler."
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
                .navigationTitle(
                    trophy.isPrestigeTrophy
                        ? ATHLTHLocalization.choose(
                            english: "Trophy",
                            norwegian: "Pokal"
                        )
                        : ATHLTHLocalization.choose(
                            english: "Achievement",
                            norwegian: "Medalje"
                        )
                )
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(
                    edge: .bottom,
                    spacing: 0
                ) {
                    showcaseStickyBar(
                        trophy
                    )
                }
            } else {
                ContentUnavailableView("Trophy unavailable", systemImage: "trophy")
            }
        }
        .task(id: trophyID) {
            guard let trophy,
                  trophy.isPrestigeTrophy,
                  trophy.isUnlocked
            else {
                inscription = nil
                return
            }

            if let cached =
                    trophies
                        .inscription(
                            for:
                                trophy.id
                        ) {
                inscription =
                    cached
                return
            }

            let resolution =
                await TrophyInscriptionAIService
                    .shared
                    .inscription(
                        trophyID:
                            trophy.id,
                        username:
                            athleteName,
                        achievementTitle:
                            trophy.title,
                        achievementDetail:
                            trophy.subtitle,
                        unlockedAt:
                            trophy.unlockedAt
                    )
            inscription =
                resolution.inscription

            if resolution.isPersisted {
                trophies
                    .cacheInscription(
                        resolution
                            .inscription,
                        for:
                            trophy.id
                    )
            }
        }
    }

    @ViewBuilder
    private func showcaseStickyBar(
        _ trophy:
            TrophyProgressItem
    ) -> some View {
        if trophy.isUnlocked {
            let selected =
                trophies
                    .isShowcased(
                        trophy.id
                    )
            let full =
                trophies
                    .showcaseIDs
                    .count >=
                TrophyStore
                    .showcaseLimit

            VStack(spacing: 6) {
                Button {
                    trophies
                        .toggleShowcase(
                            trophy.id
                        )
                    shelfFeedback += 1
                } label: {
                    HStack(
                        spacing: 9
                    ) {
                        Image(
                            systemName:
                                selected
                                    ? "rectangle.stack.badge.minus"
                                    : "rectangle.stack.badge.plus"
                        )

                        Text(
                            selected
                                ? ATHLTHLocalization.choose(
                                    english:
                                        "Remove from trophy shelf",
                                    norwegian:
                                        "Fjern fra trofehyllen"
                                )
                                : full
                                    ? ATHLTHLocalization.choose(
                                        english:
                                            "Trophy shelf is full",
                                        norwegian:
                                            "Trofehyllen er full"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english:
                                            "Show on trophy shelf",
                                        norwegian:
                                            "Vis på trofehyllen"
                                    )
                        )
                        .font(.headline)
                    }
                    .frame(
                        maxWidth:
                            .infinity
                    )
                    .frame(height: 50)
                }
                .buttonStyle(
                    .borderedProminent
                )
                .tint(
                    selected
                        ? Color(
                            .systemGray3
                        )
                        : trophy
                            .isPrestigeTrophy
                            ? ATHLTHTheme
                                .premiumGold
                            : trophy
                                .category
                                .trophyAccent
                )
                .foregroundStyle(
                    selected
                        ? ATHLTHTheme
                            .primaryText
                        : .white
                )
                .disabled(
                    !selected &&
                    full
                )
                .sensoryFeedback(
                    .success,
                    trigger:
                        shelfFeedback
                )

                if !selected &&
                   full {
                    Text(
                        ATHLTHLocalization.choose(
                            english:
                                "Remove one item from the shelf before adding another.",
                            norwegian:
                                "Fjern én utmerkelse fra hyllen før du legger til en ny."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                }
            }
            .padding(
                .horizontal,
                16
            )
            .padding(
                .top,
                10
            )
            .padding(
                .bottom,
                8
            )
            .background(
                .ultraThinMaterial
            )
            .overlay(
                Rectangle()
                    .fill(
                        Color.white
                            .opacity(0.58)
                    )
                    .frame(height: 0.5),
                alignment: .top
            )
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

                Text(
                    trophy.isPrestigeTrophy
                        ? ATHLTHLocalization.choose(
                            english:
                                "Gold Trophy",
                            norwegian:
                                "Gullpokal"
                        )
                        : trophy.displayRarity.title
                )
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
                HStack(
                    alignment: .center,
                    spacing: 14
                ) {
                    AchievementProgressRing(
                        progress:
                            trophy.progress,
                        rarity:
                            trophy.displayRarity,
                        lineWidth: 5
                    )
                    .frame(
                        width: 52,
                        height: 52
                    )
                    .padding(5)
                    .background(
                        Color.black
                            .opacity(0.78),
                        in: Circle()
                    )

                    GeometryReader {
                        proxy in
                        ZStack(
                            alignment:
                                .leading
                        ) {
                            Capsule()
                                .fill(
                                    Color.black
                                        .opacity(
                                            0.07
                                        )
                                )

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors:
                                            trophy
                                                .displayRarity
                                                .progressPalette,
                                        startPoint:
                                            .leading,
                                        endPoint:
                                            .trailing
                                    )
                                )
                                .frame(
                                    width:
                                        proxy
                                            .size
                                            .width *
                                        trophy
                                            .progress
                                )
                        }
                    }
                    .frame(height: 8)
                }

                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            "\(Int((trophy.progress * 100).rounded()))%"
                        )
                        .font(
                            .title3.bold()
                        )

                        if let progressText =
                                trophy
                                    .concreteProgressText {
                            Text(
                                progressText
                            )
                            .font(
                                .caption
                                    .weight(
                                        .semibold
                                    )
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }

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
                        Text(
                            historyStageTitle(
                                unlock
                            )
                        )
                            .font(.subheadline.weight(.semibold))
                        Text(unlock.unlockedAt.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(
                        historyRarity(
                            unlock
                        )
                        .title
                    )
                        .font(.caption2.bold())
                        .foregroundStyle(unlock.category.trophyAccent)
                }
            }
        }
        .padding()
        .trophyDetailCard()
    }

    private func historyRarity(
        _ unlock:
            TrophyUnlockRecord
    ) -> TrophyRarity {
        if let definition =
                TrophyCatalog
                    .allSeries
                    .first(
                        where: {
                            $0.id ==
                                unlock
                                    .trophyID
                        }
                    ),
           let stage =
                definition
                    .stages
                    .first(
                        where: {
                            unlock
                                .stageKey ==
                            "\(definition.id).stage.\($0.id)"
                        }
                    ) {
            return stage.rarity
        }

        if let trophy,
           !trophy
                .isPrestigeTrophy,
           unlock
                .stageKey ==
                "\(trophy.id).unlocked" {
            return trophy
                .displayRarity
        }

        return unlock.rarity
    }

    private func historyStageTitle(
        _ unlock:
            TrophyUnlockRecord
    ) -> String {
        if let definition =
                TrophyCatalog
                    .allSeries
                    .first(
                        where: {
                            $0.id ==
                                unlock
                                    .trophyID
                        }
                    ),
           let stage =
                definition
                    .stages
                    .first(
                        where: {
                            unlock
                                .stageKey ==
                            "\(definition.id).stage.\($0.id)"
                        }
                    ) {
            return stage.title
        }

        if let trophy,
           !trophy
                .isPrestigeTrophy,
           unlock
                .stageKey ==
                "\(trophy.id).unlocked" {
            return trophy
                .stageLabel
        }

        return unlock.stageTitle
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

/// Quiet, collectible ATHLTH achievement moment. Native layouts keep the
/// earned medal, verification and accessibility correct for every award.
struct TrophyUnlockRevealView: View {
    @EnvironmentObject private var trophies: TrophyStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let unlock: TrophyUnlockRecord
    @State private var revealed = false
    @State private var inscription: TrophyInscription?

    private var trophy: TrophyProgressItem? {
        trophies.trophies.first { $0.id == unlock.trophyID }
    }

    private var metal: ATHLTHMedalMetal {
        ATHLTHMedalMetal(rarity: unlock.rarity)
    }

    private var accent: Color { metal.highlights[0] }

    private var athleteName: String {
        let username = session.profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return username }
        let display = session.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? "ATHLTH ATHLETE" : display
    }

    private var description: String {
        if unlock.trophyID == "strength.total-volume" {
            return ATHLTHLocalization.choose(
                english: "For consistent progress in strength training.",
                norwegian: "For konsekvent progresjon i styrketrening."
            )
        }
        switch unlock.category {
        case .strength:
            return ATHLTHLocalization.choose(english: "A new strength milestone.",
                                             norwegian: "En ny milepæl i styrketreningen.")
        case .consistency:
            return ATHLTHLocalization.choose(english: "For your commitment and progress.",
                                             norwegian: "For innsats og fremgang over tid.")
        case .walking, .endurance:
            return ATHLTHLocalization.choose(english: "For reaching a new milestone.",
                                             norwegian: "For en ny milepæl på veien videre.")
        case .recovery:
            return ATHLTHLocalization.choose(english: "For making recovery count.",
                                             norwegian: "For å prioritere restitusjonen.")
        case .goals:
            return ATHLTHLocalization.choose(english: "For reaching your next goal.",
                                             norwegian: "For å ha nådd et nytt mål.")
        case .challenges:
            return ATHLTHLocalization.choose(english: "For your challenge achievement.",
                                             norwegian: "For en prestasjon i en utfordring.")
        case .signature:
            return ATHLTHLocalization.choose(english: "An exceptional achievement.",
                                             norwegian: "En ekstraordinær prestasjon.")
        }
    }

    private var verification: String {
        if unlock.verificationSource == .athlth ||
           unlock.verificationSource == .mixed {
            return ATHLTHLocalization.choose(english: "Verified by ATHLTH",
                                             norwegian: "Verifisert av ATHLTH")
        }
        return ATHLTHLocalization.choose(
            english: "Verified via \(unlock.verificationSource.title)",
            norwegian: "Verifisert via \(unlock.verificationSource.title)"
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            let medalSize = min(proxy.size.width * (compact ? 0.55 : 0.65),
                                compact ? 214 : 278)

            ZStack {
                backdrop

                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        content(compact: compact, medalSize: medalSize)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: max(proxy.size.height - (compact ? 92 : 110), 0))
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)

                    Button {
                        trophies.dismissCurrentReveal()
                    } label: {
                        HStack(spacing: 15) {
                            Spacer()
                            Text(ATHLTHLocalization.choose(english: "Continue",
                                                           norwegian: "Fortsett"))
                                .font(.system(size: 17, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(Color(red: 0.12, green: 0.11, blue: 0.10))
                        .frame(maxWidth: .infinity, minHeight: compact ? 54 : 60)
                        .background(Color(red: 0.99, green: 0.98, blue: 0.96),
                                    in: Capsule())
                        .shadow(color: accent.opacity(0.13), radius: 17, y: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trophy-unlock-continue")
                    .padding(.horizontal, 28)
                    .padding(.top, compact ? 8 : 12)
                    .padding(.bottom, compact ? 10 : 16)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !reduceMotion && settings.achievementEffects != .off {
                withAnimation(.easeOut(duration: 0.6)) { revealed = true }
            } else {
                revealed = true
            }
            AchievementUnlockFeedback.play(
                rarity: unlock.rarity,
                soundEnabled: settings.achievementUnlockSoundsEnabled,
                hapticsEnabled: settings.achievementUnlockHapticsEnabled
            )
        }
        .task(id: unlock.stageKey) {
            guard unlock.isPrestigeTrophy, let trophy, trophy.isUnlocked else {
                inscription = nil
                return
            }
            if let cached = trophies.inscription(for: trophy.id) {
                inscription = cached
                return
            }
            let result = await TrophyInscriptionAIService.shared.inscription(
                trophyID: trophy.id, username: athleteName,
                achievementTitle: trophy.title, achievementDetail: trophy.subtitle,
                unlockedAt: unlock.unlockedAt
            )
            inscription = result.inscription
            if result.isPersisted {
                trophies.cacheInscription(result.inscription, for: trophy.id)
            }
        }
    }

    private func content(compact: Bool, medalSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                ATHLTHMarkShape()
                    .fill(accent.opacity(0.94))
                    .frame(width: 33, height: 25)
                Text("ATHLTH")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.90))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ATHLTH")
            .padding(.top, compact ? 14 : 28)

            Spacer(minLength: compact ? 12 : 26)

            VStack(spacing: 13) {
                Text(ATHLTHLocalization.choose(
                    english: unlock.isPrestigeTrophy
                        ? "NEW ATHLTH TROPHY" : "NEW ATHLTH ACHIEVEMENT",
                    norwegian: unlock.isPrestigeTrophy
                        ? "NY ATHLTH-POKAL" : "NY ATHLTH-UTMERKELSE"
                ))
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(accent.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Capsule().fill(accent.opacity(0.75))
                    .frame(width: 25, height: 1)
            }

            Spacer(minLength: compact ? 12 : 26)

            Group {
                if let trophy {
                    ATHLTHTrophyCoreView(
                        trophy: trophy,
                        size: medalSize,
                        revealRarity: unlock.rarity,
                        inscription: inscription,
                        athleteName: athleteName
                    )
                } else {
                    ATHLTHMintedBrandSeal(
                        size: medalSize,
                        metal: metal
                    )
                }
            }
            .shadow(color: accent.opacity(0.18), radius: 26, y: 8)
            .scaleEffect(revealed ? 1 : 0.97)
            .opacity(revealed ? 1 : 0)
            .accessibilityIdentifier("trophy-unlock-artwork")

            Spacer(minLength: compact ? 16 : 23)

            VStack(spacing: compact ? 8 : 11) {
                Text(unlock.title)
                    .font(.system(size: compact ? 28 : 36, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .accessibilityAddTraits(.isHeader)

                Text(unlock.stageTitle.uppercased())
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .tracking(4.3)
                    .foregroundStyle(accent)

                Capsule().fill(.white.opacity(0.20))
                    .frame(width: 34, height: 1)
                    .padding(.top, compact ? 2 : 7)

                Text(description)
                    .font(.system(size: compact ? 13 : 15))
                    .foregroundStyle(.white.opacity(0.69))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: compact ? 14 : 25)

            HStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: compact ? 22 : 25))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(verification)
                        .font(.system(size: compact ? 13 : 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.89))
                    Text(unlock.unlockedAt.formatted(
                        .dateTime.day().month(.wide).year()
                    ))
                        .font(.system(size: compact ? 12 : 13))
                        .foregroundStyle(.white.opacity(0.54))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: compact ? 65 : 75)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(reduceTransparency ? 0.11 : 0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: compact ? 8 : 16)
        }
        .padding(.horizontal, 16)
    }

    private var backdrop: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.094, green: 0.084, blue: 0.078),
                        Color(red: 0.071, green: 0.065, blue: 0.061),
                        Color(red: 0.02, green: 0.022, blue: 0.026)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if !reduceTransparency {
                    RadialGradient(
                        colors: [accent.opacity(0.18),
                                 accent.opacity(0.045), .clear],
                        center: .center,
                        startRadius: 12,
                        endRadius: proxy.size.width * 0.66
                    )
                    .frame(width: proxy.size.width * 1.35,
                           height: proxy.size.width * 1.4)
                    .offset(y: -proxy.size.height * 0.10)

                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, accent.opacity(0.24),
                                     accent.opacity(0.09), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: proxy.size.width * 1.6, height: 92)
                        .blur(radius: 35)
                        .rotationEffect(.degrees(24))
                        .offset(y: -proxy.size.height * 0.16)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.09),
                             .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

enum TrophyCollectionFilter: Hashable, Identifiable, CaseIterable {
    case all
    case category(TrophyCategory)

    static var allCases: [TrophyCollectionFilter] {
        [.all] +
        TrophyCategory
            .allCases
            .filter {
                $0 != .signature
            }
            .map {
                .category($0)
            }
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
            return ATHLTHTheme
                .premiumGold

        case .walking,
             .endurance,
             .strength,
             .consistency,
             .goals,
             .recovery,
             .challenges:
            return Color(
                red: 0.24,
                green: 0.27,
                blue: 0.30
            )
        }
    }

    var trophyGradient: [Color] {
        switch self {
        case .signature:
            return [
                Color(
                    red: 0.16,
                    green: 0.14,
                    blue: 0.10
                ),
                ATHLTHTheme
                    .premiumGold,
                Color(
                    red: 0.055,
                    green: 0.055,
                    blue: 0.06
                )
            ]

        case .walking,
             .endurance,
             .strength,
             .consistency,
             .goals,
             .recovery,
             .challenges:
            return [
                Color(
                    red: 0.25,
                    green: 0.28,
                    blue: 0.31
                ),
                Color(
                    red: 0.13,
                    green: 0.145,
                    blue: 0.16
                ),
                Color(
                    red: 0.055,
                    green: 0.06,
                    blue: 0.065
                )
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
