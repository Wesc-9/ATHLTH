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

/// The iPad shows that a workout is underway without leaking its title,
/// pulse, pace, GPS, exercises or other consent-protected details. The user
/// opens this card to request access for only the current session.
struct ATHLTHiPadLiveWorkoutStatusCard: View {
    @EnvironmentObject private var live: ATHLTHCrossDeviceWorkoutStore
    @EnvironmentObject private var account: AppSessionStore
    @State private var showingAccess = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var sourceName: String {
        let source = live.remote?.sourceDevice ?? live.remotePresence?.sourceDevice
        return source == "watch" ? "Apple Watch" : "iPhone"
    }

    var body: some View {
        if ATHLTHDeviceRole.isIPad &&
           (live.remote != nil || live.remotePresence != nil) {
            Button {
                if live.remote != nil {
                    live.setExpanded(true)
                } else {
                    showingAccess = true
                }
            } label: {
                HStack(spacing: 15) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title3)
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHPlanDesign.selectedSurface,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(red: 0.18, green: 0.62, blue: 0.38))
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                            Text(tr("WORKOUT IN PROGRESS", "ØKT PÅGÅR"))
                                .font(.caption2.weight(.semibold))
                                .tracking(1.3)
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        }

                        Text(live.remote?.title ??
                             tr("Active workout", "Aktiv treningsøkt"))
                            .font(.system(.title3, design: .serif, weight: .medium))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                            .lineLimit(2)

                        Text(live.remote != nil
                             ? tr("Live details available · Open the workout",
                                  "Liveinformasjon tilgjengelig · Åpne økten")
                             : tr("On \(sourceName) · Tap to request access",
                                  "På \(sourceName) · Trykk for å be om tilgang"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 5)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 19))
                .contentShape(RoundedRectangle(cornerRadius: 19))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("athlth-ipad-active-workout-status")
            .sheet(isPresented: $showingAccess) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(
                            tr("Workout in progress on \(sourceName)",
                               "Økt pågår på \(sourceName)"),
                            systemImage: "ipad.and.iphone"
                        )
                        .font(.title3.weight(.semibold))

                        Text(tr(
                            "You can see that a workout is active, but its details are private. Request permission on the recording iPhone to follow this session live.",
                            "Du kan se at en økt pågår, men treningsdata er private. Be om tillatelse på iPhone for å følge akkurat denne økten direkte."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if live.outgoingRequestState == .pending ||
                           live.outgoingRequestState == .sending {
                            Label(
                                tr("Waiting for iPhone approval",
                                   "Venter på godkjenning på iPhone"),
                                systemImage: "clock"
                            )
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        } else if live.outgoingRequestState == .denied {
                            Text(tr("Request declined", "Forespørselen ble avslått"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if live.outgoingRequestState == .expired {
                            Text(tr("Request expired · Try again",
                                    "Forespørselen utløp · Prøv igjen"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if let error = live.requestError {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            Task {
                                await live.requestAccess(accountID: account.profile.userID)
                            }
                        } label: {
                            Label(
                                live.outgoingRequestState == .pending
                                    ? tr("Resend request", "Send på nytt")
                                    : tr("Request live access", "Be om tilgang"),
                                systemImage: "lock.open"
                            )
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHPlanDesign.accentInk)
                        .disabled(live.outgoingRequestState == .sending)
                        .accessibilityIdentifier("athlth-ipad-request-live-access")

                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .navigationTitle(tr("Live workout", "Liveøkt"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("Close", "Lukk")) { showingAccess = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onChange(of: live.remote?.id) { _, newID in
                if newID != nil { showingAccess = false }
            }
        }
    }
}
