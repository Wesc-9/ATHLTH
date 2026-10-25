import SwiftUI

/// Train's editorial identity. Gold marks structure and selection; dark bronze
/// carries small text. These tokens are scoped to Train, not the global app.
enum ATHLTHTrainDesign {
    static let canvas = Color(red: 0.980, green: 0.971, blue: 0.951)
    static let paper = Color(red: 1.0, green: 0.997, blue: 0.985)
    static let ink = Color(red: 0.13, green: 0.15, blue: 0.14)
    static let inkLift = Color(red: 0.23, green: 0.25, blue: 0.21)
    static let secondary = Color(red: 0.39, green: 0.40, blue: 0.37)
    static let bronze = Color(red: 0.43, green: 0.32, blue: 0.19)
    static let gold = Color(red: 0.72, green: 0.59, blue: 0.36)
    static let paleGold = Color(red: 0.94, green: 0.90, blue: 0.81)
    static let rule = Color(red: 0.85, green: 0.82, blue: 0.74)
    static let radius: CGFloat = 24
    static let readingWidth: CGFloat = 760
    static let sectionSpacing: CGFloat = 26
    static let title = Font.system(.largeTitle, design: .serif).weight(.regular)
    static let sectionTitle = Font.system(.title2, design: .serif).weight(.medium)
}

/// A fine metallic edge, warm paper and two restrained shadows establish depth
/// without stacking material cards or obscuring the workout's content.
struct ATHLTHTrainPaper: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: ATHLTHTrainDesign.radius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [ATHLTHTrainDesign.paper, .white,
                                 ATHLTHTrainDesign.paleGold.opacity(emphasized ? 0.35 : 0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ATHLTHTrainDesign.radius, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [.white, ATHLTHTrainDesign.gold.opacity(emphasized ? 0.70 : 0.24),
                                 ATHLTHTrainDesign.rule.opacity(0.45)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: ATHLTHTrainDesign.bronze.opacity(emphasized ? 0.10 : 0.045),
                    radius: emphasized ? 22 : 12, x: 0, y: emphasized ? 10 : 5)
            .shadow(color: ATHLTHTrainDesign.ink.opacity(0.025), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func athlthTrainPaper(emphasized: Bool = false) -> some View {
        modifier(ATHLTHTrainPaper(emphasized: emphasized))
    }
}

struct ATHLTHTrainSectionHeading: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Rectangle().fill(ATHLTHTrainDesign.gold).frame(width: 24, height: 1)
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
            }
            Text(title)
                .font(ATHLTHTrainDesign.sectionTitle)
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ATHLTHTrainNavigation: View {
    @Binding var selection: ATHLTHTrainSection
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 2) {
                    compactTab(.today, title: tr("Today", "I dag"), icon: "figure.run")
                    compactTab(.plan, title: tr("Plan", "Plan"), icon: "calendar")
                    compactTab(.progress, title: tr("Progress", "Fremgang"), icon: "chart.bar.fill")
                }
                .padding(5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.08), radius: 13, y: 5)
            } else {
                HStack(spacing: 4) {
                    tab(.today, title: tr("Today", "I dag"), icon: "sun.horizon")
                    tab(.plan, title: tr("Plan", "Plan"), icon: "calendar")
                    tab(.progress, title: tr("Progress", "Fremgang"), icon: "chart.xyaxis.line")
                }
                .padding(5)
                .background(ATHLTHTrainDesign.paper, in: RoundedRectangle(cornerRadius: 19))
                .overlay {
                    RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.65), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86),
                   value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Train sections", "Treningsfaner"))
    }

    private func compactTab(_ section: ATHLTHTrainSection, title: String, icon: String) -> some View {
        let selected = selection == section
        return Button { selection = section } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.white : ATHLTHTrainDesign.ink)
            .frame(width: 59, height: 48)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(ATHLTHTrainDesign.gold)
                        .matchedGeometryEffect(id: "train-compact-selection", in: highlight)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tab(_ section: ATHLTHTrainSection, title: String, icon: String) -> some View {
        let selected = selection == section
        return Button { selection = section } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    Image(systemName: icon).accessibilityHidden(true)
                    Text(title).fixedSize()
                }
                VStack(spacing: 5) {
                    Image(systemName: icon).accessibilityHidden(true)
                    Text(title).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(selected ? Color.white : ATHLTHTrainDesign.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(ATHLTHTrainDesign.ink)
                        .matchedGeometryEffect(id: "train-selection", in: highlight)
                }
            }
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule().fill(ATHLTHTrainDesign.gold)
                        .frame(width: 22, height: 2).padding(.bottom, 6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

struct ATHLTHTrainMasthead: View {
    let title: String
    let subtitle: String
    let onLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack(alignment: .center) {
                HStack(spacing: 12) {
                    Text("ATHLTH").font(.caption.weight(.semibold)).tracking(4)
                    Rectangle().fill(ATHLTHTrainDesign.gold).frame(width: 1, height: 15)
                    Text("TRAIN").font(.caption2.weight(.medium)).tracking(2)
                }
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                Spacer(minLength: 0)
                Button(action: onLibrary) {
                    Image(systemName: "square.grid.2x2")
                        .font(.body.weight(.medium))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.7), in: Circle())
                        .overlay(Circle().strokeBorder(ATHLTHTrainDesign.rule, lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Training library", norwegian: "Treningsbibliotek"))
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(ATHLTHTrainDesign.title)
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

struct ATHLTHTrainPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(LinearGradient(
                colors: [ATHLTHTrainDesign.ink, ATHLTHTrainDesign.inkLift],
                startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 17))
            .overlay(alignment: .bottom) {
                Capsule().fill(ATHLTHTrainDesign.gold.opacity(0.8))
                    .frame(width: 42, height: 2).padding(.bottom, 7)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// A chronological spine rather than a grid of unrelated phase cards.
struct ATHLTHTrainPhaseRow: View {
    let number: Int
    let title: String
    let detail: String
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 5) {
                Text(String(format: "%02d", number))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(ATHLTHTrainDesign.gold.opacity(0.7), lineWidth: 0.8))
                if !isLast {
                    Rectangle().fill(ATHLTHTrainDesign.rule).frame(width: 1, height: 24)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                Text(detail).font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ATHLTHTrainActivityTile: View {
    let title: String
    let symbol: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.title2.weight(.light))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .accessibilityHidden(true)
            }
            Text(title).font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(LinearGradient(
                colors: [ATHLTHTrainDesign.gold, ATHLTHTrainDesign.paleGold.opacity(0.25)],
                startPoint: .leading, endPoint: .trailing)).frame(height: 1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .athlthTrainPaper()
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct ATHLTHTrainMetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Rectangle().fill(ATHLTHTrainDesign.gold.opacity(0.65)).frame(width: 1)
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: symbol).font(.body.weight(.light))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .accessibilityHidden(true)
                Text(value).font(.system(.title2, design: .serif))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Text(title).font(.caption)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
