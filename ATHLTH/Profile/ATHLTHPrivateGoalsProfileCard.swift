import SwiftUI

/// Owner-only goal preview. The public/social profile never embeds this view.
/// Goals remain account-scoped locally; creating a goal defaults to private.
struct ATHLTHPrivateGoalsProfileCard: View {
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var goalAccountSync: ATHLTHGoalAccountSyncStore

    @State private var showingCreateGoal = false
    @State private var measurementProfile = ATHLTHTrainingProfile()

    private var orderedActiveGoals: [ATHLTHGoal] {
        goalStore.goals
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func progress(for goal: ATHLTHGoal) -> Double {
        ATHLTHGoalProgressPolicy.progress(
            for: goal,
            profile: measurementProfile,
            latestBodyWeightKilograms: health.personalDetails.weightKilograms
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 40, height: 40)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("My goals", "Mine mål"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                    Label(tr("Private owner overview", "Privat måloversikt"),
                          systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }

                Spacer(minLength: 0)

                Text("\(orderedActiveGoals.count) " + tr("active", "aktive"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .lineLimit(1)
            }

            if !goalAccountSync.conflictingGoalIDs.isEmpty ||
                !goalAccountSync.conflictingMeasurementIDs.isEmpty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Goals changed on both devices. Check sync before editing further.",
                        norwegian: "Mål er endret på begge enheter. Kontroller synkronisering før du redigerer videre."
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.ink)
            } else if goalAccountSync.lastSyncError != nil {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Waiting for account sync. Your goals are saved on this device.",
                        norwegian: "Venter på kontosynkronisering. Målene er lagret på denne enheten."
                    ),
                    systemImage: "icloud.slash"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else if goalAccountSync.isSyncing {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Syncing goals", norwegian: "Synkroniserer mål"
                    ),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else if goalAccountSync.lastSuccessfulSync != nil {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Goals synced to your account",
                        norwegian: "Målene er synkronisert med kontoen"
                    ),
                    systemImage: "checkmark.icloud"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            if orderedActiveGoals.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Your next chapter starts here", "Neste mål starter her"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    Text(tr("Set a goal, add milestones and track the progress you make.",
                            "Opprett et mål, legg til delmål og følg utviklingen din."))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ATHLTHPlanDesign.selectedSurface.opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(Array(orderedActiveGoals.prefix(3))) { goal in
                    NavigationLink {
                        GoalDetailView(goalID: goal.id)
                    } label: {
                        goalRow(goal)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                NavigationLink {
                    GoalsHubView()
                } label: {
                    Label(tr("All goals", "Alle mål"), systemImage: "list.bullet")
                        .frame(maxWidth: .infinity, minHeight: 45)
                }
                .buttonStyle(.plain)
                .background(ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(ATHLTHPlanDesign.ink)

                Button {
                    showingCreateGoal = true
                } label: {
                    Label(tr("New goal", "Nytt mål"), systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 45)
                }
                .buttonStyle(.plain)
                .background(ATHLTHPlanDesign.accent,
                            in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(ATHLTHPlanDesign.ink)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(ATHLTHPlanDesign.warmDivider.opacity(0.65), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .onAppear(perform: reloadMeasurements)
        .onChange(of: session.profile.userID) { _, _ in reloadMeasurements() }
        .onReceive(NotificationCenter.default.publisher(for: .athlthTrainingDataDidChange)) { _ in
            reloadMeasurements()
        }
        .sheet(isPresented: $showingCreateGoal) {
            GoalCreationView()
        }
    }

    private func goalRow(_ goal: ATHLTHGoal) -> some View {
        let value = progress(for: goal)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if goal.isPrimary {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                Text(goal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .lineLimit(2)

                Spacer(minLength: 5)

                Text("\(Int((value * 100).rounded()))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            ProgressView(value: value)
                .tint(ATHLTHPlanDesign.accentInk)
        }
        .padding(13)
        .background(ATHLTHPlanDesign.selectedSurface.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }

    private func reloadMeasurements() {
        measurementProfile = ATHLTHTrainingProfile.load(userID: session.profile.userID)
    }
}
