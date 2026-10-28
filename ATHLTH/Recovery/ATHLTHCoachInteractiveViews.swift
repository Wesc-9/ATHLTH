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

struct ATHLTHCoachStarterActions: View {
    let onPrompt: (String) -> Void

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("What can I help you with?", "Hva kan jeg hjelpe deg med?"))
                .font(.headline)
                .foregroundStyle(ATHLTHPlanDesign.ink)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                action(tr("Create a workout", "Lag en økt"), symbol: "dumbbell.fill",
                       prompt: tr("Help me create a workout. Ask me for the training type, duration, equipment and level first.",
                                  "Hjelp meg å lage en treningsøkt. Spør først om type, varighet, utstyr og nivå."))
                action(tr("Create a plan", "Lag treningsplan"), symbol: "calendar",
                       prompt: tr("Help me create a training plan. Ask about my goal, available days, experience and equipment.",
                                  "Hjelp meg å lage en treningsplan. Spør om mål, treningsdager, erfaring og utstyr."))
                action(tr("Review progress", "Analyser fremgang"), symbol: "chart.line.uptrend.xyaxis",
                       prompt: tr("What training-history data should I share for a meaningful progress review?",
                                  "Hvilke treningsdata trenger du tilgang til for å analysere fremgangen min?"))
                action(tr("Ask about training", "Spør om trening"), symbol: "book.closed",
                       prompt: tr("How can I balance strength training and running in a week?",
                                  "Hvordan kan jeg balansere styrke og løping i løpet av en uke?"))
            }
        }
        .padding(.vertical, 6)
    }

    private func action(_ title: String, symbol: String, prompt: String) -> some View {
        Button { onPrompt(prompt) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
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

struct ATHLTHCoachHealthSourcesView: View {
    let context: RecoveryAIContext

    private func label(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func entry(_ name: String, _ timestamp: String?, available: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: available ? "checkmark.circle" : "clock.badge.questionmark")
                .foregroundStyle(available ? ATHLTHPlanDesign.accentInk :
                                    ATHLTHPlanDesign.secondaryInk)
            Text(name)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 8)
            if available, let timestamp,
               let when = ISO8601DateFormatter().date(from: timestamp) {
                Text(when.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                Text(label("No recent sample", "Ingen nyere måling"))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label("MEASUREMENT SOURCES", "MÅLEKILDER"),
                  systemImage: "checkmark.shield")
                .font(.caption2.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            entry(label("Sleep", "Søvn"),
                  context.evidence?.sleepEndedAt,
                  available: context.sleepSeconds != nil)
            entry("HRV", context.evidence?.hrvSampledAt,
                  available: context.hrvMilliseconds != nil)
            entry(label("Resting heart rate", "Hvilepuls"),
                  context.evidence?.restingPulseSampledAt,
                  available: context.restingHeartRate != nil)
            Text(label(
                "Measurements from Apple Health. Readiness is an estimate, not a direct measurement. Missing or outdated values are excluded from Coach.",
                "Målinger hentet via Apple Helse. Dagsform er en beregning, ikke en direkte måling. Manglende eller utdaterte verdier utelates fra Coach."
            ))
            .font(.caption2)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(14)
        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 17))
    }
}
