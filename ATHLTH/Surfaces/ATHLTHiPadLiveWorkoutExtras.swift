import SwiftUI

/// Optional extras never displace the active workout or invent missing data.
/// Music on Apple Watch cannot be inferred from iPhone Spotify Connect.
struct ATHLTHiPadLiveWorkoutExtrasPanel: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        let hasStatus = snapshot.spotifyPlaying != nil ||
            snapshot.audioCoachEnabled != nil
        let splits = snapshot.recentSplits ?? []

        if hasStatus || !splits.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label(tr("LIVE DETAILS", "LIVEDETALJER"),
                      systemImage: "waveform.path")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)

                if let enabled = snapshot.audioCoachEnabled {
                    Label(enabled
                        ? tr("Audio Coach active", "Lydcoach aktiv")
                        : tr("Audio Coach off", "Lydcoach av"),
                        systemImage: enabled ? "waveform" : "speaker.slash")
                        .font(.subheadline)
                }

                if snapshot.spotifyPlaying == true,
                   let track = snapshot.spotifyTrackTitle,
                   !track.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "music.note")
                            .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("NOW PLAYING", "SPILLES NÅ"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                            Text(track)
                                .font(.subheadline.weight(.semibold))
                            if let artist = snapshot.spotifyArtistName,
                               !artist.isEmpty {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                    }
                    .accessibilityIdentifier("athlth-ipad-now-playing-track")
                } else if let playing = snapshot.spotifyPlaying {
                    Label(playing
                        ? tr("Spotify playing · track not available",
                             "Spotify spiller · sang ikke tilgjengelig")
                        : tr("Spotify not playing on iPhone",
                             "Spotify spiller ikke på iPhone"),
                          systemImage: "music.note")
                        .font(.subheadline)
                }

                if !splits.isEmpty {
                    Divider()
                    Text(tr("COMPLETED SPLITS", "FULLFØRTE DELØKTER"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    ForEach(splits) { result in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(result.index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                .frame(width: 25)
                            Text(result.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Spacer(minLength: 3)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(ATHLTHiPadLiveMetrics.duration(
                                    result.activeSeconds
                                ))
                                .monospacedDigit()
                                Text(String(format: "%.2f km",
                                    result.distanceMeters / 1000))
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATHLTHPlanDesign.surface,
                        in: RoundedRectangle(cornerRadius: 24))
            .accessibilityIdentifier("athlth-ipad-live-workout-extras")
        }
    }
}
