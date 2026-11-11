import SwiftUI

/// Plan setup used by the real ATHLTHTrainingPlanBuilderFlow.
/// Simple and Advanced share one visual system and the same persistent model.
/// There are no demonstration goals, duplicate plan values or global session times.
struct ATHLTHPlanSimpleScheduleEntryView: View {
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var weekCount: Int
    @Binding var linkedGoalIDs: Set<UUID>
    let selectedDays: Set<Int>
    let goals: [ATHLTHGoal]
    let suggestedName: String
    let onToggleDay: (Int) -> Void
    let onCreateGoal: () -> Void
    let onSelectAdvanced: () -> Void

    var body: some View {
        ATHLTHPlanSetupFields(
            title: $title, startDate: $startDate, weekCount: $weekCount,
            linkedGoalIDs: $linkedGoalIDs,
            selectedDays: selectedDays, goals: goals,
            suggestedName: suggestedName, advanced: false,
            planningApproach: nil,
            varyWeekdays: .constant(false),
            onToggleDay: onToggleDay,
            onCreateGoal: onCreateGoal,
            onChooseApproach: { _ in },
            onModeChange: { isAdvanced in
                if isAdvanced { onSelectAdvanced() }
            }
        )
    }
}

/// Reusable, fully rebuilt visual contract for plan setup.
/// The wrappers are thin mode entry points, not legacy layouts stacked together.
struct ATHLTHPlanSetupFields: View {
    @Environment(\.horizontalSizeClass) private var widthClass
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var weekCount: Int
    @Binding var linkedGoalIDs: Set<UUID>
    let selectedDays: Set<Int>
    let goals: [ATHLTHGoal]
    let suggestedName: String
    let advanced: Bool
    let planningApproach: ATHLTHPlanWeekPlanningApproach?
    @Binding var varyWeekdays: Bool
    let onToggleDay: (Int) -> Void
    let onCreateGoal: () -> Void
    let onChooseApproach: (ATHLTHPlanWeekPlanningApproach) -> Void
    let onModeChange: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingAllGoals = false
    @State private var customWeekCount = false

    private let canvas = ATHLTHTrainDesign.canvas
    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let gold = ATHLTHTrainDesign.gold
    private let border = ATHLTHTrainDesign.rule

    private let weekdays: [(index: Int, en: String, no: String)] = [
        (1,"Mon","Man"), (2,"Tue","Tir"), (3,"Wed","Ons"),
        (4,"Thu","Tor"), (5,"Fri","Fre"), (6,"Sat","Lør"), (7,"Sun","Søn")
    ]

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if advanced {
                advancedIntro
            } else {
                hero
            }
            nameCard
            if advanced {
                // Date and duration belong with plan identity at the top.
                // Keep the adaptive two-column layout on standard phones.
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 10) { startCard; durationCard }
                } else {
                    HStack(alignment: .top, spacing: 9) {
                        startCard
                        durationCard
                    }
                }
                daysCard
                goalsCard
                // Choose day-by-day or weekly editing last, immediately
                // before Next leads into the actual week editor.
                planningApproachCard
            } else {
                goalsCard
                daysCard
                startCard
            }
        }
        .frame(maxWidth: widthClass == .regular ? .infinity : ATHLTHPlanDesign.maxContentWidth)
    }

    private var advancedIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(tr("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                    .font(.caption2.weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(muted)
                Spacer(minLength: 0)
                modeTab(false, title: tr("Simple", "Enkel"))
                modeTab(true, title: tr("Advanced", "Avansert"))
            }
            Text(tr("Shape your training plan", "Tilpass treningsplanen"))
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(tr(
                "Choose your dates, training days and goals, then how to build each week.",
                "Velg datoer, treningsdager og mål, og deretter hvordan du vil planlegge."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private var planningApproachCard: some View {
        card {
            cardHeading("square.grid.2x2",
                        tr("Planning layout", "Hvordan vil du planlegge?"),
                        detail: tr("Choose how to build your workouts",
                                   "Velg hvordan du ønsker å sette opp øktene"))
            VStack(spacing: 8) {
                planningApproachOption(
                    .guided,
                    title: tr("Daily plan", "Dagsplan"),
                    detail: tr(
                        "Build one training day at a time, with exercises, intervals and rest.",
                        "Sett opp én dag om gangen med økter, intervaller og hvile."
                    ),
                    icon: "calendar.day.timeline.left"
                )
                planningApproachOption(
                    .quick,
                    title: tr("Weekly plan", "Ukeplan"),
                    detail: tr(
                        "Build complete weeks and adjust workouts and progression.",
                        "Sett sammen hele uken og juster økter og progresjon."
                    ),
                    icon: "calendar"
                )
            }
        }
    }

    private func planningApproachOption(
        _ choice: ATHLTHPlanWeekPlanningApproach,
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        let selected = planningApproach == choice
        return Button {
            onChooseApproach(choice)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(bronze)
                    .frame(width: 39, height: 39)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.50),
                                in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if choice == .guided {
                        VStack(spacing: 4) {
                            ForEach(1...3, id: \.self) { day in
                                HStack(spacing: 7) {
                                    Text(tr("Day", "Dag") + " \(day)")
                                        .frame(width: 42, alignment: .leading)
                                    Capsule().fill(day == 1 ? bronze : border.opacity(0.4)).frame(height: 5)
                                    Image(systemName: day == 1 ? "pencil" : "circle")
                                }
                            }
                        }
                        .font(.caption2).foregroundStyle(bronze).padding(.top, 6)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(1...7, id: \.self) { day in
                                VStack(spacing: 4) {
                                    Text("\(day)")
                                    Image(systemName: selectedDays.contains(day) ? "figure.run" : "moon.stars")
                                }
                                .font(.caption2).foregroundStyle(bronze)
                                .frame(maxWidth: .infinity, minHeight: 33)
                                .background(ATHLTHTrainDesign.paleGold.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? bronze : border)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(selected ? ATHLTHTrainDesign.paleGold.opacity(0.28)
                                 : canvas.opacity(0.50),
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(selected ? bronze.opacity(0.75) : border.opacity(0.38),
                                  lineWidth: selected ? 1.15 : 0.65)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A pair of real buttons, each styled like the wizard's "Tilbake"
    /// capsule. Their actions are driven by the owning plan builder.
    private func modeTab(_ isAdvanced: Bool, title: String) -> some View {
        let selected = advanced == isAdvanced
        return Button {
            onModeChange(isAdvanced)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? ink : muted)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color.white.opacity(0.85), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            selected ? bronze.opacity(0.65) : Color.black.opacity(0.08),
                            lineWidth: selected ? 1.2 : 0.8
                        )
                        .allowsHitTesting(false)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                Image(advanced ? "PlanEntryAdvanced" : "PlanEntrySimple")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)

            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.99), location: 0.29),
                    .init(color: canvas.opacity(0.85), location: 0.53),
                    .init(color: canvas.opacity(0.05), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 7) {
                    Text(tr("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(muted)
                    Spacer(minLength: 2)
                    modeTab(false, title: tr("Simple", "Enkel"))
                    modeTab(true, title: tr("Advanced", "Avansert"))
                }
                .padding(.top, 8)

                Spacer(minLength: 10)

                VStack(alignment: .leading, spacing: 5) {
                    Text(advanced
                         ? tr("Build your plan\nin detail", "Bygg planen\nmer detaljert")
                         : tr("Build your plan\nsimply", "Bygg planen\nenkelt"))
                        .font(.system(size: typeSize.isAccessibilitySize ? 30 : 34,
                                      weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                        .lineSpacing(-2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(advanced
                         ? tr("Adapt the plan to your goals and everyday life.",
                              "Tilpass planen etter dine mål, hverdag og preferanser.")
                         : tr("A few choices, and we'll help build your plan.",
                              "Noen få valg, så lager vi en treningsplan som passer deg."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .padding(.trailing, typeSize.isAccessibilitySize ? 50 : 115)
                .padding(.bottom, 13)
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 235 : 194)
        .clipped()
    }

    private func card<Content: View>(@ViewBuilder _ contents: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9, content: contents)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(border.opacity(0.33), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
            .shadow(color: bronze.opacity(0.035), radius: 7, y: 3)
    }

    private func cardHeading(_ icon: String, _ text: String,
                             detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(bronze)
                .frame(width: 35, height: 35)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.45), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var nameCard: some View {
        card {
            cardHeading("pencil", tr("Plan name (optional)", "Navn på planen (valgfritt)"))
            TextField(suggestedName, text: $title)
                .font(.system(size: 12))
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .frame(height: 37)
                .background(canvas.opacity(0.70), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(border.opacity(0.38), lineWidth: 0.65)
                }
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel(tr("Plan name optional", "Navn på planen, valgfritt"))
                .onChange(of: title) { _, value in
                    if value.count > 40 { title = String(value.prefix(40)) }
                }
        }
    }

    private var goalsCard: some View {
        card {
            HStack {
                cardHeading("target", advanced
                            ? tr("Link to goal or event", "Koble til aktivt mål / konkurranse")
                            : tr("Link to active goal", "Koble til aktivt mål"))
                Button(tr("See all", "Se alle")) {
                    showingAllGoals.toggle()
                }
                .font(.system(size: 10))
                .foregroundStyle(bronze)
                .disabled(goals.count <= 2)
                .opacity(goals.count > 2 ? 1 : 0)
            }
            if goals.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "target").foregroundStyle(bronze)
                    Text(tr("You have no active goals yet.",
                            "Du har ingen aktive mål ennå."))
                        .foregroundStyle(muted)
                        .font(.system(size: 11))
                }
                .padding(.vertical, 6)
            } else {
                ForEach(showingAllGoals ? goals : Array(goals.prefix(2))) { item in
                    goalRow(item)
                }
            }
            Button(action: onCreateGoal) {
                HStack(spacing: 9) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(bronze)
                    Text(tr("Create new goal", "Opprett nytt mål"))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(canvas.opacity(0.67), in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
    }

    private func goalRow(_ item: ATHLTHGoal) -> some View {
        let chosen = linkedGoalIDs.contains(item.id)
        return Button {
            linkedGoalIDs = chosen ? [] : [item.id]
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.category.systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(bronze)
                    .frame(width: 31, height: 31)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.40),
                                in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                    if let deadline = item.deadline {
                        Text(deadline.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10))
                            .foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(chosen ? bronze : border)
            }
            .padding(9)
            .background(chosen ? ATHLTHTrainDesign.paleGold.opacity(0.20)
                        : canvas.opacity(0.47),
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(chosen ? bronze.opacity(0.80) : border.opacity(0.26),
                                  lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var daysCard: some View {
        card {
            cardHeading("calendar.badge.checkmark",
                        tr("Training days", "Treningsdager"),
                        detail: tr("Other days are rest days",
                                   "Resterende dager blir hviledager"))
            if advanced {
                // The approved circular weekday selector: a full 44-point
                // touch target, gold ring and a visible check on chosen days.
                // Scroll horizontally if seven circles cannot fit a narrow
                // iPhone or an accessibility-size window.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) {
                        ForEach(weekdays, id: \.index) { day in
                            circularWeekday(day)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(weekdays, id: \.index) { day in
                                circularWeekday(day)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(weekdays, id: \.index) { day in
                        let chosen = selectedDays.contains(day.index)
                        Button { onToggleDay(day.index) } label: {
                            Text(tr(day.en, day.no))
                                .font(.system(size: 10, weight: chosen ? .semibold : .medium))
                                .foregroundStyle(chosen ? .white : ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(chosen ? bronze : canvas, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(border.opacity(chosen ? 0 : 0.42),
                                                           lineWidth: 0.6)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            if advanced && planningApproach == .quick {
                // Dagsplan edits each date directly, so a week variation toggle
                // would be redundant. Preserve the saved choice for Ukeplan.
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .foregroundStyle(bronze)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Vary days between weeks", "Varier dagene"))
                            .font(.system(size: 11, weight: .medium))
                        Text(tr("Customize each week in the next step",
                                "Tilpass dagene i hver uke i neste steg"))
                            .font(.system(size: 9))
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Toggle(tr("Vary days", "Varier dager"), isOn: $varyWeekdays)
                        .labelsHidden()
                        .tint(bronze)
                }
                .padding(.top, 5)
            }
        }
    }

    /// Reusable day button for Advanced. Both its visual state and the
    /// saved plan's weekdays read from the same selectedDays source.
    private func circularWeekday(
        _ day: (index: Int, en: String, no: String)
    ) -> some View {
        let selected = selectedDays.contains(day.index)
        let english = ["Monday", "Tuesday", "Wednesday", "Thursday",
                       "Friday", "Saturday", "Sunday"]
        let norwegian = ["Mandag", "Tirsdag", "Onsdag", "Torsdag",
                         "Fredag", "Lørdag", "Søndag"]

        return Button {
            onToggleDay(day.index)
        } label: {
            ZStack {
                Circle()
                    .fill(selected
                          ? ATHLTHTrainDesign.paleGold.opacity(0.74)
                          : canvas.opacity(0.74))
                Circle()
                    .strokeBorder(
                        selected ? bronze : border.opacity(0.52),
                        lineWidth: selected ? 2.4 : 1.2
                    )
                Circle()
                    .strokeBorder(.white.opacity(selected ? 0.96 : 0.75),
                                  lineWidth: 1.7)
                    .padding(4)

                Text(tr(day.en, day.no))
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? ink : muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 3)
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(bronze, in: Circle())
                        .overlay {
                            Circle().strokeBorder(.white, lineWidth: 1.2)
                        }
                        .offset(x: 2, y: -3)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(english[day.index - 1], norwegian[day.index - 1]))
        .accessibilityValue(selected
            ? tr("Training day", "Treningsdag")
            : tr("Not selected", "Ikke valgt"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var startCard: some View {
        card {
            cardHeading("calendar", tr("Start date", "Startdato"))
            if advanced {
                DatePicker(tr("Start date", "Startdato"),
                           selection: $startDate,
                           in: Calendar.current.startOfDay(for: .now)...,
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(bronze)
                    .font(.system(size: 11))
            } else {
                HStack {
                    Text(tr("Today", "I dag"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundStyle(muted)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var durationCard: some View {
        card {
            cardHeading("hourglass", tr("Duration", "Varighet"))
            HStack(spacing: 3) {
                ForEach([4, 8, 12], id: \.self) { value in
                    Button { weekCount = value; customWeekCount = false } label: {
                        VStack(spacing: 2) {
                            Text("\(value)").font(.system(size: 12))
                            Text(tr("weeks", "uker")).font(.system(size: 9))
                        }
                        .foregroundStyle(weekCount == value ? .white : ink)
                        .frame(maxWidth: .infinity, minHeight: 41)
                        .background(weekCount == value ? bronze : canvas,
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    ForEach(1...52, id: \.self) { amount in
                        Button(tr("\(amount) weeks", "\(amount) uker")) {
                            weekCount = amount
                            customWeekCount = true
                        }
                    }
                } label: {
                    Text(([4,8,12].contains(weekCount) && !customWeekCount)
                         ? tr("Custom", "Egendef.")
                         : "\(weekCount) " + tr("weeks", "uker"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle((customWeekCount || ![4,8,12].contains(weekCount))
                                         ? .white : ink)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 41)
                        .background((customWeekCount || ![4,8,12].contains(weekCount))
                                    ? bronze : canvas,
                                    in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }
}

