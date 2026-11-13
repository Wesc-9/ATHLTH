import SwiftUI

/// Same visual setting in Quick Train, planned workouts and the preflight
/// surfaces. It arms only the *next* workout and is OFF by default.
struct ATHLTHLiveWorkoutPrestartToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        if !ATHLTHDeviceRole.isIPad {
            Toggle(isOn: $isOn) {
                HStack(spacing: 10) {
                    Image(systemName: "ipad.and.iphone")
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.choose(
                            english: "Show this workout on iPad",
                            norwegian: "Vis denne økten på iPad"
                        ))
                        .font(.subheadline.weight(.semibold))

                        Text(ATHLTHLocalization.choose(
                            english: "Off by default. Permission ends when this workout ends.",
                            norwegian: "Av som standard. Tilgangen avsluttes med økten."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(ATHLTHPlanDesign.accentInk)
            .padding(13)
            .background(
                ATHLTHPlanDesign.surface,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .accessibilityIdentifier("athlth-live-view-before-workout-toggle")
        }
    }
}

/// An unobtrusive home hint: no live data is revealed just by being signed in.
/// The athlete must accept for the current workout on iPhone.
struct ATHLTHiPadLiveWorkoutAccessTip: View {
    @EnvironmentObject private var live: ATHLTHCrossDeviceWorkoutStore
    @EnvironmentObject private var account: AppSessionStore

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        if ATHLTHDeviceRole.isIPad && live.remote == nil {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "ipad.and.iphone")
                    .font(.title3)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Workout on iPhone or Apple Watch?",
                            "Trener du på iPhone eller Apple Watch?"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(tr(
                        "You can follow one live workout here. iPhone must approve each request.",
                        "Du kan følge én liveøkt her. iPhone må godkjenne hver forespørsel."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                    if live.outgoingRequestState == .pending ||
                       live.outgoingRequestState == .sending {
                        Label(tr("Waiting for iPhone approval",
                                 "Venter på godkjenning på iPhone"),
                              systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                    } else if live.outgoingRequestState == .denied {
                        Text(tr("Request declined on iPhone.",
                                "Forespørselen ble avslått på iPhone."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if live.outgoingRequestState == .expired {
                        Text(tr("Request expired. You can send another.",
                                "Forespørselen utløp. Du kan prøve igjen."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let error = live.requestError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    Task {
                        await live.requestAccess(accountID: account.profile.userID)
                    }
                } label: {
                    Label(
                        tr("Request access", "Be om tilgang"),
                        systemImage: "lock.open"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(ATHLTHPlanDesign.accentInk)
                .disabled(
                    live.outgoingRequestState == .pending ||
                    live.outgoingRequestState == .sending
                )
                .accessibilityIdentifier("athlth-ipad-request-live-access")
            }
            .padding(16)
            .background(
                ATHLTHPlanDesign.surface,
                in: RoundedRectangle(cornerRadius: 19)
            )
            .accessibilityIdentifier("athlth-ipad-live-access-tip")
        }
    }
}
