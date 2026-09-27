import SwiftUI

struct ATHLTHWidgetsAndSurfacesSettingsView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ATHLTHTheme.canvasTop,
                    ATHLTHTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    ForEach(ATHLTHExternalSurface.allCases) { surface in
                        surfaceCard(surface)
                    }

                    availabilityNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Widgets & Surfaces")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATHLTH EVERYWHERE")
                .font(.caption2.weight(.bold))
                .tracking(2.1)
                .foregroundStyle(ATHLTHTheme.vitality)

            Text("Widgets & Surfaces")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)

            Text(
                "This is the home for how ATHLTH appears outside the app — on your Home Screen, during live workouts, through Siri and on the Lock Screen."
            )
            .font(.subheadline)
            .foregroundStyle(ATHLTHTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func surfaceCard(
        _ surface: ATHLTHExternalSurface
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: surface.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(surface.tint)
                        .frame(width: 46, height: 46)
                        .background(
                            surface.tint.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(surface.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(surface.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text("Planned")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            ATHLTHTheme.vitalitySoft,
                            in: Capsule()
                        )
                }

                preview(for: surface)
            }
        }
    }

    @ViewBuilder
    private func preview(
        for surface: ATHLTHExternalSurface
    ) -> some View {
        switch surface {
        case .homeScreen:
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Recovery", systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                    Text("82")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                    Text("Good")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                ProgressView(value: 0.82)
                    .tint(ATHLTHTheme.vitality)
                    .frame(maxWidth: 130)
            }
            .padding(14)
            .background(
                ATHLTHTheme.surfaceSage,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

        case .liveActivity:
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .foregroundStyle(.green)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Outdoor Run")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.76))
                    Text("32:18")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("5.2 km")
                    Text("5:56 /km")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 16)
            .frame(height: 72)
            .background(
                Color.black,
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )

        case .siriShortcuts:
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.recoveryBlue)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.recoveryBlueSoft,
                        in: Circle()
                    )

                Text("“What’s my recovery today?”")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer()
            }
            .padding(14)
            .background(
                ATHLTHTheme.surfaceStone,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

        case .lockScreen:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("9:41")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text("Recovery 82")
                        .font(.caption.weight(.semibold))
                }

                Divider()
                    .frame(height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Label("In progress", systemImage: "figure.run")
                        .font(.caption)
                    Text("32:18")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                }

                Spacer()
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.accentDeep,
                        ATHLTHTheme.vitality
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
    }

    private var availabilityNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(ATHLTHTheme.accentDeep)

            VStack(alignment: .leading, spacing: 4) {
                Text("Settings hub ready")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(
                    "These entries are intentionally marked Planned until their iOS integrations are implemented. Nothing here pretends a widget, Live Activity, Siri shortcut or Lock Screen widget is already active."
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            ATHLTHTheme.champagneSoft,
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }
}

private enum ATHLTHExternalSurface: String, CaseIterable, Identifiable {
    case homeScreen
    case liveActivity
    case siriShortcuts
    case lockScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homeScreen:
            return "Home Screen Widget"
        case .liveActivity:
            return "Live Activity"
        case .siriShortcuts:
            return "Siri & Shortcuts"
        case .lockScreen:
            return "Lock Screen"
        }
    }

    var subtitle: String {
        switch self {
        case .homeScreen:
            return "Recovery, your next session and key insights at a glance."
        case .liveActivity:
            return "Follow an active workout from the Lock Screen and Dynamic Island."
        case .siriShortcuts:
            return "Ask for insights, start workouts and use ATHLTH from Shortcuts."
        case .lockScreen:
            return "Surface recovery, the next session and live workout status without opening the app."
        }
    }

    var systemImage: String {
        switch self {
        case .homeScreen:
            return "rectangle.grid.2x2"
        case .liveActivity:
            return "dot.radiowaves.left.and.right"
        case .siriShortcuts:
            return "waveform"
        case .lockScreen:
            return "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .homeScreen:
            return ATHLTHTheme.vitality
        case .liveActivity:
            return ATHLTHTheme.accentDeep
        case .siriShortcuts:
            return ATHLTHTheme.recoveryBlue
        case .lockScreen:
            return ATHLTHTheme.primaryText
        }
    }
}
