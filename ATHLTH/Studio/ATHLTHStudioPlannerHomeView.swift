import SwiftUI

/// The Plan Studio landing page is an editorial entry point, not a second plan
/// editor. All actions lead into the established ATHLTH planning/library flows.
/// Progress comes from explicitly completed planned workouts, never elapsed time.
struct ATHLTHStudioPlannerHomeView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let onOpenActivePlan: () -> Void
    let onCreatePlan: () -> Void
    let onOpenCoach: () -> Void
    let onOpenMyPlans: () -> Void
    let onExplorePlans: () -> Void
    let onFavoritePlans: () -> Void

    private let ink = ATHLTHStudioStyle.ink
    private let gold = ATHLTHStudioStyle.gold
    private let dark = Color(red: 0.105, green: 0.115, blue: 0.11)
    private let muted = Color(red: 0.63, green: 0.64, blue: 0.61)

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 860

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 22 : 30) {
                    editorialHeading(compact: compact)

                    if compact {
                        VStack(spacing: 18) {
                            activePlanCard
                                .frame(minHeight: 440)
                            rightColumn
                        }
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            activePlanCard
                                .frame(maxWidth: .infinity)
                                .frame(height: 528)

                            rightColumn
                                .frame(width: max(345, min(490, geometry.size.width * 0.39)))
                                .frame(height: 528)
                        }
                    }
                }
                .padding(.horizontal, compact ? 18 : 26)
                .padding(.top, compact ? 18 : 32)
                .padding(.bottom, 42)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
    }

    private func editorialHeading(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(gold)
                    .frame(width: 3, height: 30)
                    .accessibilityHidden(true)

                Text(ATHLTHLocalization.choose(
                    english: "YOUR TRAINING WORLD",
                    norwegian: "DITT TRENINGSUNIVERS"
                ))
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.3)
                .foregroundStyle(gold)
            }

            Text(ATHLTHLocalization.choose(
                english: "Build something that lasts.",
                norwegian: "Bygg noe som varer."
            ))
            .font(.system(
                size: compact ? 35 : 47,
                weight: .regular,
                design: .serif
            ))
            .tracking(-1.3)
            .foregroundStyle(ink)
            .minimumScaleFactor(0.85)
            .lineLimit(2)

            Text(ATHLTHLocalization.choose(
                english: "Plan, explore and develop your training — on your terms.",
                norwegian: "Planlegg, utforsk og utvikle treningen din – på dine premisser."
            ))
            .font(.system(size: 15))
            .foregroundStyle(ink.opacity(0.64))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var activePlanCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [dark, Color(red: 0.14, green: 0.155, blue: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Tonal contour lines replace decorative imagery and gradients.
            GeometryReader { geometry in
                Path { path in
                    for index in 0..<13 {
                        let y = CGFloat(index) * 23 + geometry.size.height * 0.13
                        path.move(to: CGPoint(x: geometry.size.width * 0.42, y: y))
                        path.addCurve(
                            to: CGPoint(x: geometry.size.width + 28, y: y + 18),
                            control1: CGPoint(x: geometry.size.width * 0.62, y: y - 28),
                            control2: CGPoint(x: geometry.size.width * 0.76, y: y + 40)
                        )
                    }
                }
                .stroke(.white.opacity(0.055), lineWidth: 1)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)

            if let plan = session.activePlan {
                activePlanContent(plan)
            } else {
                noActivePlanContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: dark.opacity(0.12), radius: 16, y: 9)
    }

    private func activePlanContent(_ plan: TrainingPlan) -> some View {
        let actual = ATHLTHPlanActualProgress.inspect(
            plan: plan,
            store: session,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let timing = session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let fraction = actual.totalPlanned > 0
            ? Double(actual.totalCompleted) / Double(actual.totalPlanned)
            : 0.0
        let percent = Int((fraction * 100).rounded())
        let weekNumber = timing.currentWeek
        let currentWeek = weekNumber > 0
            ? actual.weeks.first(where: { $0.number == weekNumber })
            : nil
        let next = nextScheduledWorkout(in: plan)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                statusPill(ATHLTHLocalization.choose(
                    english: "ACTIVE PLAN", norwegian: "AKTIV PLAN"
                ))
                Spacer(minLength: 6)
                if weekNumber > 0 && weekNumber <= plan.weeks.count {
                    Text(ATHLTHLocalization.choose(
                        english: "WEEK \(weekNumber) OF \(plan.weeks.count)",
                        norwegian: "UKE \(weekNumber) AV \(plan.weeks.count)"
                    ))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(muted)
                }
            }

            Text(plan.title)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(.top, 19)

            Text(weekNumber > 0
                 ? ATHLTHLocalization.choose(
                    english: "Your progress, one workout at a time.",
                    norwegian: "Fremgang, én treningsøkt om gangen."
                 )
                 : ATHLTHLocalization.choose(
                    english: "Your next training chapter is ready.",
                    norwegian: "Neste treningsperiode er klar."
                 ))
                .font(.subheadline)
                .foregroundStyle(muted)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ATHLTHLocalization.choose(
                        english: "COMPLETED WORKOUTS",
                        norwegian: "GJENNOMFØRTE ØKTER"
                    ))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(muted)

                    Spacer()

                    Text("\(percent) %")
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(gold)

                Text(ATHLTHLocalization.choose(
                    english: "\(actual.totalCompleted) of \(actual.totalPlanned) planned workouts completed",
                    norwegian: "\(actual.totalCompleted) av \(actual.totalPlanned) planlagte økter fullført"
                ))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(.top, 19)

            Rectangle()
                .fill(.white.opacity(0.13))
                .frame(height: 1)
                .padding(.vertical, 18)

            HStack(alignment: .top, spacing: 9) {
                metric(
                    label: ATHLTHLocalization.choose(english: "DURATION", norwegian: "VARIGHET"),
                    value: ATHLTHLocalization.choose(
                        english: "\(plan.weeks.count) weeks",
                        norwegian: "\(plan.weeks.count) uker"
                    )
                )
                metric(
                    label: ATHLTHLocalization.choose(english: "THIS WEEK", norwegian: "DENNE UKEN"),
                    value: currentWeek.map {
                        "\($0.completed) / \($0.planned)"
                    } ?? "–"
                )
                metric(
                    label: ATHLTHLocalization.choose(english: "REMAINING", norwegian: "GJENSTÅR"),
                    value: "\(max(0, actual.totalPlanned - actual.totalCompleted - actual.totalSkipped))"
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(gold)
                    .accessibilityHidden(true)
                Text(planPeriod(plan))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.72))
            .padding(.top, 14)

            if let next {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: next.session.kind.systemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(gold)
                        .frame(width: 31, height: 31)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "NEXT WORKOUT", norwegian: "NESTE ØKT"
                        ))
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(muted)

                        Text(next.session.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(next.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(10)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 14)
            }

            Spacer(minLength: 15)

            Button(action: onOpenActivePlan) {
                HStack(spacing: 32) {
                    Text(ATHLTHLocalization.choose(
                        english: "Open active plan", norwegian: "Åpne aktiv plan"
                    ))
                    .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(dark)
                .padding(.horizontal, 18)
                .frame(minHeight: 47)
                .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-studio-open-active-plan")
        }
        .padding(25)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var noActivePlanContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            statusPill(ATHLTHLocalization.choose(
                english: "YOUR NEXT CHAPTER", norwegian: "DIN NESTE PERIODE"
            ))

            Spacer()

            Text(ATHLTHLocalization.choose(
                english: "Make room for your next goal.",
                norwegian: "Gi plass til ditt neste mål."
            ))
            .font(.system(size: 38, weight: .regular, design: .serif))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)

            Text(ATHLTHLocalization.choose(
                english: "Choose one of your saved plans or create a new one.",
                norwegian: "Velg en av dine lagrede planer, eller opprett en ny."
            ))
            .font(.subheadline)
            .foregroundStyle(muted)

            Spacer()

            Button(action: onOpenMyPlans) {
                Label(
                    ATHLTHLocalization.choose(
                        english: "View my plans", norwegian: "Se mine planer"
                    ),
                    systemImage: "arrow.right"
                )
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(dark)
                .padding(.horizontal, 18)
                .frame(minHeight: 47)
                .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func statusPill(_ title: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(gold)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
        }
        .foregroundStyle(Color.white.opacity(0.84))
        .padding(.horizontal, 13)
        .frame(height: 30)
        .background(.white.opacity(0.11), in: Capsule())
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(value)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planPeriod(_ plan: TrainingPlan) -> String {
        guard let start = plan.startDate else {
            return ATHLTHLocalization.choose(
                english: "Start date not set", norwegian: "Startdato er ikke satt"
            )
        }
        let startText = start.formatted(.dateTime.day().month(.abbreviated).year())
        if let end = session.trainingPlanEndDate(plan) {
            return "\(startText) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
        return startText
    }

    /// Only real plan sessions with known dates are eligible. Do not invent
    /// an upcoming workout for a plan without a start date.
    private func nextScheduledWorkout(in plan: TrainingPlan)
        -> TrainingPlanSessionOccurrence? {
        let today = Calendar.current.startOfDay(for: .now)
        var candidates: [TrainingPlanSessionOccurrence] = []

        for (index, week) in plan.weeks.enumerated() {
            for day in week.days {
                let fallbackDate = ATHLTHStudioPlanWeekSummary.date(
                    for: day, inWeekIndex: index, planStart: plan.startDate
                )
                for workout in day.sessions where !workout.isExplicitRestDay {
                    guard let date = workout.scheduledStart ?? fallbackDate,
                          Calendar.current.startOfDay(for: date) >= today,
                          !session.isPlanSessionSkipped(
                            planID: plan.id, sessionID: workout.id
                          ),
                          !session.isPlanSessionCompleted(
                            planID: plan.id,
                            sessionID: workout.id,
                            healthWorkouts: health.workouts,
                            strengthHistory: strength.workoutHistory
                          )
                    else { continue }

                    candidates.append(TrainingPlanSessionOccurrence(
                        planID: plan.id,
                        session: workout,
                        date: date,
                        weekNumber: index + 1
                    ))
                }
            }
        }

        return candidates.min { $0.date < $1.date }
    }

    private var rightColumn: some View {
        VStack(spacing: 18) {
            createPlanPanel
            libraryPanel
        }
    }

    private var createPlanPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(gold)
                    .frame(width: 43, height: 43)
                    .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    sectionEyebrow(ATHLTHLocalization.choose(
                        english: "CREATE YOUR NEXT PLAN",
                        norwegian: "SKAP DIN NESTE PLAN"
                    ))
                    Text(ATHLTHLocalization.choose(
                        english: "Where to next?",
                        norwegian: "Hvor vil du videre?"
                    ))
                    .font(.system(size: 25, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(ink.opacity(0.11))
                .frame(height: 1)

            actionRow(
                "Opprett plan",
                english: "Create plan",
                trailing: ATHLTHLocalization.choose(
                    english: "Simple / Advanced", norwegian: "Enkel / Avansert"
                ),
                symbol: "plus",
                action: onCreatePlan
            )

            Rectangle()
                .fill(ink.opacity(0.09))
                .frame(height: 1)

            actionRow(
                "Lag med ATHLTH Coach",
                english: "Create with ATHLTH Coach",
                trailing: nil,
                symbol: "sparkles",
                action: onOpenCoach
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.93), in: RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .strokeBorder(ink.opacity(0.075), lineWidth: 1)
        }
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionEyebrow(ATHLTHLocalization.choose(
                    english: "YOUR PLAN LIBRARY",
                    norwegian: "DITT PLANBIBLIOTEK"
                ))

                Spacer()

                Text(ATHLTHLocalization.choose(
                    english: "03 OPTIONS", norwegian: "03 VALG"
                ))
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.bottom, 5)

            Rectangle()
                .fill(ink.opacity(0.11))
                .frame(height: 1)

            libraryRow(
                number: "01",
                title: ATHLTHLocalization.choose(
                    english: "My plans", norwegian: "Mine planer"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Your saved and editable plans",
                    norwegian: "Dine lagrede og redigerbare planer"
                ),
                action: onOpenMyPlans
            )

            Rectangle()
                .fill(ink.opacity(0.09))
                .frame(height: 1)

            libraryRow(
                number: "02",
                title: ATHLTHLocalization.choose(
                    english: "Explore plans", norwegian: "Utforsk planer"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Find a plan that suits you",
                    norwegian: "Finn en plan som passer deg"
                ),
                action: onExplorePlans
            )

            Rectangle()
                .fill(ink.opacity(0.09))
                .frame(height: 1)

            libraryRow(
                number: "03",
                title: ATHLTHLocalization.choose(
                    english: "Favorite plans", norwegian: "Favorittplaner"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Plans you have starred",
                    norwegian: "Planene du har stjernemerket"
                ),
                action: onFavoritePlans
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.93), in: RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .strokeBorder(ink.opacity(0.075), lineWidth: 1)
        }
    }

    private func sectionEyebrow(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(gold)
            .lineLimit(2)
    }

    private func actionRow(
        _ norwegian: String,
        english: String,
        trailing: String?,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(gold)
                    .frame(width: 29, height: 29)
                    .background(ATHLTHStudioStyle.canvas, in: Circle())

                Text(ATHLTHLocalization.choose(english: english, norwegian: norwegian))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .lineLimit(2)

                Spacer(minLength: 4)

                if let trailing {
                    Text(trailing)
                        .font(.caption2)
                        .foregroundStyle(ink.opacity(0.57))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gold)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func libraryRow(
        number: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 15) {
                Text(number)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(gold)
                    .frame(width: 25, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ink.opacity(0.57))
                        .lineLimit(2)
                }

                Spacer(minLength: 5)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(gold)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
