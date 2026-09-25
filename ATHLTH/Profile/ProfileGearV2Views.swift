import SwiftUI

struct RunningShoeIcon: View {
    var color: Color = ATHLTHTheme.accentDeep

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                Path { path in
                    path.move(
                        to: CGPoint(
                            x: w * 0.10,
                            y: h * 0.64
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w * 0.35,
                            y: h * 0.39
                        ),
                        control1: CGPoint(
                            x: w * 0.16,
                            y: h * 0.61
                        ),
                        control2: CGPoint(
                            x: w * 0.23,
                            y: h * 0.43
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w * 0.57,
                            y: h * 0.53
                        ),
                        control1: CGPoint(
                            x: w * 0.43,
                            y: h * 0.37
                        ),
                        control2: CGPoint(
                            x: w * 0.46,
                            y: h * 0.50
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w * 0.91,
                            y: h * 0.66
                        ),
                        control1: CGPoint(
                            x: w * 0.68,
                            y: h * 0.57
                        ),
                        control2: CGPoint(
                            x: w * 0.82,
                            y: h * 0.58
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w * 0.87,
                            y: h * 0.79
                        ),
                        control1: CGPoint(
                            x: w * 0.96,
                            y: h * 0.70
                        ),
                        control2: CGPoint(
                            x: w * 0.94,
                            y: h * 0.77
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: w * 0.18,
                            y: h * 0.79
                        )
                    )
                    path.addCurve(
                        to: CGPoint(
                            x: w * 0.10,
                            y: h * 0.64
                        ),
                        control1: CGPoint(
                            x: w * 0.11,
                            y: h * 0.78
                        ),
                        control2: CGPoint(
                            x: w * 0.07,
                            y: h * 0.72
                        )
                    )
                    path.closeSubpath()
                }
                .fill(color)

                Path { path in
                    path.move(
                        to: CGPoint(
                            x: w * 0.27,
                            y: h * 0.58
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: w * 0.52,
                            y: h * 0.61
                        )
                    )
                    path.move(
                        to: CGPoint(
                            x: w * 0.34,
                            y: h * 0.51
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: w * 0.55,
                            y: h * 0.55
                        )
                    )
                    path.move(
                        to: CGPoint(
                            x: w * 0.18,
                            y: h * 0.73
                        )
                    )
                    path.addLine(
                        to: CGPoint(
                            x: w * 0.87,
                            y: h * 0.73
                        )
                    )
                }
                .stroke(
                    Color.white.opacity(0.75),
                    style: StrokeStyle(
                        lineWidth: max(1.2, w * 0.045),
                        lineCap: .round
                    )
                )
            }
        }
        .aspectRatio(1.35, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ProfileGearCategoryIcon: View {
    let category: ProfileGearCategory
    var size: CGFloat = 22
    var color: Color = ATHLTHTheme.accentDeep

    var body: some View {
        Group {
            if category == .shoes {
                RunningShoeIcon(color: color)
                    .frame(
                        width: size * 1.18,
                        height: size
                    )
            } else {
                Image(systemName: category.systemImage)
                    .font(
                        .system(
                            size: size,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(color)
            }
        }
        .frame(width: size * 1.35, height: size * 1.35)
    }
}

struct WorkoutGearSelectionCard: View {
    @EnvironmentObject private var gear: ProfileGearStore

    @Binding var selectedGearIDs: Set<UUID>
    let activity: WorkoutActivity

    private var eligibleItems: [ProfileGearItem] {
        gear.activeItems(for: activity)
    }

    private var shoes: [ProfileGearItem] {
        eligibleItems.filter { $0.category == .shoes }
    }

    private var otherGear: [ProfileGearItem] {
        eligibleItems.filter { $0.category != .shoes }
    }

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gear")
                        .font(.headline)

                    Text(
                        activity == .running
                            ? "Choose your running shoes and anything else you used."
                            : "Add the equipment used for this workout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ProfileGearManagerView()
                } label: {
                    Text("Manage")
                        .font(.caption.weight(.semibold))
                }
            }

            if eligibleItems.isEmpty {
                NavigationLink {
                    ProfileGearManagerView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your first gear")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(
                                "Shoes and other equipment can be linked to workouts."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 10)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 9) {
                    if !shoes.isEmpty {
                        gearSectionLabel(
                            "RUNNING SHOES",
                            detail: "One pair per workout"
                        )

                        ForEach(shoes) { item in
                            selectionRow(item)
                        }
                    }

                    if !otherGear.isEmpty {
                        if !shoes.isEmpty {
                            Divider()
                                .padding(.vertical, 3)
                        }

                        gearSectionLabel(
                            "OTHER GEAR",
                            detail: "Select any that you used"
                        )

                        ForEach(otherGear) { item in
                            selectionRow(item)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .task {
            if gear.items.isEmpty {
                await gear.refresh()
            }
        }
    }

    private func gearSectionLabel(
        _ title: String,
        detail: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(ATHLTHTheme.mutedText)

            Spacer()

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionRow(
        _ item: ProfileGearItem
    ) -> some View {
        let selected = selectedGearIDs.contains(item.id)
        let detail = gear.details(for: item)
        let stats = gear.usageStats(for: item)

        return Button {
            toggle(item)
        } label: {
            HStack(spacing: 11) {
                gearThumb(item)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if detail?.isDefaultForRunning == true {
                            Text("DEFAULT")
                                .font(
                                    .system(
                                        size: 8,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Capsule()
                                )
                        }
                    }

                    Text(
                        gearSubtitle(
                            item,
                            detail: detail,
                            stats: stats
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Image(
                    systemName:
                        selected
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .font(.title3)
                .foregroundStyle(
                    selected
                        ? ATHLTHTheme.accent
                        : Color.secondary.opacity(0.55)
                )
            }
            .padding(10)
            .background(
                selected
                    ? ATHLTHTheme.accentSoft.opacity(0.50)
                    : Color.primary.opacity(0.025),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gearThumb(
        _ item: ProfileGearItem
    ) -> some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 11,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.04))

            if let imageURL = item.imageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                    default:
                        ProfileGearCategoryIcon(
                            category: item.category,
                            size: 18
                        )
                    }
                }
            } else {
                ProfileGearCategoryIcon(
                    category: item.category,
                    size: 18
                )
            }
        }
        .frame(width: 42, height: 42)
    }

    private func toggle(
        _ item: ProfileGearItem
    ) {
        if selectedGearIDs.contains(item.id) {
            selectedGearIDs.remove(item.id)
            return
        }

        if item.category == .shoes {
            let shoeIDs = Set(shoes.map(\.id))
            selectedGearIDs.subtract(shoeIDs)
        }

        selectedGearIDs.insert(item.id)
    }

    private func gearSubtitle(
        _ item: ProfileGearItem,
        detail: ProfileGearDetailRecord?,
        stats: ProfileGearUsageStats
    ) -> String {
        var parts: [String] = []

        if let brand = detail?.brand,
           !brand.isEmpty {
            parts.append(brand)
        }

        if item.category == .shoes {
            if let type = detail?.shoeUseType {
                parts.append(type.title)
            }

            if stats.totalDistanceMeters > 0 {
                parts.append(
                    String(
                        format: "%.0f km",
                        stats.totalDistanceMeters / 1_000
                    )
                )
            }
        } else if stats.workoutCount > 0 {
            parts.append(
                "\(stats.workoutCount) workout\(stats.workoutCount == 1 ? "" : "s")"
            )
        }

        return parts.isEmpty
            ? item.category.shortTitle
            : parts.joined(separator: " · ")
    }
}

struct ProfileGearDetailView: View {
    @EnvironmentObject private var gear: ProfileGearStore

    let item: ProfileGearItem

    @State private var showingEdit = false

    private var currentItem: ProfileGearItem {
        gear.items.first(where: { $0.id == item.id }) ?? item
    }

    private var detail: ProfileGearDetailRecord? {
        gear.details(for: currentItem)
    }

    private var stats: ProfileGearUsageStats {
        gear.usageStats(for: currentItem)
    }

    private var history: [WorkoutGearUsageRecord] {
        gear.usage(for: currentItem)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                hero
                usageCard

                if currentItem.category == .shoes,
                   !history.isEmpty {
                    shoeInsightsCard
                }

                detailsCard
                historyCard
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent:
                    currentItem.category == .shoes
                        ? ATHLTHTheme.vitality.opacity(0.30)
                        : ATHLTHTheme.premiumGold.opacity(0.25)
            )
        )
        .navigationTitle(currentItem.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ProfileGearEditorView(
                    category: currentItem.category,
                    existing: currentItem
                )
            }
            .environmentObject(gear)
        }
        .task {
            await gear.refresh()
        }
    }

    private var hero: some View {
        ATHLTHCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .fill(
                        ATHLTHTheme.surfaceSage.opacity(0.62)
                    )

                    if let value = currentItem.imageURL,
                       let url = URL(string: value) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                            default:
                                ProfileGearCategoryIcon(
                                    category: currentItem.category,
                                    size: 36
                                )
                            }
                        }
                    } else {
                        ProfileGearCategoryIcon(
                            category: currentItem.category,
                            size: 36
                        )
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(currentItem.name)
                            .font(.title3.weight(.bold))

                        if detail?.status == .retired {
                            statusBadge(
                                "RETIRED",
                                tint: .secondary
                            )
                        } else if detail?.isDefaultForRunning == true {
                            statusBadge(
                                "DEFAULT",
                                tint: ATHLTHTheme.accentDeep
                            )
                        }
                    }

                    if let subtitle = itemSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if currentItem.isFeatured {
                        Label(
                            "Shown on profile",
                            systemImage: "star.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                    }
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var usageCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        currentItem.category == .shoes
                            ? "Shoe Usage"
                            : "Usage"
                    )
                    .font(.title3.weight(.bold))

                    Text(
                        currentItem.category == .shoes
                            ? "Automatically calculated from linked workouts."
                            : "Workouts where this gear was selected."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                ProfileGearCategoryIcon(
                    category: currentItem.category,
                    size: 20
                )
            }

            HStack(spacing: 8) {
                usageMetric(
                    title: "Workouts",
                    value: "\(stats.workoutCount)"
                )

                usageMetric(
                    title: "Time",
                    value: compactDuration(
                        stats.totalDuration
                    )
                )

                if currentItem.category == .shoes {
                    usageMetric(
                        title: "Distance",
                        value: String(
                            format: "%.0f km",
                            stats.totalDistanceMeters / 1_000
                        )
                    )
                }
            }
            .padding(.top, 12)

            if currentItem.category == .shoes,
               let target = detail?.replacementTargetKM,
               target > 0 {
                let usedKM = stats.totalDistanceMeters / 1_000
                let progress = min(max(usedKM / target, 0), 1)

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Replacement target")
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Text(
                            String(
                                format: "%.0f / %.0f km",
                                usedKM,
                                target
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    ProgressView(value: progress)
                        .tint(
                            progress >= 0.90
                                ? .orange
                                : ATHLTHTheme.accent
                        )

                    if progress >= 0.80 {
                        Label(
                            replacementMessage(progress),
                            systemImage:
                                progress >= 1
                                    ? "exclamationmark.circle.fill"
                                    : "shoeprints.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            progress >= 1
                                ? Color.orange
                                : ATHLTHTheme.accentDeep
                        )
                    } else {
                        Text(replacementMessage(progress))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 14)
            }

            if let lastUsed = stats.lastUsedAt {
                HStack {
                    Label(
                        "Last used",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Text(
                        lastUsed.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                    .font(.caption.weight(.semibold))
                }
                .padding(.top, 12)
            }
        }
    }

    private var shoeInsightsCard: some View {
        let distances = history.compactMap(\.distanceMeters)
        let longest = distances.max() ?? 0
        let average =
            distances.isEmpty
                ? 0
                : distances.reduce(0, +) /
                    Double(distances.count)
        let threshold = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: Date()
        ) ?? .distantPast
        let last30 = history
            .filter { $0.startedAt >= threshold }
            .compactMap(\.distanceMeters)
            .reduce(0, +)

        return ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Shoe Insights")
                        .font(.title3.weight(.bold))
                    Text(
                        "Based only on workouts linked to this pair."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                RunningShoeIcon(
                    color: ATHLTHTheme.accentDeep
                )
                .frame(width: 34, height: 26)
            }

            HStack(spacing: 8) {
                usageMetric(
                    title: "Longest",
                    value: String(
                        format: "%.1f km",
                        longest / 1_000
                    )
                )

                usageMetric(
                    title: "Avg workout",
                    value: String(
                        format: "%.1f km",
                        average / 1_000
                    )
                )

                usageMetric(
                    title: "Last 30d",
                    value: String(
                        format: "%.0f km",
                        last30 / 1_000
                    )
                )
            }
            .padding(.top, 12)
        }
    }

    private var detailsCard: some View {
        ATHLTHCard {
            Text("Details")
                .font(.title3.weight(.bold))

            VStack(spacing: 10) {
                if let brand = detail?.brand {
                    detailRow("Brand", brand)
                }

                if let model = detail?.model {
                    detailRow("Model", model)
                }

                if let color = detail?.colorName {
                    detailRow("Color", color)
                }

                if currentItem.category == .shoes {
                    if let size = detail?.sizeLabel {
                        detailRow("Size", size)
                    }

                    if let use = detail?.shoeUseType {
                        detailRow("Rotation", use.title)
                    }

                    if let purchased = detail?.purchasedDate {
                        detailRow(
                            "Purchased",
                            purchased.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                    }

                    if let first =
                        detail?.firstUsedDate ??
                        stats.firstUsedAt {
                        detailRow(
                            "First used",
                            first.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                    }
                } else if let type = detail?.gearTypeLabel {
                    detailRow("Type", type)
                }

                detailRow(
                    "Status",
                    detail?.status.title ?? "Active"
                )

                if let notes = detail?.notes,
                   !notes.isEmpty {
                    Divider()
                    Text(notes)
                        .font(.subheadline)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                }

                if detail == nil {
                    Text(
                        "Edit this item to add brand, color and more details."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }
            }
            .padding(.top, 10)
        }
    }

    private var historyCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workout History")
                        .font(.title3.weight(.bold))
                    Text(
                        "Usage is linked to the actual completed workout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(history.count)")
                    .font(.headline.monospacedDigit())
            }

            if history.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text(
                        "No workouts are linked to this gear yet."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(history.prefix(20)) { record in
                        HStack(spacing: 11) {
                            Image(
                                systemName: workoutIcon(
                                    record.activityType
                                )
                            )
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 34, height: 34)
                            .background(
                                ATHLTHTheme.accentSoft,
                                in: RoundedRectangle(
                                    cornerRadius: 10
                                )
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.workoutTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)

                                Text(
                                    record.startedAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                if currentItem.category == .shoes,
                                   let meters = record.distanceMeters,
                                   meters > 0 {
                                    Text(
                                        String(
                                            format: "%.2f km",
                                            meters / 1_000
                                        )
                                    )
                                    .font(.caption.weight(.semibold))
                                }

                                Text(
                                    compactDuration(
                                        record.durationSeconds
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)

                        if record.id != history.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var itemSubtitle: String? {
        var parts: [String] = []

        if let brand = detail?.brand {
            parts.append(brand)
        }

        if let model = detail?.model {
            parts.append(model)
        }

        if currentItem.category == .shoes,
           let use = detail?.shoeUseType {
            parts.append(use.title)
        }

        if currentItem.category == .other,
           let type = detail?.gearTypeLabel {
            parts.append(type)
        }

        return parts.isEmpty
            ? currentItem.category.title
            : parts.joined(separator: " · ")
    }

    private func statusBadge(
        _ title: String,
        tint: Color
    ) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                tint.opacity(0.10),
                in: Capsule()
            )
    }

    private func usageMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )
        )
    }

    private func detailRow(
        _ title: String,
        _ value: String
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func replacementMessage(
        _ progress: Double
    ) -> String {
        if progress >= 1 {
            return "You have reached your own replacement target."
        }

        if progress >= 0.90 {
            return "Approaching your replacement target."
        }

        if progress >= 0.80 {
            return "Keep an eye on wear as you approach your target."
        }

        return "Your target is personal — replace shoes based on condition and comfort."
    }

    private func workoutIcon(
        _ activity: String
    ) -> String {
        switch activity.lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "strength": return "dumbbell.fill"
        case "cycling": return "figure.outdoor.cycle"
        default: return "figure.mixed.cardio"
        }
    }

    private func compactDuration(
        _ seconds: TimeInterval
    ) -> String {
        let minutes = max(Int((seconds / 60).rounded()), 0)

        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0
                ? "\(hours)h"
                : "\(hours)h \(remainder)m"
        }

        return "\(minutes)m"
    }
}
