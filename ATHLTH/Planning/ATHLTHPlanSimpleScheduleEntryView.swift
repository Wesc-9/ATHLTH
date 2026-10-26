import SwiftUI

/// Lightweight, photo-led setup for Basic plans.
/// No session-duration selection: each planned workout can be edited separately
/// after the plan is created. All values come from the existing builder state.
struct ATHLTHPlanSimpleScheduleEntryView: View {
    @Binding var startDate: Date
    @Binding var weekCount: Int

    let selectedDays: Set<Int>
    let onSelectFrequency: (Int) -> Void
    let onToggleDay: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let gold = ATHLTHTrainDesign.gold
    private let canvas = ATHLTHTrainDesign.canvas
    private let rule = ATHLTHTrainDesign.rule

    private let weekdays: [(Int, String, String)] = [
        (1, "Mon", "Man"), (2, "Tue", "Tir"), (3, "Wed", "Ons"),
        (4, "Thu", "Tor"), (5, "Fri", "Fre"), (6, "Sat", "Lør"),
        (7, "Sun", "Søn")
    ]

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero
            frequencyCard

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 11) {
                    dateCard
                    weeksCard
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    dateCard
                    weeksCard
                }
            }

            weekdaysCard
            overviewCard
        }
        .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { bounds in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image("PlanGoalHero")
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width * 0.66, height: bounds.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }
            }
            LinearGradient(
                stops: [
                    .init(color: canvas, location: 0),
                    .init(color: canvas.opacity(0.99), location: 0.31),
                    .init(color: canvas.opacity(0.85), location: 0.49),
                    .init(color: canvas.opacity(0.07), location: 1)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 9) {
                Text(tr("BUILD YOUR PLAN", "BYGG DIN PLAN"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(muted)
                Text(tr("How does training\nfit your life?",
                        "Hvordan passer\ntrening inn i livet ditt?"))
                    .font(.system(
                        size: dynamicTypeSize.isAccessibilitySize ? 29 : 35,
                        weight: .regular, design: .serif
                    ))
                    .lineSpacing(-2)
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(tr("Set a few simple boundaries and we'll build a plan that fits your everyday life.",
                        "Sett noen enkle rammer, så bygger vi en plan som passer din hverdag."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 3)
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 38 : 93)
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 218 : 187)
        .clipped()
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Color.white.opacity(0.95),
                        in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(rule.opacity(0.42), lineWidth: 0.7)
            }
            .shadow(color: ink.opacity(0.04), radius: 9, y: 4)
    }

    private func cardTitle(_ systemName: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(bronze)
                .frame(width: 38, height: 38)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.5),
                            in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var frequencyCard: some View {
        panel {
            cardTitle("dumbbell", tr("How often do you want to train?",
                                    "Hvor ofte vil du trene?"),
                      tr("Sessions per week", "Antall økter per uke"))
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { count in
                    Button {
                        onSelectFrequency(count)
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 12, weight: count == selectedDays.count ? .semibold : .medium))
                            .foregroundStyle(count == selectedDays.count ? Color.white : ink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                count == selectedDays.count ? bronze : canvas,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(rule.opacity(0.4), lineWidth: 0.6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("\(count) sessions per week", "\(count) økter per uke"))
                    .accessibilityAddTraits(count == selectedDays.count ? [.isSelected] : [])
                }
            }
        }
    }

    private var dateCard: some View {
        panel {
            cardTitle("calendar", tr("When do you want to start?",
                                     "Når vil du starte?"),
                      tr("Start date", "Startdato"))
            DatePicker(tr("Start date", "Startdato"),
                       selection: $startDate,
                       in: Calendar.current.startOfDay(for: .now)...,
                       displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(bronze)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(tr("Choose start date", "Velg startdato"))
        }
    }

    private var weeksCard: some View {
        panel {
            cardTitle("chart.bar", tr("How many weeks?", "Hvor mange uker?"),
                      tr("Plan duration", "Planens varighet"))
            HStack(spacing: 4) {
                ForEach([4, 8, 12, 16], id: \.self) { count in
                    Button {
                        weekCount = count
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(count)").font(.system(size: 12, weight: .medium))
                            Text(tr("weeks", "uker")).font(.system(size: 9))
                        }
                        .foregroundStyle(weekCount == count ? .white : ink)
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .background(weekCount == count ? bronze : canvas,
                                    in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(rule.opacity(0.35), lineWidth: 0.65)
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
                        Button(tr("\(count) weeks", "\(count) uker")) {
                            weekCount = count
                        }
                    }
                } label: {
                    Text(tr("Custom: \(weekCount) weeks", "Egen: \(weekCount) uker"))
                        .font(.system(size: 10))
                        .foregroundStyle(bronze)
                }
            }
        }
    }

    private var weekdaysCard: some View {
        panel {
            cardTitle("calendar.badge.checkmark",
                      tr("Which days will you train?", "Hvilke dager vil du trene?"),
                      tr("Other days become rest days", "Resten settes som hviledager"))
            HStack(spacing: 5) {
                ForEach(weekdays.indices, id: \.self) { index in
                    let weekday = weekdays[index]
                    let chosen = selectedDays.contains(weekday.0)
                    Button {
                        onToggleDay(weekday.0)
                    } label: {
                        Text(tr(weekday.1, weekday.2))
                            .font(.system(size: 10, weight: chosen ? .semibold : .medium))
                            .foregroundStyle(chosen ? Color.white : ink)
                            .lineLimit(1).minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 43)
                            .background(chosen ? bronze : canvas, in: Capsule())
                            .overlay {
                                Capsule().stroke(rule.opacity(0.45), lineWidth: 0.6)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? [.isSelected] : [])
                }
            }
        }
    }

    private var overviewCard: some View {
        panel {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18)).foregroundStyle(bronze)
                    .frame(width: 35, height: 35)
                    .background(ATHLTHTrainDesign.paleGold.opacity(0.5), in: Circle())
                    .accessibilityHidden(true)
                Text(tr("Your plan at a glance", "Din plan i korte trekk"))
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
            }
            Rectangle().fill(rule.opacity(0.4)).frame(height: 0.6)
            HStack(spacing: 0) {
                overviewStat("calendar", "\(weekCount)", tr("weeks", "uker"))
                Rectangle().fill(rule.opacity(0.3)).frame(width: 0.7, height: 51)
                overviewStat("dumbbell", "\(selectedDays.count)", tr("per week", "per uke"))
                Rectangle().fill(rule.opacity(0.3)).frame(width: 0.7, height: 51)
                overviewStat("list.bullet", "\(weekCount * selectedDays.count)",
                             tr("total sessions", "økter totalt"))
            }
            Text(tr("Individual workout lengths can be adjusted later.",
                    "Varigheten på hver økt kan endres når du bygger den."))
                .font(.system(size: 10))
                .foregroundStyle(muted)
        }
    }

    private func overviewStat(_ icon: String, _ value: String, _ subtitle: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13)).foregroundStyle(bronze)
                .accessibilityHidden(true)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
