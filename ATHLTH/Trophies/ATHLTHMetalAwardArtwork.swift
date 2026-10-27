import SwiftUI

/// ATHLTH's unified metal award language.
/// Bronze, silver and gold are material tiers, not category colours.
/// Prestige awards use a separate sculpted gold cup.
enum ATHLTHMedalMetal: CaseIterable, Hashable {
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

/// A struck metal medallion, not a flat pictogram. The concentric edge,
/// reeded rim, specular highlights and recessed die create physical depth.
/// All category medals share the same mint finish; rarity changes the alloy.
struct ATHLTHMetalMedalArtwork: View {
    let trophy: TrophyProgressItem
    let size: CGFloat
    var showActivityIcon: Bool = true
    var rarityOverride: TrophyRarity? = nil

    private var metal: ATHLTHMedalMetal {
        ATHLTHMedalMetal(rarity: rarityOverride ?? trophy.displayRarity)
    }
    private var unlocked: Bool { trophy.isUnlocked }
    private var shadow: Color { metal.shadow }

    var body: some View {
        ZStack {
            // Real medals have a thick, shadow-casting edge, not a flat hexagon.
            Circle()
                .fill(shadow.opacity(0.23))
                .frame(width: size * 0.91, height: size * 0.91)
                .blur(radius: size * 0.074)
                .offset(x: size * 0.035, y: size * 0.067)

            Circle()
                .fill(LinearGradient(
                    colors: [shadow, metal.highlights[2],
                             metal.highlights[0], metal.highlights[4]],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(size * 0.018)
                .offset(y: size * 0.033)

            Circle()
                .fill(AngularGradient(
                    colors: [
                        metal.highlights[2], metal.highlights[0],
                        metal.highlights[3], metal.highlights[4],
                        metal.highlights[1], metal.highlights[0],
                        metal.highlights[2]
                    ],
                    center: .center, startAngle: .degrees(-100),
                    endAngle: .degrees(260)))
                .padding(size * 0.025)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.94),
                                         shadow.opacity(0.50),
                                         metal.highlights[0].opacity(0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: max(0.7, size * 0.018)
                        )
                        .padding(size * 0.033)
                }

            // Tiny radial grooves make the rim read as a minted object.
            ATHLTHMedalReededEdge()
                .stroke(Color.white.opacity(0.46),
                        lineWidth: max(0.45, size * 0.005))
                .padding(size * 0.043)
                .shadow(color: shadow.opacity(0.25),
                        radius: size * 0.003, y: size * 0.003)

            Circle()
                .fill(LinearGradient(
                    colors: [metal.face[0], metal.face[1], metal.face[2]],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(size * 0.105)
                .overlay {
                    Circle()
                        .strokeBorder(shadow.opacity(0.60),
                                      lineWidth: max(0.5, size * 0.008))
                        .padding(size * 0.102)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.49),
                                      lineWidth: max(0.5, size * 0.007))
                        .padding(size * 0.126)
                }
                .shadow(color: shadow.opacity(0.46),
                        radius: size * 0.017, x: 0, y: size * 0.012)

            // Brushed-metal reflections, clipped to the recessed field.
            Circle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.22), location: 0),
                        .init(color: Color.white.opacity(0.02), location: 0.34),
                        .init(color: shadow.opacity(0.18), location: 0.63),
                        .init(color: Color.white.opacity(0.12), location: 1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(size * 0.13)

            if size >= 73 {
                // Stamped maker's mark and tier—engraving is deliberately
                // restrained so the silhouette stays readable on small cards.
                Text("ATHLTH")
                    .font(.system(size: size * 0.074, weight: .heavy, design: .rounded))
                    .tracking(size * 0.008)
                    .foregroundStyle(metal.highlights[0].opacity(0.76))
                    .shadow(color: shadow.opacity(0.65),
                            radius: 0.3, x: 0, y: 0.8)
                    .offset(y: -size * 0.245)

                Text(metal.title.uppercased())
                    .font(.system(size: size * 0.065, weight: .bold, design: .rounded))
                    .tracking(size * 0.006)
                    .foregroundStyle(metal.highlights[0].opacity(0.72))
                    .shadow(color: shadow.opacity(0.58),
                            radius: 0.4, x: 0, y: 0.7)
                    .offset(y: size * 0.255)
            }

            if showActivityIcon {
                embossedCategorySymbol
                    .frame(width: size * 0.37, height: size * 0.36)
            } else {
                ATHLTHMarkShape()
                    .fill(LinearGradient(
                        colors: [metal.highlights[0], metal.highlights[3],
                                 metal.highlights[2]],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.32, height: size * 0.22)
                    .shadow(color: shadow.opacity(0.62),
                            radius: size * 0.010, y: size * 0.012)
            }

            if !unlocked {
                Circle()
                    .fill(Color.black.opacity(0.34))
                    .padding(size * 0.03)
                Circle()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    .padding(size * 0.065)
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
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
                    colors: [metal.highlights[0], metal.highlights[3],
                             metal.highlights[2]],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    ATHLTHMarkShape()
                        .stroke(Color.white.opacity(0.60),
                                lineWidth: max(0.5, size * 0.006))
                }
                .shadow(color: shadow.opacity(0.72),
                        radius: size * 0.014,
                        x: size * 0.010, y: size * 0.020)
        } else {
            Image(systemName: trophy.category.medalSystemImage)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(LinearGradient(
                    colors: [metal.highlights[0], metal.highlights[3],
                             metal.highlights[2]],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Image(systemName: trophy.category.medalSystemImage)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.white.opacity(0.32))
                        .offset(x: -size * 0.009, y: -size * 0.011)
                        .mask {
                            Image(systemName: trophy.category.medalSystemImage)
                                .resizable().scaledToFit()
                        }
                }
                .shadow(color: shadow.opacity(0.82),
                        radius: size * 0.012,
                        x: size * 0.010, y: size * 0.022)
        }
    }
}

/// One Canvas path instead of dozens of per-medal SwiftUI views.
private struct ATHLTHMedalReededEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for tick in 0..<80 {
            let a = Double(tick) * .pi * 2 / 80
            let inner = radius * 0.893
            let outer = radius * 0.978
            path.move(to: CGPoint(
                x: center.x + cos(a) * inner,
                y: center.y + sin(a) * inner))
            path.addLine(to: CGPoint(
                x: center.x + cos(a) * outer,
                y: center.y + sin(a) * outer))
        }
        return path
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
