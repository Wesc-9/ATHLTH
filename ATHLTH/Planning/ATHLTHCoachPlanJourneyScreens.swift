import SwiftUI

/// Presentation-only components for the Coach-created training plan journey.
/// The real data, AI request, validation, draft editor and commit stay in
/// AIProgramBuilderView / AIProgramService; none of these screens fabricate a plan.
struct ATHLTHCoachPlanWelcomeScreen: View {
    let onContinue: () -> Void
    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { bounds in
                    Image("PlanGoalHero")
                        .resizable()
                        .scaledToFill()
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                }
                LinearGradient(
                    colors: [.clear, ATHLTHTrainDesign.canvas.opacity(0.15),
                             ATHLTHTrainDesign.canvas],
                    startPoint: .center, endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("MADE FOR YOU", "LAGET FOR DEG"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.5).foregroundStyle(muted)
                    Text(tr("A plan built\nfor you", "En plan bygget\nfor deg"))
                        .font(.system(size: 37, weight: .regular, design: .serif))
                        .tracking(-0.6)
                        .foregroundStyle(ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(tr(
                        "Tell us about your training, everyday life and preferences. ATHLTH Coach creates a plan you can inspect and change before saving.",
                        "Fortell om dine mål, din hverdag og dine preferanser. ATHLTH Coach lager en plan du kan gjennomgå og endre før lagring."
                    ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .frame(height: 360)
            .clipped()
            .background(ATHLTHTrainDesign.canvas)

            benefit("person.crop.circle", tr("Personal and realistic", "Personlig og realistisk"),
                    tr("Built around your goals, experience and availability",
                       "Basert på dine mål, erfaring og tilgjengelige dager"))
            benefit("chart.line.uptrend.xyaxis", tr("Balanced progression", "Balanse og progresjon"),
                    tr("An appropriate mix of training and recovery",
                       "En god balanse mellom trening og restitusjon"))
            benefit("slider.horizontal.3", tr("Your plan, your choices", "Enkel å justere"),
                    tr("Edit individual workouts or ask Coach to regenerate",
                       "Rediger økter selv eller be Coach om et nytt forslag"))

            bronzeButton(tr("Get started", "Kom i gang"), systemImage: "arrow.right",
                         action: onContinue)
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(bronze)
                .frame(width: 40, height: 40)
                .background(ATHLTHTrainDesign.paleGold.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                Text(subtitle).font(.system(size: 10.5))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 15))
    }
}

struct ATHLTHCoachPlanGeneratingScreen: View {
    private let bronze = ATHLTHTrainDesign.bronze
    private let muted = ATHLTHTrainDesign.secondary

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(spacing: 23) {
            Spacer(minLength: 22)
            Text("ATHLTH COACH")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.8)
                .foregroundStyle(muted)
            Text(tr("Coach is building\nyour plan", "Coach lager\ntreningsplanen din"))
                .font(.system(size: 32, weight: .regular, design: .serif))
                .multilineTextAlignment(.center)
            Text(tr("We are using the goals and preferences you chose. No plan is saved until you approve it.",
                    "Vi bruker målene og valgene dine. Ingen plan lagres før du godkjenner forslaget."))
                .font(.system(size: 12.5))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 19)

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.99, green: 0.92, blue: 0.72),
                                 Color(red: 0.79, green: 0.57, blue: 0.29), .clear],
                        center: .center, startRadius: 7, endRadius: 115))
                    .frame(width: 230, height: 230)
                Circle()
                    .strokeBorder(bronze.opacity(0.25), lineWidth: 1)
                    .frame(width: 165, height: 165)
                Image(systemName: "sparkles")
                    .font(.system(size: 43, weight: .ultraLight))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(bronze)
                    .offset(y: 112)
                    .accessibilityLabel(tr("Generating training plan", "Genererer treningsplan"))
            }
            .frame(height: 248)

            VStack(alignment: .leading, spacing: 14) {
                status("target", tr("Goals and available days", "Mål og treningsdager"))
                status("calendar", tr("Periodization and progression", "Periodisering og progresjon"))
                status("dumbbell", tr("Workouts and exercises", "Økter og øvelser"))
                status("leaf", tr("Recovery and balance", "Restitusjon og balanse"))
            }
            .padding(15)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 19))
            .accessibilityLabel(tr("Coach is preparing the draft", "Coach utarbeider planforslaget"))
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func status(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).foregroundStyle(bronze)
                .frame(width: 24)
            Text(title).font(.system(size: 12))
            Spacer()
            Image(systemName: "circle.dotted")
                .font(.caption).foregroundStyle(muted)
        }
    }
}

/// A read-only projection of the ACTUAL validated AI draft.
struct ATHLTHCoachPlanDraftScreen: View {
    let draft: AIProgramDraft
    let startDate: Date
    @Binding var selectedWeek: Int
    let onEditWorkout: (Int, Int, Int) -> Void
    let onRegenerate: () -> Void
    let onApprove: () -> Void

    private let ink = ATHLTHTrainDesign.ink
    private let muted = ATHLTHTrainDesign.secondary
    private let bronze = ATHLTHTrainDesign.bronze
    private let canvas = ATHLTHTrainDesign.canvas

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var chosenWeek: AIProgramDraftWeek? {
        draft.weeks.first(where: { $0.weekNumber == selectedWeek }) ?? draft.weeks.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("FROM ATHLTH COACH", "FORSLAG FRA COACH"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2).foregroundStyle(muted)
                    Text(tr("Your training plan", "Din treningsplan"))
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 21)).foregroundStyle(bronze)
            }

            Text(draft.summary)
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                summary(tr("Weeks", "Uker"), "\(draft.weeks.count)", "calendar")
                summary(tr("Workouts", "Økter"), "\(draft.sessionCount)", "dumbbell")
                summary(tr("First day", "Første dag"),
                        startDate.formatted(.dateTime.day().month(.abbreviated)), "clock")
            }
            HStack {
                Text(tr("Week", "Uke") + " \(selectedWeek)")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Spacer()
                Button { selectedWeek = max(1, selectedWeek - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 29, height: 32)
                }
                .disabled(selectedWeek <= 1)
                Text("\(selectedWeek) / \(draft.weeks.count)")
                    .font(.caption.monospacedDigit())
                Button { selectedWeek = min(draft.weeks.count, selectedWeek + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 29, height: 32)
                }
                .disabled(selectedWeek >= draft.weeks.count)
            }
            .buttonStyle(.plain)
            .foregroundStyle(bronze)

            if let chosenWeek {
                Text(chosenWeek.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(muted)

                ForEach(chosenWeek.days.sorted(by: { $0.dayIndex < $1.dayIndex }), id: \.dayIndex) { day in
                    dayCard(day, week: chosenWeek.weekNumber)
                }
            }

            Text(tr("Check each week and change any workout before approving. Coach never activates a plan without your confirmation.",
                    "Se gjennom ukene og rediger øktene før du godkjenner. Coach aktiverer aldri en plan uten bekreftelse."))
                .font(.system(size: 10.5))
                .foregroundStyle(muted)
                .padding(.vertical, 3)

            HStack(spacing: 9) {
                Button(action: onRegenerate) {
                    Label(tr("Regenerate", "Generer på nytt"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(bronze)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)

                bronzeButton(tr("This plan works for me", "Denne planen passer"),
                             systemImage: "arrow.right", action: onApprove)
            }
        }
    }

    private func summary(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(bronze)
                .font(.system(size: 17))
            Text(value).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, minHeight: 75)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
    }

    private func dayCard(_ day: AIProgramDraftDay, week: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(day.title)
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                Spacer()
                if day.sessions.isEmpty {
                    Text(tr("Rest day", "Hviledag"))
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
            }
            ForEach(day.sessions.indices, id: \.self) { index in
                let workout = day.sessions[index]
                Button {
                    onEditWorkout(week, day.dayIndex, index)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: WorkoutKind(rawValue: workout.kind)?.systemImage ?? "figure.run")
                            .font(.system(size: 14))
                            .foregroundStyle(bronze)
                            .frame(width: 30, height: 32)
                            .background(ATHLTHTrainDesign.paleGold.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ink)
                            Text([
                                workout.durationMinutes.map { "\($0) min" },
                                workout.exercises.isEmpty ? nil :
                                    "\(workout.exercises.count) " +
                                    tr("exercises", "øvelser")
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 10))
                                .foregroundStyle(muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "pencil")
                            .font(.system(size: 12)).foregroundStyle(bronze)
                    }
                    .padding(8)
                    .background(canvas.opacity(0.85), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Only shown after the existing session store accepts the generated plan.
struct ATHLTHCoachPlanReadyScreen: View {
    let plan: TrainingPlan
    let onOpenPlan: () -> Void

    private let bronze = ATHLTHTrainDesign.bronze
    private let muted = ATHLTHTrainDesign.secondary
    private let ink = ATHLTHTrainDesign.ink

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(spacing: 17) {
            Spacer(minLength: 27)
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [Color(red: 1.0, green: 0.94, blue: 0.78),
                             Color(red: 0.75, green: 0.53, blue: 0.27),
                             .clear],
                    center: .center, startRadius: 0, endRadius: 94))
                    .frame(width: 192, height: 192)
                Image(systemName: "checkmark")
                    .font(.system(size: 37, weight: .medium))
                    .foregroundStyle(.white)
            }
            Text(tr("Your plan is ready!", "Planen din er klar!"))
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(tr("The plan has been saved. You can open it and make changes at any time.",
                    "Treningsplanen er lagret. Du kan åpne den og gjøre endringer når du ønsker."))
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(muted)
            VStack(alignment: .leading, spacing: 14) {
                fact("target", tr("Plan", "Plan"), plan.title)
                fact("calendar", tr("Duration", "Varighet"),
                     "\(plan.weeks.count) " + tr("weeks", "uker"))
                fact("dumbbell", tr("Workouts", "Treningsøkter"),
                     "\(plan.weeks.reduce(0) { $0 + $1.days.reduce(0) { $0 + $1.sessions.count } })")
                if let start = plan.startDate {
                    fact("calendar.badge.clock", tr("Start", "Start"),
                         start.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding(15)
            .background(.white, in: RoundedRectangle(cornerRadius: 19))
            Spacer(minLength: 16)
            bronzeButton(tr("Open your plan", "Se hele planen"),
                         systemImage: "arrow.right", action: onOpenPlan)
        }
        .frame(maxWidth: .infinity)
    }

    private func fact(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(bronze)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 10)).foregroundStyle(muted)
                Text(value).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
            }
            Spacer()
        }
    }
}

private func bronzeButton(_ title: String, systemImage: String,
                          action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            Spacer(minLength: 0)
            Text(title).font(.system(size: 13.5, weight: .semibold))
            Spacer(minLength: 8)
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            LinearGradient(
                colors: [ATHLTHTrainDesign.bronze,
                         Color(red: 0.68, green: 0.49, blue: 0.26)],
                startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 17))
    }
    .buttonStyle(.plain)
}
