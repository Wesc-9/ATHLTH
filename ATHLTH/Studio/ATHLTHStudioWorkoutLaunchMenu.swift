import SwiftUI

/// iPad presentation of the same validated workout actions used by iPhone
/// Today. The callbacks must route through the owning Train launch engine;
/// this modifier never starts HealthKit or Watch sessions on its own.
struct ATHLTHStudioWorkoutLaunchMenu: ViewModifier {
    let canLaunch: Bool
    let supportsWatch: Bool
    let onStart: () -> Void
    let onSendToWatch: () -> Void
    let onDelay: (TimeInterval) -> Void
    let onDetails: () -> Void

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if canLaunch {
                    Button(action: onStart) {
                        Label(tr("Start now on iPhone", "Start nå på iPhone"),
                              systemImage: "iphone")
                    }
                    if supportsWatch {
                        Button(action: onSendToWatch) {
                            Label(tr("Send to Apple Watch", "Send til Apple Watch"),
                                  systemImage: "applewatch")
                        }
                    }
                    Menu {
                        ForEach([30, 60, 300, 600], id: \.self) { seconds in
                            Button {
                                onDelay(TimeInterval(seconds))
                            } label: {
                                Text(seconds == 30
                                     ? tr("30 seconds", "30 sekunder")
                                     : tr("\(seconds / 60) minutes",
                                          "\(seconds / 60) minutter"))
                            }
                        }
                    } label: {
                        Label(tr("Start later", "Start om X tid"),
                              systemImage: "clock")
                    }
                }

                Button(action: onDetails) {
                    Label(tr("Workout details", "Øktdetaljer"),
                          systemImage: "info.circle")
                }
            }
    }
}
