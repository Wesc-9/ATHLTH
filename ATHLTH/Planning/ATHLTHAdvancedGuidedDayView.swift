import SwiftUI

/// Local, draft-scoped drag identity. Never accepts a foreign plan's payload.
struct ATHLTHPlanDragPayload {
    let dateKey: Int
    let workout: Int
    let block: UUID?

    static func encode(scope: String, key: Int, workout: Int, block: UUID? = nil) -> String {
        "\(scope)|\(key)|\(workout)|\(block?.uuidString ?? "-")"
    }

    static func decode(_ value: String, scope: String) -> Self? {
        let fields = value.split(separator: "|")
        guard fields.count == 4, fields[0] == scope,
              let key = Int(fields[1]), let workout = Int(fields[2]), workout >= 0 else { return nil }
        let block = UUID(uuidString: String(fields[3]))
        guard fields[3] == "-" || block != nil else { return nil }
        return Self(dateKey: key, workout: workout, block: block)
    }
}

/// New presentation for the existing dated ATHLTHPlanWeekDayEdit engine.
/// Never owns a separate draft: every action updates the parent wizard.
struct ATHLTHAdvancedGuidedDayView: View {
    @Environment(\.horizontalSizeClass) private var widthClass
    let date: Date
    let weekNumber: Int
    let totalWeeks: Int
    let dayIndex: Int
    let startDate: Date
    let workouts: [ATHLTHPlanStructuredWorkoutBlueprint]
    let isRestDay: Bool
    var suggestedTraining: Bool? = nil
    var pinsDayActions = false
    var dragScope = ""
    var dateKey = 0
    var onDropItem: (String, Int?, WorkoutPhaseKind?, UUID?) -> Bool = { _, _, _, _ in false }
    var onDeleteBlock: (Int, UUID) -> Void = { _, _ in }
    var onClearDay: () -> Void = {}
    let onSelectDay: (Int) -> Void
    let onAddExercise: (WorkoutPhaseKind, Int) -> Void
    let onAddWorkout: () -> Void
    let onQuick: (String) -> Void
    let onEditWorkout: (Int) -> Void
    let onEditBlock: (Int, Int) -> Void
    let onDeleteWorkout: (Int) -> Void
    let onCoachFill: () -> Void
    let onRestDay: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmingRestReplacement = false
    @State private var pendingWorkoutDeletion: Int?
    @State private var confirmingWorkoutDeletion = false
    @State private var showingDayPicker = false
    @State private var pendingBlockDeletion: (Int, UUID)?
    @State private var confirmingBlockDeletion = false
    private let ink = ATHLTHTrainDesign.ink
    private let secondary = ATHLTHTrainDesign.secondary
    private let gold = ATHLTHTrainDesign.bronze
    private let canvas = ATHLTHTrainDesign.canvas
    private let rule = ATHLTHTrainDesign.rule

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        Group {
            if pinsDayActions {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView {
                        dayContent
                            .padding(.bottom, 4)
                    }
                    .scrollIndicators(.hidden)
                    if !isRestDay {
                        Divider().opacity(0.4)
                        AnyView(dayActions)
                            .padding(.vertical, 4)
                            .background(canvas)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    dayContent
                    if !isRestDay { AnyView(dayActions) }
                }
            }
        }
        .frame(maxWidth: widthClass == .regular ? .infinity : ATHLTHPlanDesign.maxContentWidth)
        .confirmationDialog(
            tr("Delete workout?", "Slette treningsøkt?"),
            isPresented: $confirmingWorkoutDeletion,
            titleVisibility: .visible
        ) {
            Button(tr("Delete workout", "Slett treningsøkt"), role: .destructive) {
                guard let pendingWorkoutDeletion else { return }
                onDeleteWorkout(pendingWorkoutDeletion)
                self.pendingWorkoutDeletion = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingWorkoutDeletion = nil
            }
        } message: {
            Text(tr("Only this workout will be removed from the day.",
                    "Kun denne treningsøkten fjernes fra dagen."))
        }
        .alert(tr("Delete step or linked group?", "Slette deløkten eller tilhørende gruppe?"),
               isPresented: $confirmingBlockDeletion) {
            Button(tr("Delete", "Slett"), role: .destructive) {
                if let item = pendingBlockDeletion { onDeleteBlock(item.0, item.1) }
                pendingBlockDeletion = nil
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) { pendingBlockDeletion = nil }
        }
        .confirmationDialog(
            tr("Replace workouts with a rest day?", "Erstatte øktene med en hviledag?"),
            isPresented: $confirmingRestReplacement, titleVisibility: .visible
        ) {
            Button(tr("Replace with rest day", "Erstatt med hviledag"),
                   role: .destructive, action: onRestDay)
        } message: {
            Text(tr("The planned workouts for this date will be removed.",
                    "Planlagte økter på denne datoen blir fjernet."))
        }
    }

    private var dayContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if pinsDayActions { dayDetails }
            if isRestDay || !workouts.isEmpty {
                HStack {
                    Spacer()
                    Button(role: .destructive, action: onClearDay) {
                        Label(tr("Clear day", "Slett planlegging for dagen"), systemImage: "trash")
                            .font(.caption.weight(.medium))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(secondary)
                }
            }
            if isRestDay {
                restDayCard
            } else if workouts.isEmpty {
                emptyDayCard
            } else {
                ForEach(Array(workouts.enumerated()), id: \.offset) { pair in
                    workoutCard(pair.element, index: pair.offset)
                }
            }
        }
    }

    private var dayDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("Workout details", "Øktdetaljer"), systemImage: "list.bullet.rectangle")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            HStack(alignment: .top, spacing: 12) {
                detailMetric(tr("Workouts", "Økter"), value: String(workouts.count), symbol: "calendar")
                detailMetric(tr("Duration", "Varighet"),
                             value: workouts.isEmpty ? "–" : "\(workouts.reduce(0) { $0 + $1.durationMinutes }) min",
                             symbol: "clock")
                detailMetric(tr("Day type", "Dagtype"),
                             value: isRestDay ? tr("Rest", "Hvile") :
                                !workouts.isEmpty ? tr("Training", "Trening") :
                                suggestedTraining == true ? tr("Suggested training", "Foreslått trening") :
                                suggestedTraining == false ? tr("Suggested rest", "Foreslått hvile") : "–",
                             symbol: isRestDay || (workouts.isEmpty && suggestedTraining == false) ? "moon.stars" : "figure.run")
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .strokeBorder(rule.opacity(0.38), lineWidth: 0.7)
        }
    }

    private func detailMetric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayActions: some View {
        VStack(spacing: 8) {
            restDayAction
            quickActions
            if pinsDayActions {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { mainActions }
                    VStack(spacing: 8) { mainActions }
                }
            } else {
                VStack(spacing: 8) { mainActions }
            }
        }
    }

    @ViewBuilder
    private var mainActions: some View {
        goldAction(tr("Add exercise", "Legg til øvelse"), symbol: "dumbbell") {
            onQuick("exercise")
        }
        goldAction(tr("Add workout", "Legg til treningsøkt"), symbol: "plus") {
            onAddWorkout()
        }
        goldAction(tr("Ask ATHLTH Coach to fill empty days", "Be ATHLTH Coach fylle ut"), symbol: "sparkles") {
            onCoachFill()
        }
    }

    private var restDayAction: some View {
        Button {
            if workouts.isEmpty { onRestDay() }
            else { confirmingRestReplacement = true }
        } label: {
            Label(tr("Set as rest day", "Sett som hviledag"), systemImage: "moon.stars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(gold)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(gold.opacity(0.35), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                Image("PlanGoalHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.96), location: 0.34),
                    .init(color: canvas.opacity(0.58), location: 0.68),
                    .init(color: canvas.opacity(0.05), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(tr("WEEK", "UKE") + " \(weekNumber)")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(secondary)
                    Spacer()
                    Button {
                        showingDayPicker = true
                    } label: {
                        Label(tr("Change day", "Skift dag"), systemImage: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(.white.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingDayPicker, arrowEdge: .top) {
                        allPlanDaysPicker
                            .presentationCompactAdaptation(.popover)
                    }
                }
                Text(date.formatted(.dateTime.weekday(.wide)).capitalized)
                    .font(.system(size: typeSize.isAccessibilitySize ? 28 : 35,
                                  weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(date.formatted(.dateTime.day().month(.wide)))
                    .font(.subheadline).foregroundStyle(secondary)
            }
            .padding(9)
        }
        .frame(height: typeSize.isAccessibilitySize ? 155 : 128)
        .clipped()
    }

    /// One continuous scrollable list of *every* date in the plan.
    /// Week labels are visual dividers only, never navigation or submenus.
    /// A 4-week plan contains 28 individual date buttons in the same list.
    private var allPlanDaysPicker: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(0..<max(1, totalWeeks), id: \.self) { week in
                        Text(tr("WEEK", "UKE") + " \(week + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(secondary)
                            .padding(.horizontal, 18)
                            .padding(.top, week == 0 ? 15 : 19)
                            .padding(.bottom, 6)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(0..<7, id: \.self) { weekday in
                            let absoluteDay = week * 7 + weekday
                            let isSelected = absoluteDay == (weekNumber - 1) * 7 + dayIndex

                            Button {
                                onSelectDay(absoluteDay)
                                showingDayPicker = false
                            } label: {
                                HStack(spacing: 10) {
                                    Text(dayDate(absoluteDay).formatted(
                                        .dateTime.weekday(.wide).day().month()
                                    ))
                                        .font(.system(size: 16))
                                        .foregroundStyle(ink)
                                    Spacer(minLength: 8)
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(gold)
                                    }
                                }
                                .frame(minHeight: 48)
                                .padding(.horizontal, 18)
                                .contentShape(Rectangle())
                                .background(isSelected ? gold.opacity(0.10) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .id(absoluteDay)
                        }

                        if week < max(1, totalWeeks) - 1 {
                            Divider()
                                .padding(.horizontal, 18)
                        }
                    }
                }
            }
            .frame(width: 330, height: 460)
            .background(canvas)
            .onAppear {
                // Keep the currently selected date near the visible portion,
                // but all earlier/later weeks remain in this *same* list.
                let selected = (weekNumber - 1) * 7 + dayIndex
                scrollProxy.scrollTo(selected, anchor: .center)
            }
        }
    }

    private func dayDate(_ absoluteDay: Int) -> Date {
        Calendar.current.date(byAdding: .day,
            value: absoluteDay,
            to: Calendar.current.startOfDay(for: startDate)) ?? date
    }

    private var emptyDayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("No workouts planned", "Ingen økter planlagt"),
                  systemImage: "calendar.badge.plus")
                .font(.system(size: 16, weight: .semibold, design: .serif))
            if !pinsDayActions, let suggestedTraining {
                Label(
                    suggestedTraining
                        ? tr("Suggested training day", "Foreslått treningsdag")
                        : tr("Suggested rest day", "Foreslått hviledag"),
                    systemImage: suggestedTraining ? "figure.run" : "moon.stars"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(suggestedTraining ? gold : secondary)
            }
            Text(tr("Add exercises or a complete workout, or mark this date as a rest day.",
                    "Legg til øvelser eller en komplett treningsøkt, eller sett dagen som hviledag."))
                .font(.caption).foregroundStyle(secondary)
            // The two gold actions and the simple rest-day action are
            // shared with populated days below; no duplicate button row.
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
    }

    private var restDayCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 28)).foregroundStyle(gold)
            Text(tr("Rest and recovery", "Hvile og restitusjon"))
                .font(.system(size: 20, weight: .semibold, design: .serif))
            Button(action: onRestDay) {
                Label(tr("Remove rest day", "Fjern hviledag"),
                      systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(gold)
            Button(action: onAddWorkout) {
                Label(tr("Add workout instead", "Legg til treningsøkt i stedet"),
                      systemImage: "plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(gold)
        }
        .frame(maxWidth: .infinity, minHeight: 152)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
    }

    private func workoutCard(
        _ workout: ATHLTHPlanStructuredWorkoutBlueprint, index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(secondary)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
                .draggable(ATHLTHPlanDragPayload.encode(scope: dragScope, key: dateKey, workout: index))
                .accessibilityLabel(tr("Drag workout", "Dra treningsøkt"))
            Button { onEditWorkout(index) } label: {
                HStack(spacing: 9) {
                    Image(systemName: workout.kind.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(gold)
                        .frame(width: 37, height: 37)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.65),
                                    in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.title)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                        Text("\(workout.blocks.count) " + tr("blocks", "blokker"))
                            .font(.caption).foregroundStyle(secondary)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(secondary)
                }
            }
            .buttonStyle(.plain)
            }
            .dropDestination(for: String.self) { items, _ in
                items.first.map { onDropItem($0, index, .main, nil) } ?? false
            }
            HStack {
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    pendingWorkoutDeletion = index
                    confirmingWorkoutDeletion = true
                } label: {
                    Label(tr("Delete workout", "Slett treningsøkt"),
                          systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondary)
                        .frame(minHeight: 34)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-guided-delete-workout-\(index)")
            }
            ForEach(ATHLTHWorkoutTimelinePresentation.sections(for: workout.blocks)) { section in
                phaseSection(section, workoutIndex: index, workout: workout)
            }
            // Empty phases are also valid drop targets.
            let existingPhases = Set(ATHLTHWorkoutTimelinePresentation.sections(for: workout.blocks).map(\.phase))
            ForEach([WorkoutPhaseKind.warmup, .main, .cooldown].filter { !existingPhases.contains($0) }, id: \.self) { phase in
                Label(phase.title, systemImage: phase.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(canvas, in: RoundedRectangle(cornerRadius: 9))
                    .dropDestination(for: String.self) { items, _ in
                        items.first.map { onDropItem($0, index, phase, nil) } ?? false
                    }
            }
            // Additional workouts are inserted by the common gold action
            // below every day, not by a second control inside the first card.
        }
        .padding(12)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(rule.opacity(0.38), lineWidth: 0.7)
        }
    }

    private func phaseSection(
        _ section: ATHLTHWorkoutTimelinePresentation.Section,
        workoutIndex: Int,
        workout: ATHLTHPlanStructuredWorkoutBlueprint
    ) -> some View {
        let phase = section.phase
        let blocks = section.blocks
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: phase.symbol).foregroundStyle(gold)
                    .frame(width: 18)
                Text(phase.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                Text("(\(section.activityCount))")
                    .font(.caption2).foregroundStyle(secondary)
                Spacer()
                Button { onAddExercise(phase, workoutIndex) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(gold)
                        .frame(width: 27, height: 27)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.55), in: Circle())
                }
                .accessibilityLabel(tr("Add to", "Legg til i") + " " + phase.title)
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                items.first.map { onDropItem($0, workoutIndex, phase, nil) } ?? false
            }
            ForEach(Array(blocks.enumerated()), id: \.element.editorDragID) { pair in
                if let groupID = pair.element.groupID,
                   let groupKind = pair.element.groupKind {
                    if !blocks.prefix(pair.offset).contains(where: {
                        $0.groupID == groupID
                    }) {
                        ATHLTHAdvancedPlanGroupSummaryRow(
                            kind: groupKind,
                            blocks: blocks.filter { $0.groupID == groupID },
                            onEditStep: { blockID in
                                if let sourceIndex = workout.blocks.firstIndex(where: {
                                    $0.editorDragID == blockID
                                }) {
                                    onEditBlock(workoutIndex, sourceIndex)
                                } else {
                                    onEditWorkout(workoutIndex)
                                }
                            }
                        )
                        .draggable(ATHLTHPlanDragPayload.encode(scope: dragScope, key: dateKey, workout: workoutIndex, block: pair.element.editorDragID))
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingBlockDeletion = (workoutIndex, pair.element.editorDragID)
                                confirmingBlockDeletion = true
                            } label: { Label(tr("Delete group", "Slett gruppe"), systemImage: "trash") }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            items.first.map { onDropItem($0, workoutIndex, phase, pair.element.editorDragID) } ?? false
                        }
                    }
                } else {
                Button {
                    // Use the original blueprint index, not the index within
                    // a displayed phase. This also handles interleaved rests.
                    if let blockIndex = workout.blocks.firstIndex(where: {
                        $0.editorDragID == pair.element.editorDragID
                    }) {
                        onEditBlock(workoutIndex, blockIndex)
                    } else {
                        onEditWorkout(workoutIndex)
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: pair.element.kind == .rest ? "pause.circle.fill" :
                              pair.element.kind == .exercise ? "dumbbell" :
                              pair.element.kind == .run ? "figure.run" : "figure.cooldown")
                            .font(.caption)
                            .foregroundStyle(pair.element.kind == .rest ? gold : secondary)
                            .frame(width: 19)
                        Text(pair.element.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(pair.element.targetText ?? "")
                            .font(.caption)
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(secondary)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                    .background(pair.element.kind == .rest
                        ? ATHLTHTrainDesign.paleGold.opacity(0.43) : canvas.opacity(0.70),
                        in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .draggable(ATHLTHPlanDragPayload.encode(scope: dragScope, key: dateKey, workout: workoutIndex, block: pair.element.editorDragID))
                .dropDestination(for: String.self) { items, _ in
                    items.first.map { onDropItem($0, workoutIndex, phase, pair.element.editorDragID) } ?? false
                }
                .contextMenu {
                    Button(role: .destructive) {
                        pendingBlockDeletion = (workoutIndex, pair.element.editorDragID)
                        confirmingBlockDeletion = true
                    } label: { Label(tr("Delete step", "Slett deløkt"), systemImage: "trash") }
                }
                .accessibilityHint(tr(
                    "Edit the duration, pace, intensity or recovery for this step.",
                    "Rediger varighet, tempo, intensitet eller pause for denne deløkten."
                ))
                }
            }
        }
    }

    private func goldAction(
        _ title: String, symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(gold.gradient, in: RoundedRectangle(cornerRadius: 15))
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }

    // One consistent two-row action palette across empty and populated dates.
    // Choices append directly to the current workout when one exists.
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            quickRow {
                quick("walking", "figure.walk", tr("Walk", "Gå"))
                quick("running", "figure.run", tr("Running", "Løping"))
                quick("strength", "dumbbell", tr("Strength", "Styrke"))
                quick("cycling", "bicycle", tr("Cycling", "Sykling"))
                moreActivities
            }
            quickRow {
                quick("rest", "pause.fill", tr("Rest", "Pause"))
                quick("active-rest", "figure.walk", tr("Active rest", "Aktiv pause"))
                quick("stretching", "figure.cooldown", tr("Stretching", "Uttøying"))
            }
        }
    }

    private func quickRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }
                .frame(minHeight: 44)
        }
    }

    private var moreActivities: some View {
        Menu {
            Button { onQuick("yoga") } label: {
                Label("Yoga", systemImage: "figure.yoga")
            }
            Button { onQuick("meditation") } label: {
                Label(tr("Meditation", "Meditasjon"), systemImage: "leaf")
            }
        } label: {
            Label(tr("More", "Flere"), systemImage: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(.white, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(tr("More activities", "Flere treningsmoduser"))
    }

    private func quick(_ id: String, _ symbol: String, _ text: String) -> some View {
        Button {
            onQuick(id)
        } label: {
            Label(text, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(.white, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

