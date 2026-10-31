import SwiftUI

/// Lightweight entry points into the existing ATHLTH workout integrations.
/// Actions are presented separately from the workout-save action.
struct ATHLTHWorkoutExtrasMenu: View {
    let onGear: () -> Void
    let onPlanWithFriend: () -> Void
    let onSpotify: () -> Void
    let onHeartRateAndPace: () -> Void
    let onAudioCoach: () -> Void
    let onGhostRace: () -> Void
    let onChooseRoute: () -> Void
    let onCreateRoute: () -> Void

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        Menu {
            Button(action: onGear) {
                Label(tr("Gear", "Utstyr"), systemImage: "shoeprints.fill")
            }
            Button(action: onPlanWithFriend) {
                Label(tr("Plan with a friend", "Planlegg med en venn"),
                      systemImage: "person.2")
            }
            Button(action: onSpotify) {
                Label("Spotify", systemImage: "music.note")
            }
            Button(action: onHeartRateAndPace) {
                Label(tr("Heart rate and pace", "Puls og tempo"),
                      systemImage: "heart.text.square")
            }
            Button(action: onAudioCoach) {
                Label("Audio Coach", systemImage: "waveform")
            }
            Button(action: onGhostRace) {
                Label("Ghost Race", systemImage: "figure.run")
            }
            Menu {
                Button(action: onChooseRoute) {
                    Label(tr("Choose saved route", "Velg lagret rute"),
                          systemImage: "map")
                }
                Button(action: onCreateRoute) {
                    Label(tr("Create route", "Lag rute"),
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            } label: {
                Label(tr("Route", "Rute"), systemImage: "map.fill")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 42, height: 42)
                .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(tr("Workout options", "Øktinnstillinger"))
        .accessibilityHint(tr(
            "Opens workout integrations and route actions",
            "Åpner innstillinger og rutevalg for økten"
        ))
    }
}
