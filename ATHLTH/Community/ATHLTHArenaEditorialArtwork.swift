import SwiftUI
import UIKit

/// Four crops from the Arena concept explicitly selected for ATHLTH 1.8.9.
/// The single, local JPEG atlas keeps the launch artwork offline and avoids
/// four large decoded photos in the scrolling view. All labels/buttons are
/// native SwiftUI, not baked into the screenshot.
enum ATHLTHArenaEditorialScene: Hashable {
    case athlete, stadium, running, strength

    fileprivate var atlasCrop: (y: CGFloat, height: CGFloat) {
        switch self {
        case .athlete: return (0, 165)
        case .stadium: return (165, 155)
        case .running: return (320, 135)
        case .strength: return (455, 135)
        }
    }

    fileprivate var fallback: String {
        switch self {
        case .athlete: return "CommunityHero"
        case .stadium: return "ConversationStadiumHero"
        case .running: return "GoalRunning"
        case .strength: return "StrengthFeedGym"
        }
    }
}

private enum ATHLTHArenaEditorialAtlas {
    static let image = UIImage(named: "ArenaReferenceAtlas")?.cgImage

    static let athlete = cropped(.athlete)
    static let stadium = cropped(.stadium)
    static let running = cropped(.running)
    static let strength = cropped(.strength)

    static func cropped(_ scene: ATHLTHArenaEditorialScene) -> UIImage? {
        guard let image else { return nil }
        let crop = scene.atlasCrop
        let scale = CGFloat(image.height) / 590
        let y = Int((crop.y * scale).rounded(.down))
        let end = Int(((crop.y + crop.height) * scale).rounded(.down))
        guard end > y,
              let part = image.cropping(to: CGRect(
                x: 0, y: y, width: image.width,
                height: min(end - y, image.height - y)
              )) else { return nil }
        return UIImage(cgImage: part)
    }

    static func photo(_ scene: ATHLTHArenaEditorialScene) -> UIImage? {
        switch scene {
        case .athlete: return athlete
        case .stadium: return stadium
        case .running: return running
        case .strength: return strength
        }
    }
}

struct ATHLTHArenaEditorialPhoto: View {
    let scene: ATHLTHArenaEditorialScene

    var body: some View {
        Group {
            if let image = ATHLTHArenaEditorialAtlas.photo(scene) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // No remote fetch or image generation during a workout/session.
                Image(scene.fallback)
                    .resizable()
                    .scaledToFill()
            }
        }
        .accessibilityHidden(true)
    }
}

/// Editorial, *advisory* visible-activity podium. This does not claim Arena
/// victories, replace server-authorized season standings, or rank users with
/// private workout histories. Empty states never invent athletes or points.
struct ATHLTHArenaVisibleActivityPodium: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var health: HealthKitManager

    private struct Athlete: Identifiable {
        let id: UUID
        let name: String
        let avatarURL: URL?
        let points: Double
        let workouts: Int
        let isYou: Bool
    }

    private var threshold: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date())
            ?? .distantPast
    }

    private func points(workouts: Double, activeMinutes: Double) -> Double {
        let split = CommunityMatchupVisualPolicy.pointsBreakdown(
            workouts: workouts, activeMinutes: activeMinutes
        )
        return (split?.workoutPoints ?? 0) + (split?.timePoints ?? 0)
    }

    private var athletes: [Athlete] {
        let own = health.workouts.filter { $0.startDate >= threshold }
        let ownMinutes = own.reduce(0.0) { $0 + max($1.duration, 0) } / 60
        var all = [Athlete(
            id: session.profile.userID,
            name: session.profile.displayName.isEmpty
                ? ATHLTHLocalization.choose(english: "You", norwegian: "Deg")
                : session.profile.displayName,
            avatarURL: session.profile.avatarURL,
            points: points(workouts: Double(own.count), activeMinutes: ownMinutes),
            workouts: own.count,
            isYou: true
        )]

        for friend in social.mutualFollows {
            let visible = social.feed.filter {
                $0.actor.userID == friend.userID &&
                $0.activity.kind == "workout" &&
                $0.activity.createdAt >= threshold
            }
            let seconds = visible.reduce(0.0) { value, item in
                let raw = item.activity.metadata?["duration_seconds"] ?? ""
                let duration = Double(raw) ?? 0
                return value + (duration.isFinite ? max(0, duration) : 0)
            }
            all.append(Athlete(
                id: friend.userID,
                name: friend.resolvedName,
                avatarURL: friend.avatarURL.flatMap(URL.init(string:)),
                points: points(
                    workouts: Double(visible.count),
                    activeMinutes: seconds / 60
                ),
                workouts: visible.count,
                isYou: false
            ))
        }
        return Array(all.filter { $0.workouts > 0 && $0.points.isFinite }
            .sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                return $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "trophy")
                    .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                Text(ATHLTHLocalization.choose(
                    english: "Top athletes", norwegian: "Ukens utøvere"
                ))
                .font(ATHLTHArenaLightStyle.editorialTitle(22))
                .foregroundStyle(ATHLTHArenaLightStyle.ink)
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "7 days", norwegian: "7 dager"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHArenaLightStyle.secondary)
            }

            if athletes.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle")
                        .font(.system(size: 33, weight: .ultraLight))
                        .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "Your circle is ready",
                            norwegian: "Plass til første prestasjon"
                        ))
                        .font(.subheadline.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Visible training achievements appear here.",
                            norwegian: "Delte treningsprestasjoner vises her."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaLightStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 13)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    athleteColumn(at: 1)
                    athleteColumn(at: 0)
                    athleteColumn(at: 2)
                }
                .frame(maxWidth: .infinity)
            }

            Text(ATHLTHLocalization.choose(
                english: "Activity points from visible workouts · not official competition results",
                norwegian: "Aktivitetspoeng fra synlige økter · ikke offisielle konkurranseresultater"
            ))
            .font(.system(size: 10))
            .foregroundStyle(ATHLTHArenaLightStyle.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .padding(17)
        .background(ATHLTHArenaLightStyle.card(23))
    }

    @ViewBuilder
    private func athleteColumn(at index: Int) -> some View {
        if athletes.indices.contains(index) {
            let athlete = athletes[index]
            VStack(spacing: 5) {
                CommunityShowcaseAvatar(
                    url: athlete.avatarURL,
                    fallback: athlete.name,
                    size: index == 0 ? 74 : 59
                )
                .overlay {
                    Circle().stroke(
                        index == 0
                            ? ATHLTHArenaLightStyle.warmGold
                            : ATHLTHArenaLightStyle.line,
                        lineWidth: index == 0 ? 2.5 : 1
                    )
                }
                .overlay(alignment: .bottom) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(index == 0
                            ? ATHLTHArenaLightStyle.ink : .white)
                        .frame(width: 22, height: 22)
                        .background(
                            index == 0
                                ? ATHLTHTheme.champagneSoft
                                : ATHLTHArenaLightStyle.secondary,
                            in: Circle()
                        )
                        .offset(y: 8)
                }
                .padding(.bottom, 8)

                Text(athlete.isYou
                    ? ATHLTHLocalization.choose(english: "You", norwegian: "Du")
                    : String(athlete.name.split(separator: " ").first ?? ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHArenaLightStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(String(format: "%.0f p", athlete.points))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHArenaLightStyle.warmGold)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 1)
        }
    }
}
