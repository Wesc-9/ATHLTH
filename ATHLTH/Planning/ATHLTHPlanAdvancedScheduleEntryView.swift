import SwiftUI

/// Step three of the advanced training-plan journey.
/// The view intentionally receives existing builder state rather than storing
/// a parallel plan. Basic mode continues using its original short questionnaire.
struct ATHLTHPlanAdvancedScheduleEntryView: View {
    @Binding var startDate: Date
    @Binding var weekCount: Int

    let selectedDays: Set<Int>
    let minutesPerSession: Int
    let onSelectFrequency: (Int) -> Void
    let onSelectMinutes: (Int) -> Void
    let onToggleDay: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingExampleWeek = false

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let gold = ATHLTHTrainDesign.gold
    private let canvas = ATHLTHTrainDesign.canvas
    private let rule = ATHLTHTrainDesign.rule

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private let weekdays: [(Int, String, String)] = [
        (1, "Mon", "Man"), (2, "Tue", "Tir"), (3, "Wed", "Ons"),
        (4, "Thu", "Tor"), (5, "Fri", "Fre"), (6, "Sat", "Lør"),
        (7, "Sun", "Søn")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            hero
            frequencyCard
            durationCard

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    startDateCard
                    planLengthCard
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    startDateCard
                    planLengthCard
                }
            }

            weekdaysCard
            overviewCard
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
        .sheet(isPresented: $showingExampleWeek) {
            NavigationStack {
                List {
                    Section {
                        ForEach(0..<weekdays.count, id: \.self) { index in
                            let weekday = weekdays[index]
                            HStack(spacing: 12) {
                                Image(systemName: selectedDays.contains(weekday.0)
                                      ? "figure.run" : "moon.stars")
                                    .foregroundStyle(selectedDays.contains(weekday.0)
                                                     ? bronze : muted)
                                    .frame(width: 26)
                                Text(tr(weekday.1, weekday.2))
                                Spacer()
                                Text(selectedDays.contains(weekday.0)
                                     ? tr("Workout", "Treningsøkt")
                                     : tr("Rest day", "Hviledag"))
                                    .foregroundStyle(muted)
                            }
                        }
                    } header: {
                        Text(tr("Example week", "Eksempeluke"))
                    } footer: {
                        Text(tr(
                            "These are your planned training days. The detailed sessions are added later.",
                            "Dette er dagene du har valgt. De detaljerte øktene bygger du senere."
                        ))
                    }
                }
                .scrollContentBackground(.hidden)
                .background(canvas)
                .navigationTitle(tr("Your week", "Din uke"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done", "Ferdig")) {
                            showingExampleWeek = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { bounds in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image("PlanScheduleHero")
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width * 0.69,
                               height: bounds.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }
            }

            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.99), location: 0.28),
                    .init(color: canvas.opacity(0.90), location: 0.45),
                    .init(color: canvas.opacity(0.13), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(muted)
                Text(tr("How does training\nfit your life?",
                        "Hvordan passer\ntrening inn i livet ditt?"))
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 30 : 34,
                                  weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .lineSpacing(-2)
                    .minimumScaleFactor(0.73)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(tr("Choose a few boundaries and we'll build a plan for your everyday life.",
                        "Sett noen rammer, så bygger vi en plan som passer din hverdag."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 3)
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 40 : 90)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 185)
        .clipped()
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(.white.opacity(0.95),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(rule.opacity(0.42), lineWidth: 0.7)
            }
            .shadow(color: ink.opacity(0.045), radius: 10, y: 4)
    }

    private func sectionTitle(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(bronze)
                .frame(width: 38, height: 38)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.45),
                            in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func pill(_ value: String, selected: Bool) -> some View {
        Text(value)
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : ink)
            .lineLimit(1)
            .minimumScaleFactor(0.73)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                selected
                  ? LinearGradient(colors: [bronze, gold],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                  : LinearGradient(colors: [canvas, .white],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(rule.opacity(selected ? 0.14 : 0.65), lineWidth: 0.7)
            }
    }

    private var frequencyCard: some View {
        panel {
            sectionTitle("dumbbell", tr("How often do you want to train?",
                                        "Hvor ofte vil du trene?"),
                         tr("Sessions per week", "Antall økter per uke"))
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { number in
                    Button { onSelectFrequency(number) } label: {
                        pill("\(number)", selected: selectedDays.count == number)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("\(number) sessions per week",
                                            "\(number) økter per uke"))
                    .accessibilityAddTraits(selectedDays.count == number ? [.isSelected] : [])
                }
            }
        }
    }

    private var durationCard: some View {
        panel {
            sectionTitle("clock", tr("How long should each session be?",
                                     "Hvor lenge skal øktene være?"),
                         tr("Average session duration", "Gjennomsnittlig varighet per økt"))
            HStack(spacing: 5) {
                ForEach([30, 45, 60, 75, 90], id: \.self) { minutes in
                    Button { onSelectMinutes(minutes) } label: {
                        VStack(spacing: 1) {
                            pill("\(minutes)", selected: minutesPerSession == minutes)
                            Text(tr("min", "min"))
                                .font(.system(size: 9))
                                .foregroundStyle(muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("\(minutes) minutes", "\(minutes) minutter"))
                    .accessibilityAddTraits(minutesPerSession == minutes ? [.isSelected] : [])
                }
            }
            if ![30, 45, 60, 75, 90].contains(minutesPerSession) {
                Menu {
                    ForEach(Array(stride(from: 10, through: 180, by: 5)), id: \.self) { minutes in
                        Button("\(minutes) min") { onSelectMinutes(minutes) }
                    }
                } label: {
                    Label("\(minutesPerSession) min · " + tr("Custom duration", "Egen varighet"),
                          systemImage: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundStyle(bronze)
                }
            }
        }
    }

    private var startDateCard: some View {
        panel {
            sectionTitle("calendar", tr("When will you start?", "Når vil du starte?"),
                         tr("Start date", "Startdato"))
            DatePicker(
                tr("Start date", "Startdato"),
                selection: $startDate,
                in: Calendar.current.startOfDay(for: .now)...,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(bronze)
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(tr("Choose start date", "Velg startdato"))
        }
    }

    private var planLengthCard: some View {
        panel {
            sectionTitle("chart.bar", tr("For how long?", "Hvor lenge?"),
                         tr("Plan duration", "Planens varighet"))
            HStack(spacing: 4) {
                ForEach([4, 8, 12, 16], id: \.self) { count in
                    Button { weekCount = count } label: {
                        VStack(spacing: 2) {
                            Text("\(count)").font(.system(size: 12))
                            Text(tr("weeks", "uker")).font(.system(size: 9))
                        }
                        .foregroundStyle(weekCount == count ? Color.white : ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            weekCount == count ? bronze : canvas,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(rule.opacity(0.35), lineWidth: 0.6)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("\(count) weeks", "\(count) uker"))
                    .accessibilityAddTraits(weekCount == count ? [.isSelected] : [])
                }
            }
            if ![4, 8, 12, 16].contains(weekCount) {
                Menu {
                    ForEach(1...52, id: \.self) { count in
                        Button(tr("\(count) weeks", "\(count) uker")) { weekCount = count }
                    }
                } label: {
                    Text(tr("Custom: \(weekCount) weeks", "Egen: \(weekCount) uker"))
                        .font(.system(size: 10)).foregroundStyle(bronze)
                }
            }
        }
    }

    private var weekdaysCard: some View {
        panel {
            sectionTitle("calendar.badge.checkmark",
                         tr("Which days will you train?", "Hvilke dager vil du trene?"),
                         tr("Other days become rest days", "Resten settes som hviledager"))
            HStack(spacing: 5) {
                ForEach(0..<weekdays.count, id: \.self) { index in
                    let item = weekdays[index]
                    let chosen = selectedDays.contains(item.0)
                    Button { onToggleDay(item.0) } label: {
                        Text(tr(item.1, item.2))
                            .font(.system(size: 10, weight: chosen ? .semibold : .medium))
                            .foregroundStyle(chosen ? .white : ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 43)
                            .background(chosen ? bronze : canvas,
                                        in: Capsule())
                            .overlay {
                                Capsule().stroke(rule.opacity(chosen ? 0.10 : 0.55), lineWidth: 0.7)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? [.isSelected] : [])
                }
            }
            Text(tr("\(7 - selectedDays.count) rest days each week",
                    "\(7 - selectedDays.count) hviledager i uken"))
                .font(.system(size: 10.5))
                .foregroundStyle(muted)
        }
    }

    private var overviewCard: some View {
        panel {
            HStack {
                Label(tr("Your plan at a glance", "Din plan i korte trekk"),
                      systemImage: "chart.bar.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
                Button {
                    showingExampleWeek = true
                } label: {
                    HStack(spacing: 4) {
                        Text(tr("Example week", "Se eksempeluke"))
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(bronze)
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(rule.opacity(0.5)).frame(height: 0.6)
            HStack(spacing: 0) {
                overviewValue("calendar", "\(weekCount)", tr("weeks", "uker"))
                Rectangle().fill(rule.opacity(0.4)).frame(width: 0.6, height: 46)
                overviewValue("dumbbell", "\(selectedDays.count)", tr("per week", "per uke"))
                Rectangle().fill(rule.opacity(0.4)).frame(width: 0.6, height: 46)
                overviewValue("clock", "\(minutesPerSession)", "min")
                Rectangle().fill(rule.opacity(0.4)).frame(width: 0.6, height: 46)
                overviewValue("list.bullet", "\(weekCount * selectedDays.count)",
                              tr("total sessions", "totalt"))
            }
        }
    }

    private func overviewValue(_ symbol: String, _ value: String, _ suffix: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12)).foregroundStyle(bronze)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
            Text(suffix).font(.system(size: 9)).foregroundStyle(muted)
                .lineLimit(1).minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
