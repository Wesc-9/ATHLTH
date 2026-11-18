import SwiftUI
import UIKit

/// Data-backed treadmill hero for the light-theme Recent Activity cards.
/// The gym artwork is intentionally free of fixed workout numbers; every
/// metric shown here comes from the actual recorded workout.
struct HomeTreadmillRecentArtwork: View {
    let workout: SocialPublishableWorkout
    let averageHeartRate: Double?
    let height: CGFloat

    private let mint = Color(red: 0.67, green: 0.96, blue: 0.79)

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

    private var distance: Double? {
        guard let meters = workout.distanceMeters,
              meters.isFinite, meters > 0 else {
            return nil
        }
        return meters / 1_000
    }

    private var durationText: String {
        let totalMinutes = max(Int((workout.duration / 60).rounded()), 0)
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)t \(totalMinutes % 60)m"
        }
        return "\(totalMinutes) min"
    }

    private var paceText: String? {
        guard let distance, workout.duration.isFinite,
              workout.duration > 0 else {
            return nil
        }
        let secondsPerKilometer = workout.duration / distance
        guard secondsPerKilometer.isFinite,
              secondsPerKilometer > 0 else {
            return nil
        }
        let seconds = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }

    private var heartRate: Int? {
        guard let averageHeartRate,
              averageHeartRate.isFinite,
              averageHeartRate > 0 else {
            return nil
        }
        return Int(averageHeartRate.rounded())
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                treadmillImage
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.10), location: 0),
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.65), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    HStack {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Treadmill",
                                norwegian: "Tredemølle"
                            ),
                            systemImage: "figure.run"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.black.opacity(0.38), in: Capsule())
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let distance {
                            Text(
                                String(
                                    format: "%.2f km",
                                    distance
                                )
                            )
                            .font(
                                .system(
                                    size: height < 140 ? 19 : 24,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        } else {
                            Text(durationText)
                                .font(
                                    .system(
                                        size: height < 140 ? 18 : 22,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .monospacedDigit()
                        }

                        HStack(spacing: 4) {
                            if distance != nil {
                                Text(durationText)
                            }
                            if let paceText {
                                Text("·")
                                Text(paceText)
                            }
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }

                    Spacer(minLength: 0)

                    if let heartRate {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(mint)
                            Text("\(heartRate)")
                                .monospacedDigit()
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .frame(height: 23)
                        .background(
                            .black.opacity(0.40),
                            in: Capsule()
                        )
                        .accessibilityLabel(
                            ATHLTHLocalization.choose(
                                english: "Average heart rate \(heartRate)",
                                norwegian: "Snittpuls \(heartRate)"
                            )
                        )
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.bottom, 11)
            }
        }
        .frame(height: height)
        .clipped()
        .accessibilityLabel(
            ATHLTHLocalization.choose(
                english: "Treadmill workout",
                norwegian: "Tredemølleøkt"
            )
        )
    }
}
