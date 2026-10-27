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
            varyWeekdays: .constant(false),
            onToggleDay: onToggleDay,
            onCreateGoal: onCreateGoal,
            onModeChange: { isAdvanced in
                if isAdvanced { onSelectAdvanced() }
            }
        )
    }
}

/// Reusable, fully rebuilt visual contract for plan setup.
/// The wrappers are thin mode entry points, not legacy layouts stacked together.
struct ATHLTHPlanSetupFields: View {
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var weekCount: Int
    @Binding var linkedGoalIDs: Set<UUID>
    let selectedDays: Set<Int>
    let goals: [ATHLTHGoal]
    let suggestedName: String
    let advanced: Bool
    @Binding var varyWeekdays: Bool
    let onToggleDay: (Int) -> Void
    let onCreateGoal: () -> Void
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
            // Deliberately small switch, outside all data cards.
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    modeTab(false, title: tr("Simple", "Enkel"))
                    modeTab(true, title: tr("Advanced", "Avansert"))
                }
                .padding(3)
                .frame(width: 188)
                .background(.white.opacity(0.75), in: Capsule())
            }
            .padding(.bottom, 1)

            hero
            nameCard
            if !advanced {
                goalsCard
                daysCard
                startCard
            } else {
                daysCard
                goalsCard
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 10) { startCard; durationCard }
                } else {
                    HStack(alignment: .top, spacing: 9) {
                        startCard
                        durationCard
                    }
                }
            }
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
    }

    private func modeTab(_ isAdvanced: Bool, title: String) -> some View {
        Button { onModeChange(isAdvanced) } label: {
            Text(title)
                .font(.system(size: 11, weight: advanced == isAdvanced ? .semibold : .medium))
                .foregroundStyle(advanced == isAdvanced ? .white : ink)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(advanced == isAdvanced ? bronze : .clear,
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(advanced == isAdvanced ? .isSelected : [])
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geometry in
                Image(advanced ? "PlanEntryAdvanced" : "PlanEntrySimple")
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.99), location: 0.29),
                    .init(color: canvas.opacity(0.85), location: 0.53),
                    .init(color: canvas.opacity(0.05), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(muted)
                Text(advanced ? tr("Build your plan\nin detail", "Bygg planen\nmer detaljert")
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
        }
        .frame(height: typeSize.isAccessibilitySize ? 196 : 151)
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
            cardHeading("pencil", tr("Plan name", "Navn på planen"))
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
            if advanced {
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
