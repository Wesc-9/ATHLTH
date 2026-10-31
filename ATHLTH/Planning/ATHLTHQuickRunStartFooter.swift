import SwiftUI

/// One Quick Run start bar. A tap launches now; holding either button
/// opens the existing immediate, countdown and delayed-start choices.
struct ATHLTHQuickRunStartFooter: View {
    let watchAvailable: Bool
    let canStart: Bool
    let starting: Bool
    let scheduledDate: Date?
    let onIPhoneNow: () -> Void
    let onWatchNow: () -> Void
    let onWatchCountDown: () -> Void
    let onWatchManual: () -> Void
    let onDelay: (WorkoutCaptureDevice, Int) -> Void
    let onCancelDelay: () -> Void

    @State private var customDevice: WorkoutCaptureDevice = .iPhone
    @State private var customMinutes = 2
    @State private var showingCustomDelay = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(ATHLTHLocalization.choose(
                english: "START WORKOUT WITH", norwegian: "START ØKT MED"
            ))
            .font(.system(size: 10, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(ATHLTHTrainDesign.secondary)

            HStack(spacing: 10) {
                deviceButton(.iPhone, label: "iPhone", icon: "iphone")
                deviceButton(.appleWatch, label: "Apple Watch", icon: "applewatch")
            }

            if let scheduledDate {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Text(ATHLTHLocalization.choose(
                        english: "Starts at ", norwegian: "Starter kl. "
                    ) + scheduledDate.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    ), action: onCancelDelay)
                }
                .font(.caption)
                .foregroundStyle(ATHLTHTrainDesign.bronze)
            } else {
                Text(ATHLTHLocalization.choose(
                    english: "Tap to start now · hold a button for more start options.",
                    norwegian: "Trykk for å starte nå · hold inne for startvalg."
                ))
                .font(.caption2)
                .foregroundStyle(ATHLTHTrainDesign.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            ATHLTHTrainDesign.rule.opacity(0.7).frame(height: 0.7)
        }
        .sheet(isPresented: $showingCustomDelay) {
            NavigationStack {
                Form {
                    Stepper(value: $customMinutes, in: 1...120) {
                        Text(ATHLTHLocalization.format(
                            english: "Start in %d minutes",
                            norwegian: "Start om %d minutter",
                            customMinutes
                        ))
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "The iPhone app must be active to launch a delayed Quick Train workout. Reopen it if it is suspended.",
                        norwegian: "iPhone-appen må være aktiv for å starte en utsatt hurtigøkt. Åpne appen igjen hvis den er satt på pause."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .navigationTitle(ATHLTHLocalization.choose(
                    english: "Delayed start", norwegian: "Utsatt start"
                ))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Cancel", norwegian: "Avbryt"
                        )) { showingCustomDelay = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ATHLTHLocalization.choose(
                            english: "Set start", norwegian: "Velg start"
                        )) {
                            showingCustomDelay = false
                            onDelay(customDevice, customMinutes * 60)
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func deviceButton(
        _ device: WorkoutCaptureDevice,
        label: String, icon: String
    ) -> some View {
        let enabled = canStart && !starting &&
            (device == .iPhone || watchAvailable)
        return Button {
            if device == .iPhone { onIPhoneNow() }
            else { onWatchNow() }
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 49)
                .background(
                    ATHLTHTrainDesign.bronze.gradient,
                    in: RoundedRectangle(cornerRadius: 15)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .contextMenu {
            Button {
                if device == .iPhone { onIPhoneNow() }
                else { onWatchNow() }
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Start now", norwegian: "Start nå"
                ), systemImage: "play.fill")
            }
            if device == .appleWatch {
                Button(action: onWatchCountDown) {
                    Label(ATHLTHLocalization.choose(
                        english: "Countdown · 30 seconds",
                        norwegian: "Nedtelling · 30 sekunder"
                    ), systemImage: "timer")
                }
                Button(action: onWatchManual) {
                    Label(ATHLTHLocalization.choose(
                        english: "Start on Watch", norwegian: "Start på klokken"
                    ), systemImage: "applewatch")
                }
            }
            Menu {
                ForEach([30, 60, 300, 600], id: \.self) { seconds in
                    Button(seconds == 30
                        ? ATHLTHLocalization.choose(
                            english: "30 seconds", norwegian: "30 sekunder"
                          ) : "\(seconds / 60) min"
                    ) {
                        onDelay(device, seconds)
                    }
                }
                Button {
                    customDevice = device
                    customMinutes = 2
                    showingCustomDelay = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Choose duration…", norwegian: "Velg tid …"
                    ), systemImage: "clock")
                }
            } label: {
                Label(ATHLTHLocalization.choose(
                    english: "Start later", norwegian: "Start om X tid"
                ), systemImage: "clock")
            }
        }
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Tap to start now, or hold to schedule.",
            norwegian: "Trykk for å starte nå, eller hold for å velge tidspunkt."
        ))
    }
}
