import SwiftUI

/// Calendar starts are direct on tap. Holding either device gives access to
/// the existing prepared-Watch and foreground deferred-start flows.
struct HomeDailyRecommendedWorkoutActions: View {
    let isPlanWorkout: Bool
    let canStartWithWatch: Bool
    let onOpenPlannedWorkout: () -> Void
    let onStartOnPhone: () -> Void
    let onStartOnWatch: () -> Void
    var onSendToWatch: (() -> Void)? = nil
    var onDelayOnPhone: ((TimeInterval) -> Void)? = nil
    var onDelayOnWatch: (() -> Void)? = nil

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        if isPlanWorkout {
            Button(action: onOpenPlannedWorkout) {
                Label(tr("Open workout and start", "Åpne økten og start"),
                      systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.white)
                    .background(ATHLTHTrainDesign.bronze,
                                in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                startDeviceButton(
                    title: "iPhone",
                    symbol: "iphone",
                    primary: true,
                    enabled: true,
                    action: onStartOnPhone
                )
                .contextMenu { moreStartOptions(watchButton: false) }

                startDeviceButton(
                    title: "Apple Watch",
                    symbol: "applewatch",
                    primary: false,
                    enabled: canStartWithWatch,
                    action: onStartOnWatch
                )
                .contextMenu { moreStartOptions(watchButton: true) }
            }
            .accessibilityIdentifier("athlth-calendar-inline-device-starts")
        }
    }

    private func startDeviceButton(
        title: String,
        symbol: String,
        primary: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Text(enabled
                     ? tr("Hold for more", "Hold for flere valg")
                     : tr("Unavailable", "Ikke tilgjengelig"))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(primary ? Color.white : ATHLTHTrainDesign.ink)
            .background(primary
                ? ATHLTHTrainDesign.bronze
                : Color.white.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(ATHLTHTrainDesign.bronze.opacity(primary ? 0 : 0.27),
                                  lineWidth: 0.8)
            }
            .opacity(enabled ? 1 : 0.52)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(tr("Start with", "Start med") + " " + title)
        .accessibilityHint(tr(
            "Tap to start. Hold to send the workout or delay starting.",
            "Trykk for å starte. Hold inne for å sende eller utsette økten."
        ))
    }

    @ViewBuilder
    private func moreStartOptions(watchButton: Bool) -> some View {
        if canStartWithWatch, let onSendToWatch {
            Button(action: onSendToWatch) {
                Label(tr("Send workout to Apple Watch",
                         "Send økt til Apple Watch"), systemImage: "applewatch")
            }
        }
        if watchButton && canStartWithWatch, let onDelayOnWatch {
            Button(action: onDelayOnWatch) {
                Label(tr("Start on Watch in 30 seconds",
                         "Start på Watch om 30 sekunder"), systemImage: "timer")
            }
        }
        if let onDelayOnPhone {
            Menu {
                ForEach([30, 120, 300, 600], id: \.self) { seconds in
                    Button {
                        onDelayOnPhone(TimeInterval(seconds))
                    } label: {
                        Text(seconds == 30
                             ? tr("30 seconds", "30 sekunder")
                             : tr("\(seconds / 60) minutes",
                                  "\(seconds / 60) minutter"))
                    }
                }
            } label: {
                Label(tr("Delay iPhone start", "Utsett start på iPhone"),
                      systemImage: "clock")
            }
        }
    }
}
