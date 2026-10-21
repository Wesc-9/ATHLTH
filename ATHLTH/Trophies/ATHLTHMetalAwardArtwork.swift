import SwiftUI

/// ATHLTH's unified metal award language.
/// Bronze, silver and gold are material tiers, not category colours.
/// Prestige awards use a separate sculpted gold cup.
enum ATHLTHMedalMetal: CaseIterable, Equatable {
    case bronze
    case silver
    case gold

    init(rarity: TrophyRarity) {
        switch rarity {
        case .core: self = .bronze
        case .rare: self = .silver
        case .epic, .signature: self = .gold
        }
    }

    var title: String {
        switch self {
        case .bronze: return ATHLTHLocalization.choose(english: "Bronze", norwegian: "Bronse")
        case .silver: return ATHLTHLocalization.choose(english: "Silver", norwegian: "Sølv")
        case .gold: return ATHLTHLocalization.choose(english: "Gold", norwegian: "Gull")
        }
    }

    // Bronze must be COPPER / red-brown, never amber or yellow gold.
    var highlights: [Color] {
        switch self {
        case .bronze:
            return [
                Color(red: 0.97, green: 0.66, blue: 0.47),
                Color(red: 0.71, green: 0.34, blue: 0.20),
                Color(red: 0.43, green: 0.19, blue: 0.13),
                Color(red: 0.86, green: 0.46, blue: 0.31),
                Color(red: 0.36, green: 0.15, blue: 0.12)
            ]
        case .silver:
            return [
                Color(red: 0.97, green: 0.98, blue: 1.00),
                Color(red: 0.72, green: 0.78, blue: 0.85),
                Color(red: 0.39, green: 0.45, blue: 0.54),
                Color(red: 0.87, green: 0.91, blue: 0.97),
                Color(red: 0.48, green: 0.55, blue: 0.64)
            ]
        case .gold:
            return [
                Color(red: 1.00, green: 0.95, blue: 0.61),
                Color(red: 0.99, green: 0.74, blue: 0.21),
                Color(red: 0.60, green: 0.36, blue: 0.07),
                Color(red: 0.98, green: 0.83, blue: 0.36),
                Color(red: 0.67, green: 0.40, blue: 0.09)
            ]
        }
    }

    var face: [Color] {
        switch self {
        case .bronze:
            return [
                Color(red: 0.74, green: 0.37, blue: 0.25),
                Color(red: 0.38, green: 0.17, blue: 0.12),
                Color(red: 0.55, green: 0.25, blue: 0.17)
            ]
        case .silver:
            return [
                Color(red: 0.87, green: 0.90, blue: 0.95),
                Color(red: 0.52, green: 0.58, blue: 0.67),
                Color(red: 0.71, green: 0.76, blue: 0.83)
            ]
        case .gold:
            return [
                Color(red: 0.94, green: 0.75, blue: 0.32),
                Color(red: 0.61, green: 0.40, blue: 0.10),
                Color(red: 0.80, green: 0.57, blue: 0.16)
            ]
        }
    }

    var shadow: Color {
        switch self {
        case .bronze: return Color(red: 0.30, green: 0.11, blue: 0.07)
        case .silver: return Color(red: 0.34, green: 0.41, blue: 0.51)
        case .gold: return Color(red: 0.39, green: 0.24, blue: 0.04)
        }
    }
}

extension TrophyCategory {
    var medalSystemImage: String {
        switch self {
        case .signature: return "sparkles"
        case .walking: return "mountain.2.fill"
        case .endurance: return "shoeprints.fill"
        case .strength: return "dumbbell.fill"
        case .consistency: return "flame.fill"
        case .goals: return "scope"
        case .recovery: return "heart.text.square.fill"
        case .challenges: return "flag.checkered"
        }
    }
}

struct ATHLTHMedalHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX, y = rect.minY
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: x + 0.50 * w, y: y))
        path.addLine(to: CGPoint(x: x + 0.94 * w, y: y + 0.25 * h))
        path.addLine(to: CGPoint(x: x + 0.94 * w, y: y + 0.75 * h))
        path.addLine(to: CGPoint(x: x + 0.50 * w, y: y + h))
        path.addLine(to: CGPoint(x: x + 0.06 * w, y: y + 0.75 * h))
        path.addLine(to: CGPoint(x: x + 0.06 * w, y: y + 0.25 * h))
        path.closeSubpath()
        return path
    }
}

/// One visual component for every non-prestige achievement.
struct ATHLTHMetalMedalArtwork: View {
    let trophy: TrophyProgressItem
    let size: CGFloat
    var showActivityIcon: Bool = true

    private var metal: ATHLTHMedalMetal {
        ATHLTHMedalMetal(rarity: trophy.displayRarity)
    }
    private var unlocked: Bool { trophy.isUnlocked }

    var body: some View {
        ZStack {
            ATHLTHMedalHexagon()
                .fill(LinearGradient(
                    colors: metal.highlights,
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .shadow(color: metal.shadow.opacity(unlocked ? 0.34 : 0.10),
                        radius: size * 0.075, x: 0, y: size * 0.05)

            ATHLTHMedalHexagon()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.66), .clear, metal.shadow.opacity(0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .padding(size * 0.018)

            ATHLTHMedalHexagon()
                .fill(LinearGradient(
                    colors: metal.face,
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .padding(size * 0.075)
                .shadow(color: metal.shadow.opacity(0.48), radius: size * 0.013,
                        x: 0, y: size * 0.022)

            ATHLTHMedalHexagon()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.76), metal.shadow.opacity(0.36), Color.white.opacity(0.28)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.8, size * 0.011)
                )
                .padding(size * 0.084)

            embossedCategorySymbol
                .frame(width: size * 0.48, height: size * 0.42)
                .shadow(color: metal.shadow.opacity(0.65),
                        radius: size * 0.012, x: size * 0.012, y: size * 0.025)

            if !unlocked {
                ATHLTHMedalHexagon()
                    .fill(Color(.systemBackground).opacity(0.60))
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(size * 0.11)
                    .background(.thinMaterial, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(trophy.category.title), \(metal.title)")
    }

    @ViewBuilder
    private var embossedCategorySymbol: some View {
        if trophy.category == .signature {
            ATHLTHMarkShape()
                .fill(LinearGradient(
                    colors: [metal.highlights[0], metal.highlights[1], metal.highlights[3]],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                    ATHLTHMarkShape()
                        .stroke(Color.white.opacity(0.45), lineWidth: max(0.5, size * 0.007))
                }
                .frame(width: size * 0.50, height: size * 0.31)
        } else {
            Image(systemName: trophy.category.medalSystemImage)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(LinearGradient(
                    colors: [metal.highlights[0], metal.highlights[1], metal.highlights[3]],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                    Image(systemName: trophy.category.medalSystemImage)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.white.opacity(0.24))
                        .offset(x: -size * 0.007, y: -size * 0.009)
                        .mask {
                            Image(systemName: trophy.category.medalSystemImage)
                                .resizable()
                                .scaledToFit()
                        }
                }
        }
    }
}

private struct ATHLTHGoldCupBowl: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.07, y: h * 0.06))
        path.addLine(to: CGPoint(x: w * 0.93, y: h * 0.06))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.93),
                      control1: CGPoint(x: w * 0.88, y: h * 0.74),
                      control2: CGPoint(x: w * 0.66, y: h * 0.92))
        path.addCurve(to: CGPoint(x: w * 0.07, y: h * 0.06),
                      control1: CGPoint(x: w * 0.31, y: h * 0.91),
                      control2: CGPoint(x: w * 0.11, y: h * 0.74))
        path.closeSubpath()
        return path
    }
}

private struct ATHLTHGoldCupHandles: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.30*w, y: 0.16*h))
        path.addCurve(to: CGPoint(x: 0.35*w, y: 0.81*h),
                      control1: CGPoint(x: -0.10*w, y: -0.08*h),
                      control2: CGPoint(x: 0.04*w, y: 0.76*h))
        path.move(to: CGPoint(x: 0.70*w, y: 0.16*h))
        path.addCurve(to: CGPoint(x: 0.65*w, y: 0.81*h),
                      control1: CGPoint(x: 1.10*w, y: -0.08*h),
                      control2: CGPoint(x: 0.96*w, y: 0.76*h))
        return path
    }
}

/// A sculpted trophy silhouette: actual bowl, open handles, stem and
/// pedestal, not SF Symbols' flat "trophy.fill" pictogram.
struct ATHLTHGoldPrestigeCupArtwork: View {
    let size: CGFloat
    let isUnlocked: Bool

    private let gold: [Color] = [
        Color(red: 1.00, green: 0.95, blue: 0.66),
        Color(red: 0.99, green: 0.78, blue: 0.26),
        Color(red: 0.66, green: 0.40, blue: 0.08),
        Color(red: 0.96, green: 0.73, blue: 0.20),
        Color(red: 0.99, green: 0.88, blue: 0.42)
    ]

    private var finish: LinearGradient {
        LinearGradient(colors: gold, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.19))
                .frame(width: size * 0.70, height: size * 0.075)
                .blur(radius: size * 0.040)
                .offset(y: size * 0.49)

            ATHLTHGoldCupHandles()
                .stroke(finish, style: StrokeStyle(lineWidth: size * 0.077,
                                                    lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.93, height: size * 0.52)
                .offset(y: -size * 0.19)
                .shadow(color: Color(red: 0.39, green: 0.21, blue: 0.04).opacity(0.48),
                        radius: size * 0.018, x: size * 0.01, y: size * 0.02)

            ATHLTHGoldCupBowl()
                .fill(finish)
                .frame(width: size * 0.70, height: size * 0.55)
                .overlay {
                    ATHLTHGoldCupBowl()
                        .stroke(Color.white.opacity(0.45), lineWidth: size * 0.010)
                        .frame(width: size * 0.70, height: size * 0.55)
                }
                .offset(y: -size * 0.20)
                .shadow(color: Color(red: 0.33, green: 0.18, blue: 0.03).opacity(0.43),
                        radius: size * 0.025, x: 0, y: size * 0.016)

            Ellipse()
                .fill(LinearGradient(
                    colors: [Color(red: 0.42, green: 0.25, blue: 0.07),
                             Color(red: 0.76, green: 0.51, blue: 0.12),
                             Color(red: 1.00, green: 0.91, blue: 0.51)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.67, height: size * 0.095)
                .overlay {
                    Ellipse()
                        .stroke(Color.white.opacity(0.60), lineWidth: size * 0.012)
                }
                .offset(y: -size * 0.443)

            RoundedRectangle(cornerRadius: size * 0.018)
                .fill(finish)
                .frame(width: size * 0.095, height: size * 0.26)
                .offset(y: size * 0.257)

            Ellipse()
                .fill(finish)
                .frame(width: size * 0.27, height: size * 0.09)
                .offset(y: size * 0.35)

            RoundedRectangle(cornerRadius: size * 0.022)
                .fill(finish)
                .frame(width: size * 0.48, height: size * 0.09)
                .offset(y: size * 0.415)

            RoundedRectangle(cornerRadius: size * 0.025)
                .fill(finish)
                .frame(width: size * 0.59, height: size * 0.080)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.025)
                        .stroke(Color.white.opacity(0.48), lineWidth: max(0.5, size * 0.008))
                }
                .offset(y: size * 0.475)
        }
        .frame(width: size, height: size * 1.10)
        .shadow(color: Color(red: 0.45, green: 0.25, blue: 0.06).opacity(0.22),
                radius: size * 0.063, y: size * 0.022)
        .saturation(isUnlocked ? 1 : 0)
        .opacity(isUnlocked ? 1 : 0.38)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Prestige gold trophy", norwegian: "Prestisjepokal i gull"
        ))
    }
}
