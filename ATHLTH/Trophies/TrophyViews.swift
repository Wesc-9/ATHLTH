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

struct ATHLTHTrophyCoreView: View {
    let trophy: TrophyProgressItem
    var size: CGFloat = 112
    var showLabel = false

    private var unlockedSegments: Int {
        if trophy.isComplete { return 5 }
        if trophy.currentStage != nil {
            return min(4, max(2, Int((trophy.progress * 3).rounded()) + 2))
        }
        return max(1, Int((trophy.progress * 4).rounded()))
    }

    var body: some View {
        VStack(spacing: showLabel ? 8 : 0) {
            ZStack {
                ATHLTHTrophyPlateShape()
                    .fill(
                        LinearGradient(
                            colors: trophy.isUnlocked
                                ? trophy.category.trophyGradient
                                : [
                                    Color(.systemGray5),
                                    Color(.systemGray4)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        ATHLTHTrophyPlateShape()
                            .stroke(
                                trophy.isUnlocked
                                    ? Color.white.opacity(0.52)
                                    : Color.secondary.opacity(0.18),
                                lineWidth: 1.2
                            )
                    }
                    .shadow(
                        color: trophy.isUnlocked
                            ? trophy.category.trophyAccent.opacity(0.22)
                            : .clear,
                        radius: 16,
                        x: 0,
                        y: 8
                    )

                ATHLTHTrophyPlateShape()
                    .fill(.black.opacity(trophy.isUnlocked ? 0.14 : 0.04))
                    .padding(size * 0.09)

                VStack(spacing: size * 0.055) {
                    Text(trophy.displayRarity.title.uppercased())
                        .font(.system(size: max(6, size * 0.065), weight: .bold))
                        .tracking(size * 0.012)
                        .foregroundStyle(.white.opacity(trophy.isUnlocked ? 0.78 : 0.45))

                    ZStack {
                        ATHLTHMarkShape()
                            .fill(
                                trophy.isUnlocked
                                    ? Color.white
                                    : Color.secondary.opacity(0.42)
                            )
                            .frame(
                                width: size * 0.35,
                                height: size * 0.25
                            )
                            .shadow(
                                color: trophy.isUnlocked
                                    ? Color.white.opacity(0.22)
                                    : .clear,
                                radius: 7
                            )

                        if !trophy.isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: size * 0.11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.88))
                                .offset(y: size * 0.27)
                        }
                    }

                    HStack(spacing: size * 0.025) {
                        ForEach(0..<5, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index < unlockedSegments
                                        ? Color.white.opacity(trophy.isUnlocked ? 0.9 : 0.42)
                                        : Color.white.opacity(0.18)
                                )
                                .frame(
                                    width: size * 0.075,
                                    height: size * 0.018
                                )
                        }
                    }

                    Image(systemName: trophy.category.systemImage)
                        .font(.system(size: size * 0.09, weight: .semibold))
                        .foregroundStyle(.white.opacity(trophy.isUnlocked ? 0.78 : 0.34))
                }
                .padding(.top, size * 0.015)
            }
            .frame(width: size, height: size * 1.12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                trophy.isUnlocked
                    ? "\(trophy.title), \(trophy.stageLabel), unlocked"
                    : "\(trophy.title), locked"
            )

            if showLabel {
                VStack(spacing: 2) {
                    Text(trophy.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(trophy.stageLabel)
                        .font(.caption2)
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
                    Text("Trophy Cabinet")
                        .font(.title3.weight(.bold))
                    Text("The achievements you choose to display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    TrophyCollectionView()
                } label: {
                    Text("View Collection")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
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
                        .foregroundStyle(.green)
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
                        .foregroundStyle(.green)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.055))
                        Capsule()
                            .fill(.green)
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

        return "Next · \(next.displayTarget)"
    }
}

struct TrophyCollectionView: View {
    @EnvironmentObject private var trophies: TrophyStore
    @State private var filter: TrophyCollectionFilter = .all

    private var filtered: [TrophyProgressItem] {
        switch filter {
        case .all:
            return trophies.trophies
        case .category(let category):
            return trophies.trophies.filter { $0.category == category }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                collectionHero
                filters

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(filtered) { trophy in
                        NavigationLink {
                            TrophyDetailView(trophyID: trophy.id)
                        } label: {
                            collectionCard(trophy)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Trophies")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var collectionHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    ATHLTHTrophyPlateShape()
                        .fill(
                            LinearGradient(
                                colors: [.black, .green.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    ATHLTHMarkShape()
                        .fill(.white)
                        .frame(width: 40, height: 30)
                }
                .frame(width: 76, height: 86)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ATHLTH TROPHY COLLECTION")
                        .font(.caption2.bold())
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    Text("\(trophies.unlockedCount) unlocked")
                        .font(.title2.bold())

                    Text("Your Core evolves with the work behind it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("Trophies are verified from Apple Health, ATHLTH training or completed Goals. They are not a copy of Activity awards: each series develops instead of creating endless duplicate medals.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TrophyCollectionFilter.allCases) { option in
                    Button {
                        withAnimation(.snappy) {
                            filter = option
                        }
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(filter == option ? .white : .primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                filter == option
                                    ? Color.green
                                    : Color(.secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func collectionCard(_ trophy: TrophyProgressItem) -> some View {
        VStack(spacing: 10) {
            ATHLTHTrophyCoreView(trophy: trophy, size: 92)

            VStack(spacing: 3) {
                Text(trophy.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(trophy.stageLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(trophy.isUnlocked ? .green : .secondary)

                Label(
                    trophy.verificationSource.title,
                    systemImage: trophy.verificationSource.systemImage
                )
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }

            if !trophy.isComplete {
                ProgressView(value: trophy.progress)
                    .tint(.green)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
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

struct TrophyDetailView: View {
    @EnvironmentObject private var trophies: TrophyStore

    let trophyID: String

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
                                    .foregroundStyle(.green)

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
                                        ? "Remove from Trophy Cabinet"
                                        : "Show in Trophy Cabinet",
                                    systemImage: trophies.isShowcased(trophy.id)
                                        ? "rectangle.stack.badge.minus"
                                        : "rectangle.stack.badge.plus"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(trophies.isShowcased(trophy.id) ? .secondary : .green)
                            .disabled(
                                !trophies.isShowcased(trophy.id) &&
                                trophies.showcaseIDs.count >= 5
                            )

                            if !trophies.isShowcased(trophy.id) &&
                               trophies.showcaseIDs.count >= 5 {
                                Text("Your cabinet can display up to five trophies.")
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
                    .foregroundStyle(.green)
                }
            } else {
                ProgressView(value: trophy.progress)
                    .tint(.green)

                HStack {
                    Text("\(Int((trophy.progress * 100).rounded()))%")
                        .font(.title3.bold())

                    Spacer()

                    if let next = trophy.nextStage {
                        Text("Next · \(next.displayTarget)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let completed = trophy.journeyMilestonesCompleted,
               let total = trophy.journeyMilestonesTotal {
                Divider()

                HStack {
                    Label("\(completed) milestones", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("\(total) total")
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
            .foregroundStyle(.green)

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
                        "ATHLTH · \(unlock.verificationSource.title.uppercased())",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption.bold())
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.66))
                    .padding(.top, 6)
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
        case .all: return "All"
        case .category(let category): return category.title
        }
    }
}

private extension TrophyCategory {
    var trophyAccent: Color {
        switch self {
        case .signature:
            return Color(red: 0.92, green: 0.72, blue: 0.26)
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
