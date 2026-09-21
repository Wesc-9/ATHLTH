import SwiftUI
import UIKit

enum OnboardingArtworkKind {
    case username
    case goals
    case connections
    case ready

    var title: String {
        switch self {
        case .username: return "YOUR ATHLTH ID"
        case .goals: return "TRAIN • RECOVER • PROGRESS"
        case .connections: return "YOUR HEALTH, CONNECTED"
        case .ready: return "BUILT AROUND YOU"
        }
    }

    var symbols: [String] {
        switch self {
        case .username:
            return ["person.crop.circle.fill", "at", "person.2.fill"]
        case .goals:
            return ["dumbbell.fill", "figure.run", "moon.stars.fill"]
        case .connections:
            return ["heart.fill", "applewatch", "waveform.path.ecg"]
        case .ready:
            return ["checkmark.seal.fill", "chart.line.uptrend.xyaxis", "figure.run"]
        }
    }
}

struct OnboardingHeroPhoto: View {
    private static let image: UIImage? = {
        let encoded = [
            OnboardingHeroDataPart0.value,
            OnboardingHeroDataPart1.value,
            OnboardingHeroDataPart2.value,
            OnboardingHeroDataPart3.value
        ]
        .joined()
        .replacingOccurrences(of: "\n", with: "")

        guard
            let data = Data(base64Encoded: encoded),
            let image = UIImage(data: data)
        else {
            return nil
        }

        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.17, green: 0.14, blue: 0.12),
                        Color(red: 0.05, green: 0.05, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 72, weight: .thin))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct OnboardingSceneCard: View {
    let kind: OnboardingArtworkKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            OnboardingTheme.warmHighlight.opacity(0.10),
                            Color.black.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(OnboardingTheme.warmHighlight.opacity(0.13))
                .frame(width: 170, height: 170)
                .offset(x: 145, y: -20)
                .blur(radius: 4)

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(kind.title)
                        .font(.caption2.weight(.bold))
                        .tracking(1.7)
                        .foregroundStyle(.white.opacity(0.72))

                    HStack(spacing: 11) {
                        ForEach(kind.symbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.09), in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                }
                        }
                    }
                }

                Spacer(minLength: 8)

                ATHLTHMarkShape()
                    .fill(.white.opacity(0.80))
                    .frame(width: 42, height: 28)
            }
            .padding(18)
        }
        .frame(height: 112)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        .accessibilityHidden(true)
    }
}
