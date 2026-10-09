import SwiftUI

/// A new read-only progress surface over preserved workout history.
/// Planned and performed sessions are always kept distinct.
struct ATHLTHTrainProgressPremiumView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let onOpenPlan: () -> Void

    @State private var showingDetailedAnalysis = false
    @State private var showingGoals = false
    @State private var showingTrends = false
    @State private var showingCoach = false

    private let ink = Color(red: 0.18, green: 0.18, blue: 0.17)
    private let muted = Color(red: 0.46, green: 0.45, blue: 0.43)
    private let champagne = Color(red: 0.65, green: 0.53, blue: 0.35)
    private let hairline = Color(red: 0.89, green: 0.87, blue: 0.84)
    private let warm = Color(red: 0.965, green: 0.950, blue: 0.925)

    private var plan: TrainingPlan? { session.activePlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("THE WORK BEHIND THE RESULTS", "VEIEN MOT MÅLET"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(champagne)
                Text(tr("Progress", "Fremgang"))
                    .font(.system(size: 35, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Text(tr(
                    "Follow what you planned, what you actually trained, and how far you've come.",
                    "Se forskjellen på det du planla, det du gjennomførte og hva du har oppnådd."
                ))
                .font(.subheadline)
                .foregroundStyle(muted)
            }

            if let plan {
                progressContent(for: plan)
            } else {
                noPlanContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingDetailedAnalysis) {
            if let plan {
                TrainingPlanProgressDetailView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingGoals) {
            if let plan {
                ATHLTHTrainGoalHubView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingTrends) {
            if let plan {
                ATHLTHTrainTrendsView(planID: plan.id)
            }
        }
        .sheet(isPresented: $showingCoach) {
            if let plan {
                ATHLTHTrainProgressionCoachView(planID: plan.id)
            }
        }
    }

    private func progressContent(for plan: TrainingPlan) -> some View {
        let snapshot = session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let planned = snapshot.totalSessions
        let finished = min(max(snapshot.completedSessions, 0), planned)
        let skipped = snapshot.skippedSessions
        let fraction = snapshot.completionFraction

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("ACTIVE PROGRAM", "AKTIVT PROGRAM"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(champagne)
                Text(plan.title)
                    .font(.system(size: 27, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((fraction * 100).rounded()))")
                        .font(.system(size: 57, weight: .light, design: .rounded))
                        .foregroundStyle(ink)
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(muted)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(finished) / \(planned)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(tr("completed workouts", "gjennomførte økter"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                }
                GeometryReader { geometry in
                    Capsule()
                        .fill(hairline.opacity(0.65))
                        .overlay(alignment: .leading) {
                            Capsule().fill(champagne)
                                .frame(width: geometry.size.width * fraction)
                        }
                }
                .frame(height: 7)

                HStack(spacing: 0) {
                    stat(tr("PLANNED", "PLANLAGT"), value: "\(planned)")
                    Rectangle().fill(hairline).frame(width: 0.7, height: 39)
                    stat(tr("PERFORMED", "GJENNOMFØRT"), value: "\(finished)")
                    Rectangle().fill(hairline).frame(width: 0.7, height: 39)
                    stat(tr("SKIPPED", "HOPPET OVER"), value: "\(skipped)")
                }
                .padding(.top, 5)
            }
            .padding(18)
            .freshProgressSurface(line: hairline)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("TRAINING BY WEEK", "TRENING UKE FOR UKE"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(champagne)
                    Spacer()
                    Text(tr("Actual / Planned", "Utført / Planlagt"))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, week in
                        let workouts = week.days.flatMap(\.sessions)
                        let done = workouts.filter {
                            session.isPlanSessionCompleted(
                                planID: plan.id,
                                sessionID: $0.id,
                                healthWorkouts: health.workouts,
                                strengthHistory: strength.workoutHistory
                            )
                        }.count
                        VStack(spacing: 6) {
                            GeometryReader { proxy in
                                let height = max(proxy.size.height, 1)
                                let full = CGFloat(workouts.count) /
                                    CGFloat(max(maxSessionsPerWeek(plan), 1)) * height
                                let performed = CGFloat(done) /
                                    CGFloat(max(maxSessionsPerWeek(plan), 1)) * height
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(warm)
                                        .frame(height: full)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(champagne)
                                        .frame(height: performed)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .bottom)
                            }
                            .frame(height: 95)
                            Text("\(index + 1)")
                                .font(.system(size: 9))
                                .foregroundStyle(muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if plan.weeks.count > 9 {
                    Text(tr("Weeks are shown in order. Scroll for additional detail in analysis.",
                            "Uker vises i rekkefølge. Åpne analyse for mer detaljer."))
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
            }
            .padding(15)
            .freshProgressSurface(line: hairline)

            if !snapshot.missed.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr("Workouts to review", "Økter som trenger oppfølging"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr(
                            "\(snapshot.missed.count) planned sessions were not completed. You decide whether to move or skip them.",
                            "\(snapshot.missed.count) tidligere planlagte økter mangler. Du bestemmer om de skal flyttes eller hoppes over."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(15)
                .freshProgressSurface(line: hairline)
            }

            Button {
                showingCoach = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Progression suggestions", "Forslag til progresjon"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Optional adjustments based on logged training",
                                "Valgfrie endringer basert på gjennomført trening"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(ink)
                .padding(15)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)

            Button {
                showingTrends = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Exercise and volume trends", "Øvelser og treningsutvikling"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Actual loads, working sets and progress toward goals",
                                "Arbeidsvekter, sett og utvikling mot treningsmål"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(ink)
                .padding(15)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)

            Button {
                showingGoals = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Goals and training blocks", "Mål og treningsblokker"))
                            .font(.subheadline.weight(.semibold))
                        Text(tr("Planned vs. completed – with real evidence",
                                "Planlagt og utført – med faktiske resultater"))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption)
                }
                .foregroundStyle(ink)
                .padding(15)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)

            Button {
                showingDetailedAnalysis = true
            } label: {
                HStack {
                    Spacer()
                    Text(tr("Detailed analysis", "Detaljert treningsanalyse"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(15)
                .background(ink, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button(action: onOpenPlan) {
                HStack {
                    Text(tr("Back to training plan", "Tilbake til treningsplan"))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ink)
                .padding(14)
                .freshProgressSurface(line: hairline)
            }
            .buttonStyle(.plain)
        }
    }

    private var noPlanContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(champagne)
            Text(tr("Progress begins with a plan", "Fremgang starter med en plan"))
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(ink)
            Text(tr("Create a plan to follow your program and compare planned sessions with actual training.",
                    "Opprett en plan for å følge treningsutviklingen og sammenligne planlagt med faktisk trening."))
                .font(.subheadline)
                .foregroundStyle(muted)
            Button(action: onOpenPlan) {
                Label(tr("Open Plan", "Gå til Plan"), systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
            }
            .buttonStyle(.plain)
            .padding(.top, 7)
        }
        .padding(18)
        .freshProgressSurface(line: hairline)
    }

    private func maxSessionsPerWeek(_ plan: TrainingPlan) -> Int {
        plan.weeks.map {
            $0.days.reduce(0) { result, day in
                result + day.sessions.count
            }
        }.max() ?? 0
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 23, weight: .regular, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension View {
    func freshProgressSurface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(line, lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.03), radius: 9, y: 4)
    }
}
