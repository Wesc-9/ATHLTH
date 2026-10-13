import SwiftUI

/// Shared first step for personal planning, direct partner invites and
/// Train Together. Every choice continues into the same SessionEditorView.
struct WorkoutPlanningSourceCard: View {
    let context: String
    let onCreateNew: () -> Void
    let onUsePlanned: () -> Void
    let onTrainTogether: (() -> Void)?

    init(
        context: String,
        onCreateNew: @escaping () -> Void,
        onUsePlanned: @escaping () -> Void,
        onTrainTogether: (() -> Void)? = nil
    ) {
        self.context = context
        self.onCreateNew = onCreateNew
        self.onUsePlanned = onUsePlanned
        self.onTrainTogether = onTrainTogether
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ATHLTH · PLAN")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.2)
                    .foregroundStyle(ATHLTHTheme.accentDeep)

                Text(ATHLTHLocalization.choose(
                    english: "How do you want to start?",
                    norwegian: "Hvordan vil du starte?"
                ))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 1)

            HStack(alignment: .top, spacing: 12) {
                sourceTile(
                    title: ATHLTHLocalization.choose(
                        english: "Start from scratch",
                        norwegian: "Fra bunnen av"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Build a new workout with all the planning options.",
                        norwegian: "Bygg en ny økt med alle planleggingsvalgene."
                    ),
                    icon: "plus.circle.fill",
                    imageName: "GoalRunning",
                    tint: ATHLTHTheme.vitality,
                    action: onCreateNew
                )

                sourceTile(
                    title: ATHLTHLocalization.choose(
                        english: "Use a planned workout",
                        norwegian: "Bruk planlagt økt"
                    ),
                    subtitle: ATHLTHLocalization.choose(
                        english: "Choose and adjust a workout you've already planned.",
                        norwegian: "Hent og tilpass en økt du allerede har planlagt."
                    ),
                    icon: "calendar",
                    imageName: "GoalStrength",
                    tint: ATHLTHTheme.accentDeep,
                    action: onUsePlanned
                )
            }

            if let onTrainTogether {
                Button(action: onTrainTogether) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 45, height: 45)
                            .background(
                                ATHLTHTheme.accentSoft.opacity(0.75),
                                in: RoundedRectangle(cornerRadius: 14)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(ATHLTHLocalization.choose(
                                english: "Train together",
                                norwegian: "Tren sammen"
                            ))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                            Text(ATHLTHLocalization.choose(
                                english: "Plan a workout with someone in ATHLTH.",
                                norwegian: "Planlegg en økt med noen i ATHLTH."
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 3)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.white.opacity(0.86),
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ATHLTHTheme.border.opacity(0.65), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Plan a workout together",
                    norwegian: "Planlegg en økt sammen"
                ))
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 21)

                Text(ATHLTHLocalization.choose(
                    english: "Tip: You can change the type, time, exercises and other details in the next step.",
                    norwegian: "Tips: Du kan endre type, tid, øvelser og andre detaljer i neste steg."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTheme.surfaceStone.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .padding(.horizontal, 2)
    }

    /// Full-bleed portrait photo cards matching the selected start design.
    /// The bright upper gradient keeps titles legible over any goal artwork,
    /// while the lower image stays visible all the way to the rounded edges.
    private func sourceTile(
        title: String,
        subtitle: String,
        icon: String,
        imageName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.94), location: 0),
                            .init(color: Color.white.opacity(0.91), location: 0.25),
                            .init(color: Color.white.opacity(0.78), location: 0.44),
                            .init(color: Color.white.opacity(0.26), location: 0.66),
                            .init(color: Color.clear, location: 0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    LinearGradient(
                        colors: [
                            tint.opacity(0.07),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 43, height: 43)
                            .background(Color.white.opacity(0.94), in: Circle())

                        Text(title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 17)

                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.primaryText.opacity(0.78))
                            .lineLimit(4)
                            .minimumScaleFactor(0.86)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 6)

                        Spacer(minLength: 12)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 43, height: 43)
                            .background(
                                Color.white.opacity(0.97),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                            }
                    }
                    .padding(15)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .topLeading
                    )
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                }
            }
            .frame(height: 315)
            .contentShape(
                RoundedRectangle(cornerRadius: 23, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .frame(maxWidth: .infinity)
    }
}
