import Charts
import SwiftUI

/// Privacy-first full-screen projection for AirPlay / external display
/// mirroring. Deliberately excludes profile names, inbox, location and
/// per-workout health values. Does not open a second UIWindowScene.
struct ATHLTHStudioPresentationView: View {
    @EnvironmentObject private var health: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var periodDays = 28

    private var data: ATHLTHStudioAnalytics.Snapshot {
        ATHLTHStudioAnalytics.snapshot(
            from: health.workouts, days: periodDays
        )
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 750
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 20 : 28) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("ATHLTH STUDIO")
                                .font(.system(size: compact ? 15 : 18,
                                              weight: .bold))
                                .tracking(2.4)
                                .foregroundStyle(ATHLTHStudioStyle.gold)
                            Text(tr("Training overview", "Treningsoversikt"))
                                .font(.system(
                                    size: compact ? 30 : 46,
                                    weight: .semibold, design: .rounded
                                ))
                                .foregroundStyle(ATHLTHStudioStyle.ink)
                        }
                        Spacer(minLength: 10)
                        Button {
                            dismiss()
                        } label: {
                            Label(tr("Close", "Lukk"), systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape)
                    }
                    HStack(spacing: 14) {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(tr(
                            "Privacy mode: personal details, messages, maps and individual workouts are hidden.",
                            "Personvernmodus: personopplysninger, meldinger, kart og enkeltøkter er skjult."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))

                    Picker(tr("Period", "Periode"), selection: $periodDays) {
                        Text(tr("7 days", "7 dager")).tag(7)
                        Text(tr("28 days", "28 dager")).tag(28)
                        Text(tr("90 days", "90 dager")).tag(90)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 15),
                            count: geometry.size.width >= 980 ? 4 :
                                geometry.size.width >= 610 ? 2 : 1
                        ),
                        spacing: 15
                    ) {
                        ATHLTHStudioMetricCard(
                            title: tr("Recorded workouts", "Registrerte økter"),
                            value: "\(data.sessions)",
                            note: tr("Completed workouts only", "Kun gjennomførte økter")
                        )
                        ATHLTHStudioMetricCard(
                            title: tr("Training time", "Treningstid"),
                            value: String(format: "%.1f h", data.minutes / 60),
                            note: tr("Recorded duration", "Registrert varighet")
                        )
                        ATHLTHStudioMetricCard(
                            title: tr("Recorded distance", "Registrert distanse"),
                            value: String(format: "%.1f km",
                                          data.distanceKilometers),
                            note: tr("Available workout data", "Tilgjengelige øktdata")
                        )
                        ATHLTHStudioMetricCard(
                            title: tr("Running / strength", "Løping / styrke"),
                            value: "\(data.runningSessions) / \(data.strengthSessions)",
                            note: tr("Number of sessions", "Antall økter")
                        )
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        Text(tr("Recorded training duration by day",
                                "Registrert treningstid per dag"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ATHLTHStudioStyle.ink)
                        Chart(data.days) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Hours", day.minutes / 60)
                            )
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                            .cornerRadius(3)
                        }
                        .frame(height: compact ? 250 : 360)
                        if data.sessions == 0 {
                            Text(tr(
                                "There are no accessible recorded sessions in this period.",
                                "Ingen tilgjengelige registrerte økter i perioden."
                            ))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(compact ? 16 : 30)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))

                    Text(tr(
                        "Projection uses local Apple Health workout summaries. It is a read-only presentation, not a live heart-rate or GPS feed.",
                        "Visningen bruker lokale øktsammendrag fra Apple Health. Dette er en skrivebeskyttet presentasjon, ikke en live-strøm av puls eller GPS."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(compact ? 18 : 38)
                .frame(maxWidth: 1_540)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
        }
        .onChange(of: scenePhase) { _, phase in
            // Stop public projection if the application leaves foreground.
            if phase != .active { dismiss() }
        }
        .accessibilityIdentifier("athlth-ipad-presentation-mode")
    }
}
