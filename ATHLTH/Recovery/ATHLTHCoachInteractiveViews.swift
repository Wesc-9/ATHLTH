import SwiftUI

/// The disclosure state belongs to the athlete, not the view lifecycle.
/// Opening Today's Insight once keeps it open after navigating away/back.
struct ATHLTHCoachInsightDisclosure<Content: View>: View {
    let userID: UUID
    let summary: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    private var storageKey: String {
        "athlth.coach.insightExpanded.\(userID.uuidString)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.23)) {
                    expanded.toggle()
                }
                UserDefaults.standard.set(expanded, forKey: storageKey)
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "TODAY'S INSIGHT", norwegian: "DAGENS INNSIKT"
                        ))
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                .padding(15)
                .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 19))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Today's insight, expand or collapse",
                norwegian: "Dagens innsikt, utvid eller trekk sammen"
            ))
            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            expanded = UserDefaults.standard.bool(forKey: storageKey)
        }
    }
}

enum ATHLTHCoachQuickAction: String, CaseIterable, Identifiable {
    case createWorkout
    case postponeWorkout
    case createPlan
    case reviewProgress

    var id: String { rawValue }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var title: String {
        switch self {
        case .createWorkout: return tr("Plan a workout", "Planlegg en økt")
        case .postponeWorkout: return tr("Postpone a workout", "Utsett en økt")
        case .createPlan: return tr("Create a plan", "Lag treningsplan")
        case .reviewProgress: return tr("Review progress", "Analyser fremgang")
        }
    }

    var symbol: String {
        switch self {
        case .createWorkout: return "dumbbell.fill"
        case .postponeWorkout: return "calendar.badge.clock"
        case .createPlan: return "calendar"
        case .reviewProgress: return "chart.line.uptrend.xyaxis"
        }
    }

    var prompt: String {
        switch self {
        case .createWorkout:
            return tr(
                "Help me create a new workout. First ask about training type, duration, equipment and experience, then suggest a session I can add.",
                "Hjelp meg å lage en ny treningsøkt. Spør først om type, varighet, utstyr og erfaring, og foreslå så en økt jeg kan legge til."
            )
        case .postponeWorkout:
            return tr(
                "Postpone my planned workout. Ask which session and new date I want, and show the changes for approval before saving.",
                "Utsett den planlagte økten min. Spør hvilken økt og ny dato jeg ønsker, og vis endringene for godkjenning før lagring."
            )
        case .createPlan:
            return tr(
                "Help me create a training plan. Ask about my goals, training days, experience and equipment before proposing a plan.",
                "Hjelp meg å lage en treningsplan. Spør om mål, treningsdager, erfaring og utstyr før du foreslår en plan."
            )
        case .reviewProgress:
            return tr(
                "Help me review my training progress. Ask what information you need and let me choose what data to share.",
                "Hjelp meg å analysere treningsfremgangen min. Spør hvilke opplysninger du trenger, og la meg velge hva jeg vil dele."
            )
        }
    }
}

struct ATHLTHCoachStarterActions: View {
    let onSelect: (ATHLTHCoachQuickAction) -> Void
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ATHLTHLocalization.choose(
                english: "ASK COACH", norwegian: "SPØR COACH"
            ))
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            .padding(.horizontal, 14)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(ATHLTHCoachQuickAction.allCases) { action in
                    Button { onSelect(action) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 18)
                            Text(action.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.83)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .background(
                            .white.opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(ATHLTHPlanDesign.accentInk.opacity(0.11), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .accessibilityLabel(action.title)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 3)
    }
}

struct ATHLTHCoachProposalCard: View {
    let proposal: RecoveryCoachProposal
    let onAdd: () -> Void
    let onSave: () -> Void

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(
                    proposal.isWorkout ? tr("WORKOUT PROPOSAL", "ØKTFORSLAG") :
                        tr("TRAINING PLAN", "TRENINGSPLAN"),
                    systemImage: proposal.isWorkout ? "dumbbell.fill" : "calendar"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                .tracking(0.6)
                Spacer()
                Button(action: onSave) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    proposal.isWorkout ? tr("Save in My Workouts", "Lagre i Mine økter") :
                        tr("Save in My Plans", "Lagre i Mine planer")
                )
            }
            Text(proposal.title)
                .font(.headline)
                .foregroundStyle(ATHLTHPlanDesign.ink)
            if !proposal.summary.isEmpty {
                Text(proposal.summary)
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            HStack(spacing: 10) {
                Label("\(proposal.durationMinutes) min", systemImage: "clock")
                if proposal.isPlan {
                    Text("\(proposal.weekCount) " + tr("weeks", "uker"))
                    Text("\(proposal.sessionsPerWeek)" + tr(" / week", " / uke"))
                } else {
                    Text("\(proposal.steps.count) " + tr("parts", "deler"))
                }
            }
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            if proposal.isWorkout {
                ForEach(Array(proposal.steps.prefix(5).enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text(step.title)
                            .lineLimit(1)
                        Spacer(minLength: 5)
                        Text(step.sets > 0 ? "\(step.sets) × \(step.repetitions)" :
                             "\(step.minutes) min")
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    .font(.caption)
                }
                if proposal.steps.count > 5 {
                    Text("+ \(proposal.steps.count - 5) " + tr("more", "til"))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            Button(action: onAdd) {
                Label(tr("Add", "Legg til"), systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ATHLTHPlanDesign.accentInk)
            Text(tr(
                "Review before adding. You choose your own pace and working weights.",
                "Gjennomgå før du legger til. Du bestemmer selv fart og treningsvekter."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(14)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ATHLTHPlanDesign.accentInk.opacity(0.18), lineWidth: 1)
        }
    }
}
