import SwiftUI

/// A read-only window into the existing goal and trophy stores. Viewing Train
/// never awards an achievement or changes a milestone's completion method.
struct ATHLTHTrainAchievementsView: View {
    @EnvironmentObject private var goals: GoalStore
    @EnvironmentObject private var trophies: TrophyStore
    let startDate: Date

    private struct MilestoneEntry: Identifiable {
        let goal: ATHLTHGoal
        let milestone: GoalMilestone
        let date: Date
        var id: String { goal.id.uuidString + milestone.id.uuidString }
    }

    private var milestones: [MilestoneEntry] {
        let now = Date()
        return goals.goals.flatMap { goal in
            goal.milestones.compactMap { milestone -> MilestoneEntry? in
                guard let date = milestone.completedAt,
                      date >= startDate, date <= now else { return nil }
                return MilestoneEntry(goal: goal, milestone: milestone, date: date)
            }
        }.sorted { $0.date > $1.date }
    }

    private var earned: [TrophyProgressItem] {
        trophies.trophies.filter(\.isUnlocked).sorted {
            if $0.unlockedAt != $1.unlockedAt {
                return ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast)
            }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ATHLTHTrainSectionHeading(
                eyebrow: tr("STEP BY STEP", "STEG FOR STEG"),
                title: tr("Milestones and achievements", "Delmål og prestasjoner"),
                detail: tr("Completed milestones in this period. Your earned achievements across all time.",
                           "Fullførte delmål i perioden. Opptjente prestasjoner fra hele historikken."))

            if milestones.isEmpty {
                Text(tr("No completed milestones in this period.",
                        "Ingen fullførte delmål i denne perioden."))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            } else {
                ForEach(milestones.prefix(3)) { entry in
                    NavigationLink {
                        GoalDetailView(goalID: entry.goal.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(entry.milestone.title, systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.semibold))
                            Text(entry.goal.title)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTrainDesign.secondary)
                            Text(source(for: entry.milestone) + " · " +
                                 entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(ATHLTHTrainDesign.bronze)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            NavigationLink {
                GoalsHubView()
            } label: {
                Label(tr("All goals and milestones", "Alle mål og delmål"),
                      systemImage: "arrow.up.right")
                    .frame(minHeight: 48)
            }
            .font(.subheadline.weight(.medium))

            Rectangle().fill(ATHLTHTrainDesign.rule).frame(height: 1)
            if earned.isEmpty {
                Text(tr("Earned achievements appear here as they are registered.",
                        "Opptjente prestasjoner vises her når de er registrert."))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
            } else {
                ForEach(earned.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(item.title, systemImage: item.systemImage)
                            .font(.subheadline.weight(.semibold))
                        Text(item.stageLabel + " · " + item.verificationSource.title)
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
            NavigationLink {
                TrophyCollectionView()
            } label: {
                Label(tr("Explore achievements", "Se prestasjoner"), systemImage: "trophy")
                    .frame(minHeight: 48)
            }
            .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(ATHLTHTrainDesign.ink)
        .tint(ATHLTHTrainDesign.bronze)
        .padding(20)
        .athlthTrainPaper()
    }

    private func source(for milestone: GoalMilestone) -> String {
        switch milestone.completionMethod {
        case .automaticAppleHealth: return "Apple Health"
        case .automaticATHLTH: return tr("Recorded in ATHLTH", "Registrert i ATHLTH")
        case .manual: return tr("Marked complete manually", "Fullført manuelt")
        case nil: return tr("Source not recorded", "Kilde ikke registrert")
        }
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}
