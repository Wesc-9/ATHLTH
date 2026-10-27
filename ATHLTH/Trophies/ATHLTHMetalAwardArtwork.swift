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
struct ATHLTHMedalReededEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for tick in 0..<80 {
            let a = Double(tick) * .pi * 2 / 80
            let inner = radius * 0.893
            let outer = radius * 0.978
            path.move(to: CGPoint(
                x: center.x + CGFloat(cos(a)) * inner,
                y: center.y + CGFloat(sin(a)) * inner))
            path.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(a)) * outer,
                y: center.y + CGFloat(sin(a)) * outer))
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

/// Raised handles, hollow rim, spun-metal bowl, fitted stem and engraved
/// basalt pedestal give each prestige cup the proportions of an actual award.
/// Gold remains reserved for earned prestige achievements, not regular medals.
struct ATHLTHGoldPrestigeCupArtwork: View {
    let size: CGFloat
    let isUnlocked: Bool

    private let brass = Color(red: 0.54, green: 0.31, blue: 0.065)
    private let warmGold = Color(red: 0.86, green: 0.65, blue: 0.28)
    private let polishedGold = Color(red: 1.00, green: 0.91, blue: 0.64)
    private let nearBlack = Color(red: 0.12, green: 0.12, blue: 0.14)

    private var spunGold: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: brass, location: 0),
                .init(color: polishedGold, location: 0.18),
                .init(color: warmGold, location: 0.35),
                .init(color: Color(red: 0.58, green: 0.36, blue: 0.09), location: 0.61),
                .init(color: polishedGold, location: 0.79),
                .init(color: brass, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(nearBlack.opacity(0.20))
                .frame(width: size * 0.78, height: size * 0.060)
                .blur(radius: size * 0.05)
                .offset(y: size * 0.54)

            // Cast brass handles, highlighted on their outer edge.
            ATHLTHGoldCupHandles()
                .stroke(
                    LinearGradient(
                        colors: [brass, polishedGold, warmGold, brass],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: size * 0.082,
                                       lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.91, height: size * 0.52)
                .offset(y: -size * 0.20)
                .shadow(color: brass.opacity(0.58),
                        radius: size * 0.020, x: size * 0.018, y: size * 0.018)
            ATHLTHGoldCupHandles()
                .stroke(Color.white.opacity(0.40),
                        style: StrokeStyle(lineWidth: size * 0.018,
                                           lineCap: .round))
                .frame(width: size * 0.91, height: size * 0.52)
                .offset(x: -size * 0.011, y: -size * 0.216)

            // Interior lip makes the bowl look hollow rather than like a filled
            // SF Symbol. The reeded seam catches a separate specular light.
            ATHLTHGoldCupBowl()
                .fill(spunGold)
                .frame(width: size * 0.72, height: size * 0.55)
                .overlay {
                    ATHLTHGoldCupBowl()
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.20), .clear,
                                     brass.opacity(0.28)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: size * 0.72, height: size * 0.55)
                }
                .overlay {
                    ATHLTHGoldCupBowl()
                        .stroke(polishedGold.opacity(0.50),
                                lineWidth: max(0.65, size * 0.008))
                        .frame(width: size * 0.72, height: size * 0.55)
                }
                .offset(y: -size * 0.20)
                .shadow(color: brass.opacity(0.52),
                        radius: size * 0.025, x: 0, y: size * 0.020)

            // Narrow glancing reflection, clipped to the curved bowl surface.
            Capsule()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.60), .white.opacity(0.04)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.070, height: size * 0.34)
                .rotationEffect(.degrees(13))
                .offset(x: -size * 0.155, y: -size * 0.206)
                .mask {
                    ATHLTHGoldCupBowl()
                        .frame(width: size * 0.72, height: size * 0.55)
                        .offset(y: -size * 0.20)
                }

            Ellipse()
                .fill(LinearGradient(
                    colors: [nearBlack.opacity(0.80), brass,
                             warmGold, polishedGold, brass],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.68, height: size * 0.088)
                .overlay {
                    Ellipse()
                        .strokeBorder(polishedGold.opacity(0.79),
                                      lineWidth: max(0.7, size * 0.011))
                }
                .offset(y: -size * 0.447)

            // Raised centre boss and turned brass neck.
            Circle()
                .fill(RadialGradient(
                    colors: [polishedGold, warmGold, brass],
                    center: .topLeading, startRadius: 0,
                    endRadius: size * 0.20))
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(y: size * 0.09)

            RoundedRectangle(cornerRadius: size * 0.025)
                .fill(spunGold)
                .frame(width: size * 0.10, height: size * 0.25)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.025)
                        .stroke(brass.opacity(0.65), lineWidth: 0.7)
                        .frame(width: size * 0.10, height: size * 0.25)
                }
                .offset(y: size * 0.225)

            Ellipse()
                .fill(spunGold)
                .frame(width: size * 0.32, height: size * 0.090)
                .offset(y: size * 0.36)

            RoundedRectangle(cornerRadius: size * 0.018)
                .fill(spunGold)
                .frame(width: size * 0.49, height: size * 0.074)
                .offset(y: size * 0.400)

            // Weighty, non-golden base supports the cup physically.
            RoundedRectangle(cornerRadius: size * 0.033)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.30, green: 0.29, blue: 0.28),
                        Color(red: 0.12, green: 0.13, blue: 0.14),
                        Color(red: 0.23, green: 0.22, blue: 0.22)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.60, height: size * 0.145)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.033)
                        .strokeBorder(Color.white.opacity(0.22),
                                      lineWidth: max(0.6, size * 0.007))
                        .frame(width: size * 0.60, height: size * 0.145)
                }
                .offset(y: size * 0.470)

            RoundedRectangle(cornerRadius: size * 0.009)
                .fill(LinearGradient(
                    colors: [brass, warmGold, polishedGold, brass],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.39, height: size * 0.075)
                .overlay {
                    if size >= 78 {
                        Text("ATHLTH")
                            .font(.system(size: size * 0.057,
                                          weight: .heavy, design: .rounded))
                            .tracking(size * 0.006)
                            .foregroundStyle(nearBlack.opacity(0.92))
                    }
                }
                .offset(y: size * 0.471)
        }
        .frame(width: size, height: size * 1.10)
        .saturation(isUnlocked ? 0.92 : 0)
        .opacity(isUnlocked ? 1 : 0.35)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Prestige gold trophy", norwegian: "Prestisjepokal i gull"))
    }
}

