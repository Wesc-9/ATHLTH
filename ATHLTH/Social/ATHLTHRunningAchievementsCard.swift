import SwiftUI

/// An intentionally compact companion to "Øktens høydepunkter".
/// No empty placeholder and no celebration of a high heart rate.
struct ATHLTHRunningAchievementsCard: View {
    let achievements: [ATHLTHRunningAchievement]

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        if !achievements.isEmpty {
            ATHLTHPlanSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        tr("New achievements", "Nye prestasjoner"),
                        systemImage: "medal"
                    )
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(ATHLTHPlanDesign.ink)

                    ForEach(Array(achievements.prefix(3).enumerated()), id: \.element.id) {
                        index, item in
                        HStack(alignment: .center, spacing: 11) {
                            Image(systemName: icon(for: item))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 40, height: 40)
                                .background(
                                    ATHLTHPlanDesign.selectedSurface,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(for: item))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                                Text(value(for: item))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(ATHLTHPlanDesign.ink)

                                Text(detail(for: item))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)

                        if index < min(achievements.count, 3) - 1 {
                            Rectangle()
                                .fill(ATHLTHPlanDesign.warmDivider)
                                .frame(height: 0.6)
                        }
                    }

                    if achievements.contains(where: {
                        $0.kind == .maximumRecordedHeartRate
                    }) {
                        Text(tr(
                            "Peak heart rate is an observation, not a measure of better fitness.",
                            "Toppuls er en måling, ikke et tegn på bedre form."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("athlth-running-new-achievements")
        }
    }

    private func title(for achievement: ATHLTHRunningAchievement) -> String {
        switch achievement.kind {
        case .fastestKilometer:
            return tr("New 1 km personal best", "Ny personlig rekord · 1 km")
        case .fastestFiveKilometers:
            return tr("New 5 km personal best", "Ny personlig rekord · 5 km")
        case .longestRun:
            return tr("Longest run so far", "Ny rekord · lengste løpetur")
        case .routePersonalBest:
            return tr("New route personal best", "Ny bestetid på rute")
        case .maximumRecordedHeartRate:
            return tr("New running peak heart rate", "Ny registrert toppuls under løping")
        }
    }

    private func icon(for achievement: ATHLTHRunningAchievement) -> String {
        switch achievement.kind {
        case .fastestKilometer: return "speedometer"
        case .fastestFiveKilometers: return "figure.run"
        case .longestRun: return "point.topleft.down.to.point.bottomright.curvepath"
        case .routePersonalBest: return "flag.checkered"
        case .maximumRecordedHeartRate: return "heart"
        }
    }

    private func value(for achievement: ATHLTHRunningAchievement) -> String {
        switch achievement.kind {
        case .fastestKilometer:
            return time(achievement.value) + " /km"
        case .fastestFiveKilometers, .routePersonalBest:
            return time(achievement.value)
        case .longestRun:
            return String(format: "%.2f km", achievement.value / 1_000)
        case .maximumRecordedHeartRate:
            return "\(Int(achievement.value.rounded())) bpm"
        }
    }

    private func detail(for achievement: ATHLTHRunningAchievement) -> String {
        let improvement = achievement.previousValue - achievement.value
        switch achievement.kind {
        case .fastestKilometer, .fastestFiveKilometers:
            return tr(
                "\(time(improvement)) faster than your previous best",
                "\(time(improvement)) raskere enn tidligere rekord"
            )
        case .routePersonalBest:
            let delta = tr(
                "\(time(improvement)) faster than your previous route best",
                "\(time(improvement)) raskere enn tidligere bestetid"
            )
            if let name = achievement.routeTitle, !name.isEmpty {
                return name + " · " + delta
            }
            return delta
        case .longestRun:
            let metres = Int((achievement.value - achievement.previousValue).rounded())
            return tr(
                "\(metres) m further than your previous longest run",
                "\(metres) m lengre enn tidligere rekord"
            )
        case .maximumRecordedHeartRate:
            let bpm = Int((achievement.value - achievement.previousValue).rounded())
            return tr(
                "\(bpm) bpm above your previous recorded peak",
                "\(bpm) bpm over tidligere registrerte toppuls"
            )
        }
    }

    private func time(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        if rounded >= 3_600 {
            return String(format: "%d:%02d:%02d",
                          rounded / 3_600, (rounded % 3_600) / 60, rounded % 60)
        }
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
