import SwiftUI

/// One finish-confirmation experience across sports. Each recording engine
/// still owns its own save, HealthKit close-out and detailed results screen.
struct ATHLTHWorkoutFinishMetric: Identifiable {
    let title: String
    let value: String
    let symbol: String
    var id: String { title + "|" + symbol }
}

struct ATHLTHWorkoutFinishSheet: View {
    let metrics: [ATHLTHWorkoutFinishMetric]
    let progress: Double?
    let remainingWarning: String?
    let saveExplanation: String
    let saving: Bool
    let onFinish: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(ATHLTHTrainDesign.bronze)
                        .frame(width: 52, height: 52)
                        .background(ATHLTHTrainDesign.paleGold.opacity(0.56),
                                    in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ATHLTHLocalization.choose(
                            english: "Finish your workout?",
                            norwegian: "Avslutte treningsøkten?"
                        ))
                        .font(.system(size: 27, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHTrainDesign.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Review your progress before saving.",
                            norwegian: "Se over økten før du lagrer."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTrainDesign.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 16) {
                        ForEach(metrics) { metric in
                            VStack(alignment: .leading, spacing: 7) {
                                Label(metric.title, systemImage: metric.symbol)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                                Text(metric.value)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(ATHLTHTrainDesign.ink)
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let progress {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ATHLTHTrainDesign.rule.opacity(0.65))
                                Capsule().fill(ATHLTHTrainDesign.gold)
                                    .frame(width: geometry.size.width *
                                        min(max(progress, 0), 1))
                            }
                        }
                        .frame(height: 5)
                        .accessibilityHidden(true)
                    }
                    if let remainingWarning {
                        Label(remainingWarning, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTrainDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .athlthTrainPaper()

                Label(saveExplanation, systemImage: "heart.text.square")
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 21)
            .padding(.top, 25)
            .padding(.bottom, 18)
        }
        .background(ATHLTHTrainDesign.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button(action: onFinish) {
                    HStack(spacing: 10) {
                        if saving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(ATHLTHLocalization.choose(
                            english: "Finish and save workout",
                            norwegian: "Avslutt og lagre økten"
                        ))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        LinearGradient(
                            colors: [ATHLTHTrainDesign.bronze, ATHLTHTrainDesign.gold],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                }
                .buttonStyle(.plain)
                .disabled(saving)

                Button(action: onContinue) {
                    Text(ATHLTHLocalization.choose(
                        english: "Keep training", norwegian: "Fortsett treningen"
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.ink)
                    .frame(maxWidth: .infinity, minHeight: 43)
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
            .padding(.horizontal, 21)
            .padding(.top, 13)
            .padding(.bottom, 8)
            .background(ATHLTHTrainDesign.canvas)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
