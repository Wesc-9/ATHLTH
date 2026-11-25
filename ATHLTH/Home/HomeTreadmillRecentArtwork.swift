import SwiftUI
import UIKit

/// Data-backed treadmill hero for the light-theme Recent Activity cards.
/// The gym artwork is intentionally free of fixed workout numbers; every
/// metric shown here comes from the actual recorded workout.
struct HomeTreadmillRecentArtwork: View {
    let workout: SocialPublishableWorkout
    let averageHeartRate: Double?
    let height: CGFloat

    /// The original tiny treadmill artwork has been replaced in-place by
    /// a high-resolution 1536 x 1024 treadmill photograph. Keep the treadmill
    /// identity instead of reusing an outdoor running photo in the feed.
    static let backgroundAssetName = "TreadmillRecentCardHero"

    /// Use the original photo rather than the possibly downsampled UIKit
    /// asset rendition. Loaded once and reused across Recent Activity cards.
    /// The build validates its dimensions before bundling it.
    private static let originalPhoto: UIImage? = {
        guard let url = Bundle.main.url(
            forResource: "TreadmillRecentCardHeroFull",
            withExtension: "jpg"
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    private var treadmillImage: Image {
        if let originalPhoto = Self.originalPhoto {
            Image(uiImage: originalPhoto)
        } else {
            Image(Self.backgroundAssetName)
        }
    }

    var body: some View {
        ATHLTHFeedArtworkOverlay(
            title: ATHLTHLocalization.choose(english: "Treadmill", norwegian: "Tredemølle"),
            icon: "figure.run", height: height,
            metrics: .init(duration: workout.duration, distanceMeters: workout.distanceMeters),
            averageHeartRate: averageHeartRate
        ) {
            GeometryReader { geometry in
                treadmillImage.resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }
    }
}

/// Real workout values only. Missing measurements are omitted.
struct ATHLTHFeedArtworkMetrics {
    var duration: Double? = nil
    var distanceMeters: Double? = nil
    var exerciseCount: Int? = nil
    var volumeKilograms: Double? = nil
    var strength = false
    var showsPace = true

    var durationText: String? {
        guard let duration, duration.isFinite, duration > 0, duration < 10_000_000 else { return nil }
        let minutes = max(1, Int((duration / 60).rounded()))
        return minutes >= 60 ? "\(minutes / 60)t \(minutes % 60)m" : "\(minutes) min"
    }

    var distanceText: String? {
        guard let distanceMeters, distanceMeters.isFinite, distanceMeters > 0 else { return nil }
        return String(format: "%.2f km", distanceMeters / 1000)
    }

    var paceText: String? {
        guard let duration, let distanceMeters, duration.isFinite, duration > 0,
              distanceMeters.isFinite, distanceMeters > 0 else { return nil }
        let pace = duration / (distanceMeters / 1000)
        guard pace.isFinite, pace > 0, pace < 36000 else { return nil }
        let seconds = Int(pace.rounded())
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }

    var primary: String? {
        if strength {
            if let exerciseCount, exerciseCount > 0 {
                return ATHLTHLocalization.choose(english: "\(exerciseCount) exercises", norwegian: "\(exerciseCount) øvelser")
            }
            return durationText
        }
        return distanceText ?? durationText
    }

    var secondary: String {
        var parts: [String] = []
        if strength {
            if let exerciseCount, exerciseCount > 0, let durationText { parts.append(durationText) }
            if let volumeKilograms, volumeKilograms.isFinite, volumeKilograms > 0 {
                parts.append(String(format: "%.0f kg", volumeKilograms))
            }
        } else if distanceText != nil {
            if let durationText { parts.append(durationText) }
            if showsPace, let paceText { parts.append(paceText) }
        }
        return parts.joined(separator: " · ")
    }
}

/// One typography and metric layout for all feed artwork. Backgrounds may
/// be photos, private route snapshots or explicitly shared route previews.
struct ATHLTHFeedArtworkOverlay<Artwork: View>: View {
    let title: String
    let icon: String
    let height: CGFloat
    let metrics: ATHLTHFeedArtworkMetrics
    var averageHeartRate: Double? = nil
    @ViewBuilder let artwork: Artwork

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            LinearGradient(stops: [
                .init(color: .black.opacity(0.22), location: 0),
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(0.68), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            VStack {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(.black.opacity(0.42), in: Capsule())
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let primary = metrics.primary {
                            Text(primary)
                                .font(.system(size: height < 140 ? 19 : 24, weight: .bold, design: .rounded))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        }
                        if !metrics.secondary.isEmpty {
                            Text(metrics.secondary)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                    if let averageHeartRate, averageHeartRate.isFinite,
                       averageHeartRate > 0, averageHeartRate < 300 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(Color(red: 0.67, green: 0.96, blue: 0.79))
                            Text("\(Int(averageHeartRate.rounded()))")
                        }
                            .font(.system(size: 10, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 7).frame(height: 23)
                            .background(.black.opacity(0.40), in: Capsule())
                            .accessibilityLabel(ATHLTHLocalization.choose(
                                english: "Average heart rate \(Int(averageHeartRate.rounded()))",
                                norwegian: "Snittpuls \(Int(averageHeartRate.rounded()))"))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 11)
        }
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}
