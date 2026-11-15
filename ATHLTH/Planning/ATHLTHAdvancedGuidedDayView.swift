import SwiftUI

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
    let onSelectDay: (Int) -> Void
    let onAddExercise: (WorkoutPhaseKind, Int) -> Void
    let onAddWorkout: () -> Void
    let onQuick: (String) -> Void
    let onAddGroup: ([WorkoutTemplateBlock], WorkoutKind) -> Void
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
    @State private var composingGroup: WorkoutBlockGroupKind?
    private let ink = ATHLTHTrainDesign.ink
    private let secondary = ATHLTHTrainDesign.secondary
    private let gold = ATHLTHTrainDesign.bronze
    private let canvas = ATHLTHTrainDesign.canvas
    private let rule = ATHLTHTrainDesign.rule

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if isRestDay {
                restDayCard
            } else if workouts.isEmpty {
                emptyDayCard
            } else {
                ForEach(Array(workouts.enumerated()), id: \.offset) { pair in
                    workoutCard(pair.element, index: pair.offset)
                }
            }
            if !isRestDay {
                quickActions
                VStack(spacing: 9) {
                    goldAction(
                        tr("Add workout", "Legg til treningsøkt"),
                        symbol: "plus"
                    ) {
                        onAddWorkout()
                    }
                    goldAction(
                        tr("Ask Coach to fill empty days", "Be Coach fylle ut"),
                        symbol: "sparkles"
                    ) {
                        onCoachFill()
                    }
                }
                Button {
                    if workouts.isEmpty {
                        onRestDay()
                    } else {
                        confirmingRestReplacement = true
                    }
                } label: {
                    Label(tr("Rest day", "Legg til hviledag"), systemImage: "moon.stars")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondary)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            if let composingGroup, !isRestDay {
                ATHLTHPlanInlineGroupComposer(
                    groupKind: composingGroup,
                    onInsert: { blocks, kind in
                        onAddGroup(blocks, kind)
                        self.composingGroup = nil
                    },
                    onCancel: { self.composingGroup = nil }
                )
            }
        }
        .frame(maxWidth: widthClass == .regular ? .infinity : ATHLTHPlanDesign.maxContentWidth)
        .onChange(of: date) { _, _ in
            // Never carry an uncommitted group to another calendar day.
            composingGroup = nil
        }
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
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quick("walking", "figure.walk", tr("Walk", "Gå"))
                    quick("running", "figure.run", tr("Running", "Løping"))
                    quick("strength", "dumbbell", tr("Strength", "Styrke"))
                    quick("cycling", "bicycle", tr("Cycling", "Sykling"))
                    quick("yoga", "figure.yoga", "Yoga")
                    quick("meditation", "leaf", tr("Meditation", "Meditasjon"))
                }
                .frame(minHeight: 35)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    quick("workout", "list.bullet", tr("Workout", "Treningsøkt"))
                    quick("exercise", "dumbbell", tr("Exercise", "Øvelse"))
                    quick("rest", "pause.fill", tr("Rest", "Pause"))
                    quick("active-rest", "figure.walk", tr("Active rest", "Aktiv pause"))
                    quick("stretching", "figure.cooldown", tr("Stretching", "Uttøying"))
                }
                .frame(minHeight: 35)
            }
        }
    }

    private func quick(_ id: String, _ symbol: String, _ text: String) -> some View {
        Button {
            if id == "interval" || id == "superset" {
                composingGroup = id == "interval" ? .intervals : .superset
            } else if id == "restday" && !workouts.isEmpty {
                confirmingRestReplacement = true
            } else {
                onQuick(id)
            }
        } label: {
            Label(text, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

