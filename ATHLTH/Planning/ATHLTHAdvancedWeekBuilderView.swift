import SwiftUI

/// The single live UI for Advanced → Week by week. It edits the same
/// dated training-plan draft as Advanced → Day by day; no nested legacy UI.
struct ATHLTHAdvancedWeekBuilderView: View {
    struct Day: Identifiable {
        let weekday: Int                 // Monday = 1
        let date: Date
        let isRestDay: Bool
        let workouts: [ATHLTHPlanStructuredWorkoutBlueprint]
        let suggestedTitle: String?
        let planned: Bool

        var id: Int { weekday }
        var title: String {
            if isRestDay { return ATHLTHLocalization.choose(english: "Rest day", norwegian: "Hviledag") }
            if let first = workouts.first { return first.title }
            if planned { return ATHLTHLocalization.choose(english: "Plan workout", norwegian: "Planlegg økt") }
            return ATHLTHLocalization.choose(english: "Not planned", norwegian: "Ikke planlagt")
        }
        var kind: WorkoutKind? { workouts.first?.kind }
        var totalBlocks: Int { workouts.reduce(0) { $0 + $1.blocks.count } }
    }

    @Binding var selectedWeek: Int
    @Binding var weekCount: Int
    let startDate: Date
    let days: [Day]
    let workoutsPerWeek: [Int]
    let weekSymbols: [[String]]
    let onEditWorkout: (Int, Int) -> Void
    let onAddExercise: (Int, Int, WorkoutPhaseKind) -> Void
    let onAddWorkout: (Int) -> Void
    let onMarkRest: (Int) -> Void
    let onQuick: (Int, String) -> Void
    let onCopyWeek: (Int, [Int], Bool) -> Void
    let onMakeRecoveryWeek: (Int) -> Void

    @State private var selectedDay: Int? = nil
    @State private var showingStructure = false
    @State private var showingCopy = false
    @State private var copyTargets: Set<Int> = []
    @State private var replaceTargets = false
    @State private var templateSourceWeek: Int? = nil
    @State private var pendingRecovery = false
    @State private var pendingRemoveLast = false

    private let ink = ATHLTHTrainDesign.ink
    private let secondary = ATHLTHTrainDesign.secondary
    private let gold = ATHLTHTrainDesign.bronze
    private let paper = ATHLTHTrainDesign.canvas
    private let divider = ATHLTHTrainDesign.rule

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var orderedDays: [Day] { days.sorted { $0.date < $1.date } }
    private var weekStart: Date {
        Calendar.current.date(byAdding: .day, value: selectedWeek * 7,
                              to: Calendar.current.startOfDay(for: startDate)) ?? startDate
    }
    private func weekStart(_ week: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: week * 7,
                              to: Calendar.current.startOfDay(for: startDate)) ?? startDate
    }
    private func weekRange(_ week: Int) -> String {
        let from = weekStart(week)
        let to = Calendar.current.date(byAdding: .day, value: 6, to: from) ?? from
        return from.formatted(.dateTime.day().month(.abbreviated)) + " – " +
            to.formatted(.dateTime.day().month(.abbreviated))
    }
    private var totalWorkouts: Int { workoutsPerWeek.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let selectedDay, let day = days.first(where: { $0.weekday == selectedDay }) {
                detail(day)
            } else if showingStructure {
                structure
            } else {
                overview
            }
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
        .animation(.easeInOut(duration: 0.16), value: selectedDay)
        .animation(.easeInOut(duration: 0.16), value: showingStructure)
        .sheet(isPresented: $showingCopy) {
            copySheet
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            tr("Make this a recovery week?", "Gjøre uken til restitusjonsuke?"),
            isPresented: $pendingRecovery, titleVisibility: .visible
        ) {
            Button(tr("Set all days to rest", "Sett alle dagene til hvile"), role: .destructive) {
                onMakeRecoveryWeek(selectedWeek)
            }
        } message: {
            Text(tr("Existing workouts in this week will be replaced by rest days.",
                    "Eksisterende økter i uken blir erstattet med hviledager."))
        }
        .confirmationDialog(
            tr("Shorten the plan?", "Forkorte treningsplanen?"),
            isPresented: $pendingRemoveLast, titleVisibility: .visible
        ) {
            Button(tr("Remove last week", "Fjern siste uke"), role: .destructive) {
                guard weekCount > 1 else { return }
                weekCount -= 1
                selectedWeek = min(selectedWeek, weekCount - 1)
            }
        } message: {
            Text(tr("Any edits in the last week will be excluded from the plan.",
                    "Endringer i den siste uken blir ikke med videre."))
        }
        .onChange(of: selectedWeek) { _, _ in
            selectedDay = nil
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            scenicHeader
            HStack {
                Button { selectedWeek = max(0, selectedWeek - 1) } label: {
                    Image(systemName: "arrow.left")
                        .frame(width: 42, height: 40)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedWeek == 0)
                Spacer()
                VStack(spacing: 3) {
                    Text(tr("Week", "Uke") + " \(selectedWeek + 1) " +
                         tr("of", "av") + " \(weekCount)")
                        .font(.subheadline.weight(.semibold))
                    Text(weekRange(selectedWeek))
                        .font(.caption).foregroundStyle(secondary)
                }
                Spacer()
                Button { selectedWeek = min(weekCount - 1, selectedWeek + 1) } label: {
                    Image(systemName: "arrow.right")
                        .frame(width: 42, height: 40)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(selectedWeek >= weekCount - 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(gold)
            ForEach(orderedDays) { day in
                dayRow(day)
            }
            HStack(spacing: 9) {
                action(tr("Add workout", "Legg til økt"), icon: "plus") {
                    onAddWorkout(orderedDays.first(where: { !$0.isRestDay })?.weekday ??
                                 orderedDays.first?.weekday ?? 1)
                }
                action(tr("Copy week", "Kopier uke"), icon: "square.on.square") {
                    presentCopy(source: selectedWeek)
                }
            }
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Week tools", "Ukeverktøy"))
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                HStack(spacing: 7) {
                    smallTool(tr("Empty week", "Tøm uke"), "trash", role: .destructive) {
                        pendingRecovery = true
                    }
                    smallTool(tr("Use as template", "Sett som mal"), "square.stack") {
                        templateSourceWeek = selectedWeek
                    }
                    smallTool(tr("Paste template", "Bruk mal"), "doc.on.clipboard") {
                        guard let source = templateSourceWeek else { return }
                        presentCopy(source: source)
                    }
                    smallTool(tr("More weeks", "Flere uker"), "ellipsis") {
                        showingStructure = true
                    }
                }
            }
            .padding(12)
            .background(.white.opacity(0.81), in: RoundedRectangle(cornerRadius: 16))
            Button { showingStructure = true } label: {
                HStack {
                    Label(tr("Full plan structure", "Hele planstrukturen"),
                          systemImage: "calendar")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(gold)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var scenicHeader: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                Image("PlanGoalHero")
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(
                stops: [
                    .init(color: paper, location: 0),
                    .init(color: paper.opacity(0.97), location: 0.30),
                    .init(color: paper.opacity(0.62), location: 0.65),
                    .init(color: paper.opacity(0.03), location: 1)
                ], startPoint: .leading, endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 7) {
                Text(tr("WEEK BUILDER", "UKEBYGGER"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8).foregroundStyle(secondary)
                Text(tr("Week", "Uke") + " \(selectedWeek + 1)")
                    .font(.system(size: 36, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(tr("Plan the week with freedom to add, move and edit workouts.",
                        "Planlegg hele uken med full fleksibilitet. Legg til, flytt og juster økter."))
                    .font(.system(size: 12)).foregroundStyle(secondary)
                    .frame(maxWidth: 185, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)
        }
        .frame(height: 135)
        .clipped()
    }

    private func dayRow(_ day: Day) -> some View {
        Button {
            selectedDay = day.weekday
        } label: {
            HStack(spacing: 8) {
                VStack(spacing: 5) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 11, weight: .semibold))
                    Text(day.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 9))
                }
                .foregroundStyle(secondary)
                .frame(width: 59)
                .frame(minHeight: 58)
                .background(paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                Image(systemName: day.isRestDay ? "pause.fill" :
                      (day.kind?.systemImage ?? "plus.circle"))
                    .foregroundStyle(gold)
                    .font(.system(size: 17))
                    .frame(width: 29)
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.title)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(day.isRestDay ? tr("Recovery", "Restitusjon") :
                         day.workouts.isEmpty ? tr("Add your workout", "Legg inn økt") :
                         "\(day.workouts.count) " + tr("workouts", "økter") +
                         " · \(day.totalBlocks) " + tr("blocks", "blokker"))
                        .font(.system(size: 10))
                        .foregroundStyle(secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis").foregroundStyle(secondary)
                    .frame(width: 24, height: 36)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(divider.opacity(0.36), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func detail(_ day: Day) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Button { selectedDay = nil } label: {
                    Label(tr("Back to week", "Til uken"), systemImage: "chevron.left")
                        .font(.caption.weight(.medium))
                }
                Spacer()
                Text(day.date.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.caption).foregroundStyle(secondary)
            }
            .foregroundStyle(gold)
            ZStack(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Image("PlanGoalHero").resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                    Text(day.title)
                        .font(.system(size: 29, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                    Text("\(day.workouts.count) " + tr("workouts", "økter"))
                        .font(.caption).foregroundStyle(.white.opacity(0.88))
                }
                .padding(13)
            }
            .frame(height: 166)
            .clipShape(RoundedRectangle(cornerRadius: 17))
            if day.isRestDay || day.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 13) {
                    Label(day.isRestDay ? tr("Rest and recovery", "Hvile og restitusjon") :
                          tr("No workouts here yet", "Ingen treningsøkter ennå"),
                          systemImage: day.isRestDay ? "moon.stars" : "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 9) {
                        action(tr("Add workout", "Legg til økt"), icon: "plus") {
                            onAddWorkout(day.weekday)
                        }
                        action(tr("Add exercise", "Legg til øvelse"), icon: "dumbbell") {
                            onAddExercise(day.weekday, 0, .main)
                        }
                    }
                }
                .padding(13)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(day.workouts.indices, id: \.self) { workoutIndex in
                    workoutDetail(day.workouts[workoutIndex], day: day.weekday,
                                  index: workoutIndex)
                }
            }
            quickActions(day.weekday)
            HStack(spacing: 9) {
                action(tr("Previous day", "Forrige dag"), icon: "arrow.left") {
                    moveDetail(from: day.weekday, by: -1)
                }
                action(tr("Next day", "Neste dag"), icon: "arrow.right") {
                    moveDetail(from: day.weekday, by: 1)
                }
            }
        }
    }

    private func moveDetail(from weekday: Int, by direction: Int) {
        guard let index = orderedDays.firstIndex(where: { $0.weekday == weekday }),
              orderedDays.indices.contains(index + direction) else {
            selectedDay = nil
            return
        }
        selectedDay = orderedDays[index + direction].weekday
    }

    private func workoutDetail(_ workout: ATHLTHPlanStructuredWorkoutBlueprint,
                               day: Int, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: workout.kind.systemImage).foregroundStyle(gold)
                    .frame(width: 30, height: 30)
                    .background(ATHLTHTrainDesign.paleGold, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                    Text("\(workout.blocks.count) " + tr("blocks", "blokker"))
                        .font(.caption2).foregroundStyle(secondary)
                }
                Spacer()
                Button { onEditWorkout(day, index) } label: {
                    Label(tr("Edit", "Rediger"), systemImage: "pencil")
                        .font(.caption).foregroundStyle(gold)
                }
                .buttonStyle(.plain)
            }
            phase(.warmup, workout: workout, day: day, index: index)
            phase(.main, workout: workout, day: day, index: index)
            phase(.cooldown, workout: workout, day: day, index: index)
            if workout.blocks.contains(where: { $0.resolvedPhase == .recovery }) {
                phase(.recovery, workout: workout, day: day, index: index)
            }
        }
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
    }

    private func phase(_ phase: WorkoutPhaseKind,
                       workout: ATHLTHPlanStructuredWorkoutBlueprint,
                       day: Int, index: Int) -> some View {
        let blocks = workout.blocks.filter { $0.resolvedPhase == phase }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: phase.symbol)
                    .foregroundStyle(gold)
                Text(phase.title)
                    .font(.subheadline.weight(.semibold))
                Text("(\(blocks.count))")
                    .font(.caption).foregroundStyle(secondary)
                Spacer()
                Button { onAddExercise(day, index, phase) } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(width: 31, height: 31)
                        .background(paper, in: Circle())
                }
                .foregroundStyle(gold)
                .accessibilityLabel(tr("Add to", "Legg til i") + " " + phase.title)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { pair in
                HStack(spacing: 9) {
                    Image(systemName: pair.element.kind == .rest
                          ? "pause.circle.fill" : pair.element.kind == .exercise
                          ? "dumbbell" : pair.element.kind == .run ? "figure.run" : "leaf")
                        .font(.caption).foregroundStyle(gold)
                        .frame(width: 18)
                    Text(pair.element.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    Spacer()
                    Text(pair.element.targetText ?? "")
                        .font(.system(size: 10)).foregroundStyle(secondary)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                }
                .padding(10)
                .background(pair.element.kind == .rest
                            ? ATHLTHTrainDesign.paleGold.opacity(0.5) : paper.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 10))
            }
            action(tr("Add to", "Legg til i") + " " + phase.title, icon: "plus") {
                onAddExercise(day, index, phase)
            }
        }
    }

    private func quickActions(_ weekday: Int) -> some View {
        VStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    quick("running", "figure.run", tr("Running", "Løping"), weekday)
                    quick("walking", "figure.walk", tr("Walking", "Gå"), weekday)
                    quick("cycling", "bicycle", tr("Cycling", "Sykling"), weekday)
                    quick("yoga", "figure.yoga", "Yoga", weekday)
                    quick("meditation", "leaf", tr("Meditation", "Meditasjon"), weekday)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Button { onAddExercise(weekday, 0, .main) } label: {
                        Label(tr("Exercise", "Øvelse"), systemImage: "dumbbell")
                    }
                    Button { onAddWorkout(weekday) } label: {
                        Label(tr("Workout", "Treningsøkt"), systemImage: "list.bullet")
                    }
                    quick("interval", "waveform.path", tr("Interval", "Intervall"), weekday)
                    quick("superset", "link", "Supersett", weekday)
                    quick("rest", "pause.fill", tr("Rest", "Pause"), weekday)
                    Button { onAddExercise(weekday, 0, .cooldown) } label: {
                        Label(tr("Stretching", "Uttøying"), systemImage: "figure.cooldown")
                    }
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered).tint(gold)
            }
        }
    }

    private func quick(_ id: String, _ symbol: String,
                       _ text: String, _ day: Int) -> some View {
        Button { onQuick(day, id) } label: {
            Label(text, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 10).frame(minHeight: 32)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink)
    }

    private var structure: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Plan structure", "Planstruktur"))
                        .font(.system(size: 31, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr("See and edit the whole plan", "Se og rediger hele planen"))
                        .font(.caption).foregroundStyle(secondary)
                }
                Spacer()
                Menu {
                    ForEach(1...52, id: \.self) { count in
                        Button("\(count) " + tr("weeks", "uker")) {
                            weekCount = count
                            selectedWeek = min(selectedWeek, count - 1)
                        }
                    }
                } label: {
                    Text("\(weekCount) " + tr("weeks", "uker"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                        .padding(10)
                        .background(.white, in: Capsule())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(0..<weekCount, id: \.self) { week in
                        Button {
                            selectedWeek = week
                            showingStructure = false
                        } label: {
                            VStack(spacing: 5) {
                                Text(tr("Week", "Uke") + " \(week + 1)")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(weekStart(week).formatted(.dateTime.day().month(.abbreviated)))
                                    .font(.system(size: 9))
                            }
                            .foregroundStyle(week == selectedWeek ? .white : ink)
                            .frame(width: 66, height: 56)
                            .background(week == selectedWeek ? gold : .white,
                                        in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ForEach(0..<weekCount, id: \.self) { week in
                Button {
                    selectedWeek = week
                    showingStructure = false
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(tr("Week", "Uke") + " \(week + 1)")
                                .font(.system(size: 17, weight: .semibold, design: .serif))
                            Text(weekRange(week))
                                .font(.system(size: 10)).foregroundStyle(secondary)
                            Spacer(minLength: 0)
                            Text("\(workoutsPerWeek.indices.contains(week) ? workoutsPerWeek[week] : 0) " +
                                 tr("workouts", "økter"))
                                .font(.system(size: 10)).foregroundStyle(gold)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(gold)
                        }
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { offset in
                                let date = Calendar.current.date(byAdding: .day, value: offset,
                                                                  to: weekStart(week)) ?? weekStart(week)
                                VStack(spacing: 6) {
                                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                        .font(.system(size: 9))
                                    Image(systemName: weekSymbols.indices.contains(week) &&
                                        weekSymbols[week].indices.contains(offset)
                                        ? weekSymbols[week][offset] : "calendar")
                                        .font(.system(size: 13))
                                        .foregroundStyle(gold)
                                }
                                .frame(maxWidth: .infinity, minHeight: 43)
                                .background(paper.opacity(0.85),
                                            in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                    .foregroundStyle(ink)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            Button {
                if weekCount < 52 {
                    weekCount += 1
                    selectedWeek = weekCount - 1
                    showingStructure = false
                }
            } label: {
                Label(tr("Add week", "Legg til uke"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(gold.gradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 11) {
                Text(tr("Week actions", "Ukehandlinger"))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                HStack(spacing: 8) {
                    smallTool(tr("Copy week", "Kopier uke"), "square.on.square") {
                        presentCopy(source: selectedWeek)
                    }
                    smallTool(tr("Use template", "Bruk mal"), "doc.on.clipboard") {
                        if let source = templateSourceWeek {
                            presentCopy(source: source)
                        } else {
                            templateSourceWeek = selectedWeek
                        }
                    }
                    smallTool(tr("Remove last", "Fjern siste"), "trash", role: .destructive) {
                        if weekCount > 1 { pendingRemoveLast = true }
                    }
                    smallTool(tr("Recovery week", "Restitusjonsuke"), "leaf") {
                        pendingRecovery = true
                    }
                }
            }
        }
    }

    private func presentCopy(source: Int) {
        copyTargets = []
        for index in 0..<weekCount where index != source {
            copyTargets.insert(index)
        }
        replaceTargets = false
        // Remember the source; selectedWeek is restored on the copy sheet's close.
        selectedWeek = source
        showingCopy = true
    }

    private var copySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("Copy week", "Kopier uke") + " \(selectedWeek + 1)")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                    Text(tr("Choose which weeks to receive this week's workouts. Individual changes are protected by default.",
                            "Velg ukene som skal få denne ukens økter. Egne tilpasninger beskyttes som standard."))
                        .font(.subheadline).foregroundStyle(secondary)
                    ForEach(0..<weekCount, id: \.self) { index in
                        if index != selectedWeek {
                            Toggle(isOn: Binding(
                                get: { copyTargets.contains(index) },
                                set: { value in
                                    if value { copyTargets.insert(index) }
                                    else { copyTargets.remove(index) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tr("Week", "Uke") + " \(index + 1)")
                                    Text(weekRange(index))
                                        .font(.caption).foregroundStyle(secondary)
                                }
                            }
                            .tint(gold)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    Toggle(tr("Replace existing individual workouts",
                              "Erstatt eksisterende individuelle økter"),
                           isOn: $replaceTargets)
                        .tint(gold)
                    Button {
                        onCopyWeek(selectedWeek, copyTargets.sorted(), replaceTargets)
                        showingCopy = false
                    } label: {
                        Label(tr("Copy to selected weeks", "Kopier til valgte uker"),
                              systemImage: "square.on.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(gold.gradient, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(copyTargets.isEmpty)
                }
                .padding(15)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Copy week", "Kopier uke"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Done", "Ferdig")) { showingCopy = false }
                }
            }
        }
    }

    private func action(_ title: String, icon: String,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(gold)
                .frame(maxWidth: .infinity, minHeight: 43)
                .background(.white.opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private func smallTool(_ title: String, _ symbol: String,
                           role: ButtonRole? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15)).foregroundStyle(gold)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(ink)
                    .lineLimit(2).minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 53)
            .background(paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
