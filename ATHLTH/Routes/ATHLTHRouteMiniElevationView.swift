import CoreLocation
import SwiftUI

/// Shared, read-only projection of the route's *sourced* elevation data.
/// A route without altitude samples must not be given a synthetic hill profile.
enum ATHLTHRouteMiniElevationPolicy {
    struct Summary {
        let profile: [Double]
        let ascentMeters: Double?
        let descentMeters: Double?
        let difficulty: String?

        var hasContent: Bool {
            profile.count >= 2 || ascentMeters != nil ||
            descentMeters != nil || difficulty != nil
        }
    }

    static func summary(
        for route: TrainingRoute,
        published: PublicTrailRecord? = nil
    ) -> Summary {
        let ordered = ATHLTHRouteDetailsPolicy.ordered(route)
        // GPS tracks with just two altitude fixes and hundreds of missing
        // values do not constitute a trustworthy elevation profile.
        let track = ordered.compactMap { validAltitude($0.altitude) }
        let completeEnough = track.count >= 2 &&
            Double(track.count) / Double(max(ordered.count, 1)) >= 0.5
        let publishedProfile = (published?.elevationProfile ?? [])
            .compactMap { validAltitude($0) }
        let fullProfile: [Double]
        if publishedProfile.count >= 2 {
            fullProfile = publishedProfile
        } else if completeEnough {
            fullProfile = track
        } else {
            fullProfile = []
        }

        // Calculate ascent/descent using the unsampled valid profile, not the
        // 72 display points. Preserve published ascent and loss when supplied.
        let calculated = ATHLTHRouteDetailsPolicy.ascentDescent(fullProfile)
        let ascent = validNonnegative(published?.elevationGainMeters) ??
            validNonnegative(route.elevationGainMeters) ?? calculated?.ascent
        let descent = validNonnegative(published?.elevationLossMeters) ??
            calculated?.descent

        let sourceDifficulty = published?.difficulty?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let difficulty = sourceDifficulty.flatMap { value -> String? in
            guard !value.isEmpty else { return nil }
            // Long provider prose belongs on the full details page.
            return String(value.prefix(44))
        }

        return Summary(
            profile: sampled(fullProfile, maximum: 72),
            ascentMeters: ascent,
            descentMeters: descent,
            difficulty: difficulty
        )
    }

    private static func validAltitude(_ value: Double?) -> Double? {
        guard let value, value.isFinite,
              (-500...9000).contains(value) else { return nil }
        return value
    }

    private static func validNonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0,
              value <= 100_000 else { return nil }
        return value
    }

    private static func sampled(_ values: [Double], maximum: Int) -> [Double] {
        let limit = max(2, maximum)
        guard values.count > limit else { return values }
        return (0..<limit).map { index in
            let fraction = Double(index) / Double(limit - 1)
            let source = Int((fraction * Double(values.count - 1)).rounded())
            return values[source]
        }
    }
}

/// Small, airy cartographic elevation preview for the Explore route card.
/// The large route-detail elevation view remains unchanged.
struct ATHLTHRouteMiniElevationView: View {
    let summary: ATHLTHRouteMiniElevationPolicy.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "mountain.2")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                Text(ATHLTHLocalization.choose(
                    english: "Elevation profile", norwegian: "Høydeprofil"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer(minLength: 0)
            }

            if summary.profile.count >= 2 {
                GeometryReader { geometry in
                    ZStack {
                        ProfileShape(samples: summary.profile, fillArea: true)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        ATHLTHTheme.premiumGold.opacity(0.38),
                                        ATHLTHTheme.premiumGold.opacity(0.025)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        ProfileShape(samples: summary.profile, fillArea: false)
                            .stroke(
                                ATHLTHTheme.accentDeep,
                                style: StrokeStyle(
                                    lineWidth: 2.1,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(height: 49)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Route elevation profile from available elevation data",
                    norwegian: "Rutens høydeprofil fra tilgjengelige høydedata"
                ))
                .accessibilityAddTraits(.isImage)

                if let lowest = summary.profile.min(),
                   let highest = summary.profile.max() {
                    HStack {
                        Text("\(Int(lowest.rounded())) m")
                        Spacer()
                        Text("\(Int(highest.rounded())) m")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .monospacedDigit()
                }
            }

            if summary.ascentMeters != nil || summary.descentMeters != nil {
                HStack(spacing: 15) {
                    if let ascent = summary.ascentMeters {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Ascent", norwegian: "Stigning"
                            ) + " \(Int(ascent.rounded())) m",
                            systemImage: "arrow.up.right"
                        )
                    }
                    if let descent = summary.descentMeters {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Descent", norwegian: "Nedstigning"
                            ) + " \(Int(descent.rounded())) m",
                            systemImage: "arrow.down.right"
                        )
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(ATHLTHTheme.primaryText.opacity(0.82))
                .minimumScaleFactor(0.82)
            }

            if let difficulty = summary.difficulty {
                Label(
                    ATHLTHLocalization.choose(
                        english: "Difficulty", norwegian: "Vanskelighetsgrad"
                    ) + ": \(difficulty)",
                    systemImage: "chart.bar"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(2)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.7)
        }
        .accessibilityIdentifier("athlth-explore-route-mini-elevation")
    }
}

private struct ProfileShape: Shape {
    let samples: [Double]
    let fillArea: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count >= 2,
              let minimum = samples.min(),
              let maximum = samples.max(),
              rect.width > 0, rect.height > 0 else { return path }

        let spread = maximum - minimum
        let top = rect.minY + 4
        let bottom = rect.maxY - 3
        let height = bottom - top

        for index in samples.indices {
            let x = rect.minX +
                rect.width * CGFloat(index) / CGFloat(samples.count - 1)
            let normalized = spread > 0
                ? (samples[index] - minimum) / spread : 0.5
            let y = bottom - height * CGFloat(normalized)
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }

        if fillArea {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
