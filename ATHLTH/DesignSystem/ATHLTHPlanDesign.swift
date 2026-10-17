import SwiftUI

/// A single visual contract for the training-plan experience.
/// Uses the existing ATHLTH brand palette instead of introducing a second app theme.
enum ATHLTHPlanDesign {
    static let canvas = Color(red: 0.991, green: 0.986, blue: 0.979)
    static let ink = ATHLTHTheme.primaryText
    static let secondaryInk = Color(red: 0.43, green: 0.42, blue: 0.41)
    static let accent = ATHLTHTheme.premiumGold
    static let outline = ATHLTHTheme.accentDeep.opacity(0.10)
    static let surface = Color.white
    static let selectedSurface = accent.opacity(0.085)
    static let cardRadius: CGFloat = 20
    static let fieldRadius: CGFloat = 14
    static let minTapHeight: CGFloat = 48
    static let maxContentWidth: CGFloat = 720

    enum Density: String, CaseIterable, Identifiable {
        case comfortable
        case compact
        var id: String { rawValue }
        var cardPadding: CGFloat { self == .comfortable ? 18 : 13 }
        var stackSpacing: CGFloat { self == .comfortable ? 16 : 10 }
        var title: String {
            switch self {
            case .comfortable:
                return ATHLTHLocalization.choose(english: "Comfortable", norwegian: "Luftig")
            case .compact:
                return ATHLTHLocalization.choose(english: "Compact", norwegian: "Kompakt")
            }
        }
    }
}

/// Reusable low-cost plan surface. Ghost depth is deliberately restrained;
/// content and accessibility contrast always take priority over blur effects.
struct ATHLTHPlanSurface<Content: View>: View {
    var highlighted = false
    var ghost = true
    var density: ATHLTHPlanDesign.Density = .comfortable
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: density.stackSpacing) {
            content
        }
        .padding(density.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ATHLTHPlanDesign.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ATHLTHPlanDesign.surface,
                            ghost ? ATHLTHTheme.cardWarm.opacity(0.38) : .white
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: ATHLTHPlanDesign.cardRadius, style: .continuous)
                .stroke(
                    highlighted ? ATHLTHPlanDesign.accent.opacity(0.65)
                        : ATHLTHPlanDesign.outline,
                    lineWidth: highlighted ? 1.2 : 0.8
                )
        }
        .shadow(
            color: ghost ? ATHLTHTheme.accentDeep.opacity(0.055) : .clear,
            radius: ghost ? 13 : 0,
            x: 0,
            y: ghost ? 6 : 0
        )
    }
}

/// Unified warm chrome used by every nested plan surface, including Studio.
struct ATHLTHPlanCardChrome: ViewModifier {
    var radius: CGFloat = ATHLTHPlanDesign.cardRadius
    var warm = true

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            ATHLTHPlanDesign.surface,
                            warm ? ATHLTHTheme.cardWarm.opacity(0.38) : ATHLTHPlanDesign.surface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(ATHLTHPlanDesign.outline, lineWidth: 0.8)
            }
            .shadow(color: ATHLTHTheme.accentDeep.opacity(warm ? 0.055 : 0.035),
                    radius: warm ? 13 : 9, y: warm ? 6 : 3)
    }
}

extension View {
    func athlthPlanCard(radius: CGFloat = ATHLTHPlanDesign.cardRadius,
                        warm: Bool = true) -> some View {
        modifier(ATHLTHPlanCardChrome(radius: radius, warm: warm))
    }
}

/// Reused by the first-step mode picker and the source chooser.
struct ATHLTHPlanSelectionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    var selected = false
    var accent: Color = ATHLTHPlanDesign.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ATHLTHPlanSurface(highlighted: selected) {
                HStack(alignment: .center, spacing: 15) {
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(selected ? .white : accent)
                        .frame(width: 48, height: 48)
                        .background(
                            selected ? ATHLTHTheme.accentDeep : accent.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selected ? accent : ATHLTHPlanDesign.secondaryInk)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: ATHLTHPlanDesign.minTapHeight)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ". " + subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Debug-only entry point is hosted by the plan builder. Uses the very same
/// production components and tokens, but never changes the user's saved plan.
struct ATHLTHPlanDesignLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var density: ATHLTHPlanDesign.Density = .comfortable
    @State private var ghost = true
    @State private var preview = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(ATHLTHLocalization.choose(
                        english: "Preview the visual system without editing a real training plan.",
                        norwegian: "Forhåndsvis designet uten å endre en ekte treningsplan."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    Picker("Preview", selection: $preview) {
                        Text(ATHLTHLocalization.choose(english: "Plan", norwegian: "Plan")).tag(0)
                        Text(ATHLTHLocalization.choose(english: "Week", norwegian: "Uke")).tag(1)
                        Text(ATHLTHLocalization.choose(english: "Insights", norwegian: "Innsikt")).tag(2)
                    }
                    .pickerStyle(.segmented)

                    Picker(ATHLTHLocalization.choose(english: "Layout", norwegian: "Oppsett"), selection: $density) {
                        ForEach(ATHLTHPlanDesign.Density.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(
                        ATHLTHLocalization.choose(english: "Ghost depth", norwegian: "Ghost-dybde"),
                        isOn: $ghost
                    )
                    .tint(ATHLTHTheme.accentDeep)

                    ATHLTHPlanSurface(ghost: ghost, density: density) {
                        Text(preview == 0 ? "ATHLTH / PLAN" :
                             (preview == 1 ? "ATHLTH / WEEK" : "ATHLTH / INSIGHTS"))
                            .font(.caption2.weight(.semibold))
                            .tracking(2)
                            .foregroundStyle(ATHLTHPlanDesign.accent)

                        Text(preview == 0
                            ? ATHLTHLocalization.choose(english: "Stronger and faster", norwegian: "Sterkere og raskere")
                            : preview == 1
                            ? ATHLTHLocalization.choose(english: "Your training week", norwegian: "Din treningsuke")
                            : ATHLTHLocalization.choose(english: "Your progress", norwegian: "Din fremgang"))
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                        if preview == 0 {
                            Label("8 " + ATHLTHLocalization.choose(english: "weeks", norwegian: "uker"), systemImage: "calendar")
                        } else if preview == 1 {
                            Label(ATHLTHLocalization.choose(english: "Strength · Monday", norwegian: "Styrke · mandag"), systemImage: "dumbbell")
                            Label(ATHLTHLocalization.choose(english: "Intervals · Wednesday", norwegian: "Intervaller · onsdag"), systemImage: "figure.run")
                        } else {
                            Text("83 %")
                                .font(.system(size: 34, weight: .medium, design: .rounded))
                            ProgressView(value: 0.83)
                                .tint(ATHLTHPlanDesign.accent)
                        }
                    }
                    ATHLTHPlanSelectionCard(
                        title: ATHLTHLocalization.choose(english: "Advanced", norwegian: "Avansert"),
                        subtitle: ATHLTHLocalization.choose(
                            english: "Full control of weeks, sessions and exercises.",
                            norwegian: "Full kontroll på uker, økter og øvelser."
                        ),
                        symbol: "slider.horizontal.3",
                        selected: true,
                        action: {}
                    )
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: ATHLTHPlanDesign.maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Plan Design Lab", norwegian: "Plan Design Lab"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Done", norwegian: "Ferdig")) {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}


/// Shared plan-styled launch control for all Quick Train setup sheets.
/// The recorder is chosen by the actual launch action, not by an earlier
/// selection that could silently start a different device.
struct ATHLTHQuickStartDeviceLaunchBar: View {
    let watchAvailable: Bool
    let onIPhone: () -> Void
    let onAppleWatch: () -> Void
    /// Highlight Watch as the preferred option when it is genuinely paired.
    /// The iPhone action remains fully available and explicit.
    var preferAppleWatch: Bool = false
    var supportingText: String? = nil
    var canStart: Bool = true

    private func label(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label("START WORKOUT WITH", "START ØKT MED"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.25)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

            HStack(spacing: 10) {
                launchButton(
                    title: "iPhone",
                    icon: "iphone",
                    primary: !(preferAppleWatch && watchAvailable),
                    enabled: canStart,
                    action: onIPhone
                )
                launchButton(
                    title: "Apple Watch",
                    icon: "applewatch",
                    primary: preferAppleWatch && watchAvailable,
                    enabled: watchAvailable && canStart,
                    action: onAppleWatch
                )
            }

            if !canStart {
                Label(
                    label(
                        "Choose a route or workout above before starting.",
                        "Velg rute eller treningsøkt ovenfor før du starter."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            if !watchAvailable {
                Label(
                    label(
                        "Apple Watch is not ready. Check it under Settings > Health & connections > Watch, or start with iPhone.",
                        "Apple Watch er ikke klar. Kontroller den under Innstillinger > Helse og tilkoblinger > Watch, eller start med iPhone."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let supportingText {
                Text(supportingText)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            ATHLTHPlanDesign.outline.frame(height: 1)
        }
    }

    private func launchButton(
        title: String,
        icon: String,
        primary: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
                if !enabled {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.medium))
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(
                !enabled
                    ? ATHLTHPlanDesign.secondaryInk.opacity(0.65)
                    : primary ? Color.white : ATHLTHPlanDesign.ink
            )
            .background(
                !enabled
                    ? ATHLTHPlanDesign.outline.opacity(0.45)
                    : primary ? ATHLTHPlanDesign.ink : ATHLTHPlanDesign.surface,
                in: RoundedRectangle(
                    cornerRadius: ATHLTHPlanDesign.fieldRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ATHLTHPlanDesign.fieldRadius,
                    style: .continuous
                )
                .stroke(
                    primary ? Color.clear : ATHLTHPlanDesign.outline,
                    lineWidth: 1
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            label("Start with", "Start med") + " " + title
        )
        .accessibilityHint(
            enabled
                ? label(
                    "Starts the current workout with this recording device.",
                    "Starter denne økten med valgt registreringsenhet."
                )
                : !canStart
                    ? label(
                        "Choose a workout or route before starting.",
                        "Velg en økt eller rute før du starter."
                    )
                    : label(
                        "Apple Watch is not ready. Check it in Settings.",
                        "Apple Watch er ikke klar. Kontroller klokken i Innstillinger."
                    )
        )
    }
}
