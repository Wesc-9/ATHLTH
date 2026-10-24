import SwiftUI

/// Identical premium strength artwork in the workout-complete review and
/// Home's recent-activity strip. The 2400px studio photograph is bundled:
/// no blurry 3 KB thumbnail, network fetch or duplicated card artwork.
struct ATHLTHStrengthCompletedHeroCard: View {
    let profile: StrengthMuscleProfile
    let duration: TimeInterval
    let exerciseCount: Int?
    let volumeKilograms: Double?
    let height: CGFloat
    var compact = false
    var showsCompletionLabel = true
    // The result, activity feed and detail screen use the same layered artwork.
    var showsMetrics = true
    var detailMetadata: String? = nil
    var cornerRadius: CGFloat? = nil

    private let ink = Color(red: 0.14, green: 0.15, blue: 0.16)
    private let secondaryInk = Color(red: 0.35, green: 0.38, blue: 0.42)
    private let warmAccent = Color(red: 0.48, green: 0.34, blue: 0.21)
    private let muscleAccent = Color(red: 0.34, green: 0.63, blue: 0.48)

    private var focus: String {
        let top = profile.topActivations
            .prefix(2)
            .map { $0.region.activityDisplayTitle }
        guard !top.isEmpty else {
            return ATHLTHLocalization.choose(
                english: "Strength training",
                norwegian: "Styrketrening"
            )
        }
        return top.joined(separator: " · ")
    }

    private var durationLabel: String {
        guard duration.isFinite, duration > 0 else { return "—" }
        let seconds = max(Int(duration.rounded()), 0)
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    private var volumeLabel: String {
        guard let volumeKilograms, volumeKilograms.isFinite,
              volumeKilograms > 0 else { return "—" }
        return volumeKilograms >= 1000
            ? String(format: "%.1f t", volumeKilograms / 1000)
            : String(format: "%.0f kg", volumeKilograms)
    }

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = geometry.size.height
            let cardWidth = geometry.size.width
            let small = compact || cardHeight < 250
            let tight = cardHeight < 170
            let displaysMetrics = showsMetrics && !tight
            let footerHeight: CGFloat = displaysMetrics ? (small ? 46 : 75) : 0

            ZStack(alignment: .topLeading) {
                Image("StrengthFeedGym")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .saturation(0.75)
                    .contrast(0.88)

                // Matte light grade keeps the medal and muscles legible
                // without making the strength room a distracting hero.
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.64), location: 0),
                        .init(color: Color.white.opacity(0.36), location: 0.42),
                        .init(color: Color(red: 0.98, green: 0.97, blue: 0.95)
                            .opacity(0.79), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [.clear, .white.opacity(0.10), .white.opacity(0.91)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: footerHeight + 28)
                .frame(maxHeight: .infinity, alignment: .bottom)

                if !profile.activations.isEmpty {
                    // The figures reach the full artwork height; do not
                    // embed a tiny muscle-map card within the image.
                    StrengthMuscleMapView(
                        profile: profile,
                        compact: true,
                        style: .activation,
                        presentation: .home,
                        activationTint: muscleAccent
                    )
                    .frame(
                        width: tight ? min(cardWidth * 0.60, 210) : min(cardWidth * 0.88, 390),
                        height: cardHeight * (tight ? 0.94 : 0.98)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
                    .padding(.trailing, tight ? 6 : (small ? 2 : 12))
                    .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if let detailMetadata {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                ATHLTHLocalization.choose(english: "STRENGTH", norwegian: "STYRKE"),
                                systemImage: "dumbbell.fill"
                            )
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                            Text(detailMetadata)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(secondaryInk)
                    } else if showsCompletionLabel {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "WORKOUT COMPLETE",
                                norwegian: "ØKT FULLFØRT"
                            ),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: small ? 8 : 10, weight: .bold))
                        .tracking(small ? 0.9 : 1.5)
                        .foregroundStyle(warmAccent)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: small ? 1 : 4) {
                        Text(ATHLTHLocalization.choose(
                            english: "Strength", norwegian: "Styrke"
                        ))
                        .font(.system(size: tight ? 20 : (small ? 25 : 35), weight: .bold,
                                      design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(ink)

                        Text(focus)
                            .font(.system(size: tight ? 10 : (small ? 12 : 17),
                                          weight: .medium))
                            .foregroundStyle(secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.77)
                    }
                    .frame(maxWidth: cardWidth * (tight ? 0.52 : (small ? 0.50 : 0.49)),
                           alignment: .leading)
                    .padding(.bottom, tight ? 2 : (small ? 9 : 16))

                    if displaysMetrics {
                    HStack(spacing: 0) {
                        metric("stopwatch", durationLabel,
                               ATHLTHLocalization.choose(english: "Time", norwegian: "Tid"),
                               small: small)
                        metricDivider
                        metric("dumbbell.fill", exerciseCount.map(String.init) ?? "—",
                               ATHLTHLocalization.choose(english: "Exercises", norwegian: "Øvelser"),
                               small: small)
                        metricDivider
                        metric("scalemass.fill", volumeLabel,
                               ATHLTHLocalization.choose(english: "Volume", norwegian: "Volum"),
                               small: small)
                    }
                    .frame(height: footerHeight)
                    }
                }
                .padding(.horizontal, small ? 13 : 20)
                .padding(.top, small ? 12 : 19)
                .padding(.bottom, small ? 6 : 10)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? (compact ? 20 : 28),
                                        style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius ?? (compact ? 20 : 28),
                                 style: .continuous)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.8)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")), " +
            "\(focus), \(durationLabel), \(exerciseCount.map(String.init) ?? "—") " +
            "\(ATHLTHLocalization.choose(english: "exercises", norwegian: "øvelser")), " +
            "\(volumeLabel)"
        )
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(warmAccent.opacity(0.22))
            .frame(width: 0.8, height: 30)
    }

    private func metric(
        _ icon: String,
        _ value: String,
        _ label: String,
        small: Bool
    ) -> some View {
        VStack(spacing: small ? 1 : 5) {
            HStack(spacing: small ? 3 : 7) {
                Image(systemName: icon)
                    .font(.system(size: small ? 9 : 13, weight: .semibold))
                    .foregroundStyle(warmAccent)
                Text(value)
                    .font(.system(size: small ? 12 : 17, weight: .bold,
                                  design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.system(size: small ? 9 : 11))
                .foregroundStyle(secondaryInk)
        }
        .frame(maxWidth: .infinity)
    }
}
