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
    let onNavigation: () -> Void
    /// Compact bottom-of-Basic menu instead of a competing top-right gear.
    var showsExpandedLabel = false

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
            Button(action: onNavigation) {
                Label(tr("Navigation", "Navigasjon"),
                      systemImage: "location.north.line")
            }
        } label: {
            if showsExpandedLabel {
                HStack(spacing: 11) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 25)
                    Text(tr("More workout settings", "Flere øktinnstillinger"))
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 5)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(ATHLTHTrainDesign.bronze)
                .padding(.horizontal, 15)
                .frame(minHeight: 50)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                    .frame(width: 42, height: 42)
                    .background(ATHLTHPlanDesign.selectedSurface, in: Circle())
                    .contentShape(Circle())
            }
        }
        .accessibilityLabel(tr("Workout options", "Øktinnstillinger"))
        .accessibilityHint(tr(
            "Opens workout integration settings",
            "Åpner innstillinger for øktintegrasjoner"
        ))
    }
}
