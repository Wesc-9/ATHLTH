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

    private func sourceTile(
        title: String,
        subtitle: String,
        icon: String,
        imageName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 41, height: 41)
                    .background(Color.white.opacity(0.9), in: Circle())

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 12)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 5)

                Spacer(minLength: 10)

                GeometryReader { geometry in
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.96), in: Circle())
                                .padding(9)
                        }
                }
                .frame(height: 115)
                .clipShape(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 275)
            .background {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                tint.opacity(0.13),
                                Color.white.opacity(0.89)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .frame(maxWidth: .infinity)
    }
}
