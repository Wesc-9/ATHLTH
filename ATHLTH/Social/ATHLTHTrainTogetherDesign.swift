import SwiftUI

/// One visual language for Train Together discovery, scheduling, invitations,
/// lobby, live progress, meetup and chat. Presentation-only; no state changes.
enum ATHLTHTrainTogetherDesign {
    static let canvas = ATHLTHPlanDesign.canvas
    static let surface = ATHLTHPlanDesign.surface
    static let stone = ATHLTHTheme.cardWarm
    static let ink = ATHLTHPlanDesign.ink
    static let secondary = ATHLTHPlanDesign.secondaryInk
    static let accent = ATHLTHPlanDesign.accentInk
    static let accentSoft = ATHLTHPlanDesign.selectedSurface
    static let outline = ATHLTHPlanDesign.outline
    static let radius: CGFloat = ATHLTHPlanDesign.cardRadius
    static let touchTarget: CGFloat = ATHLTHPlanDesign.minTapHeight
}

private struct ATHLTHTrainTogetherCardChrome: ViewModifier {
    let radius: CGFloat
    let subtle: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            ATHLTHTrainTogetherDesign.surface,
                            subtle ? ATHLTHTrainTogetherDesign.surface
                                : ATHLTHTrainTogetherDesign.stone.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(ATHLTHTrainTogetherDesign.outline, lineWidth: 0.8)
            }
            .shadow(color: ATHLTHTrainTogetherDesign.accent.opacity(subtle ? 0.025 : 0.055),
                    radius: subtle ? 8 : 14, y: subtle ? 3 : 6)
    }
}

extension View {
    func athlthTrainTogetherCard(
        radius: CGFloat = ATHLTHTrainTogetherDesign.radius,
        subtle: Bool = false
    ) -> some View {
        modifier(ATHLTHTrainTogetherCardChrome(radius: radius, subtle: subtle))
    }
}

struct ATHLTHTrainTogetherSurface<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .athlthTrainTogetherCard()
    }
}

/// A Train Together-only source card; the existing planning workflows are
/// passed straight through as actions. Does not duplicate session models.
struct ATHLTHTrainTogetherWorkoutSourceCard: View {
    let context: String
    let onCreateNew: () -> Void
    let onUsePlanned: () -> Void

    var body: some View {
        ATHLTHTrainTogetherSurface {
            Text(context)
                .font(.subheadline)
                .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sourceChoice(
                title: ATHLTHLocalization.choose(
                    english: "Build a new workout", norwegian: "Bygg en ny økt"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Plan exercises, intervals and rest.",
                    norwegian: "Sett opp øvelser, intervaller og pauser."
                ),
                icon: "plus.square.on.square",
                action: onCreateNew
            )

            sourceChoice(
                title: ATHLTHLocalization.choose(
                    english: "Use a planned workout", norwegian: "Bruk en planlagt økt"
                ),
                subtitle: ATHLTHLocalization.choose(
                    english: "Choose an existing complete session.",
                    norwegian: "Velg en eksisterende komplett treningsøkt."
                ),
                icon: "calendar.badge.checkmark",
                action: onUsePlanned
            )
        }
    }

    private func sourceChoice(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(ATHLTHTrainTogetherDesign.accent)
                    .frame(width: 47, height: 47)
                    .background(
                        ATHLTHTrainTogetherDesign.accentSoft,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHTrainTogetherDesign.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .athlthTrainTogetherCard(radius: 17, subtle: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
    }
}

struct ATHLTHTrainTogetherSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHTrainTogetherDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
