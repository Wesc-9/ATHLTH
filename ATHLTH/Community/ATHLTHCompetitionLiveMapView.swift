import SwiftUI
import MapKit

/// Privacy-first competition live map. Positions are sourced from the
/// original active iPhone workout; never starts a second GPS listener.
struct ATHLTHCompetitionLiveMapView: View {
    let tournament: ATHLTHTournamentRemote
    let userID: UUID
    let names: [UUID: String]

    @State private var sharing = false
    @State private var positions: [ATHLTHCompetitionLivePosition] = []
    @State private var errorMessage: String?
    @State private var boundWorkoutID: UUID?

    private let cloud = ATHLTHCompetitionLivePositionCloud()

    private var eligibleToAttach: Bool {
        guard tournament.status == "active",
              let start = tournament.raceSignalAt ?? tournament.startedAt,
              let active = ATHLTHWorkoutRecordingArbiter.phone?.active,
              active.runEnvironment == .outdoor,
              active.start >= start else { return false }
        return active.competitionCapture == nil ||
            active.competitionCapture?.tournamentID == tournament.id
    }

    private var attached: Bool {
        ATHLTHWorkoutRecordingArbiter.phone?.active?
            .competitionCapture?.tournamentID == tournament.id
    }

    private var raceStart: Date? {
        tournament.raceSignalAt ?? tournament.startedAt
    }

    var body: some View {
        if tournament.raceRules.allowOptInLiveLocation ||
           (tournament.raceRules.discipline == .laps &&
            tournament.raceRules.lapVerification == .gps) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Konkurranse · live")
                    .font(.system(size: 22, design: .serif))
                    .foregroundStyle(ATHLTHArenaV3Style.ink)

                if tournament.status == "active" {
                    if attached {
                        Label("Knyttet til din aktive ATHLTH-økt",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                    } else {
                        Button {
                            attachExistingWorkout()
                        } label: {
                            Label("Koble til pågående treningsøkt",
                                  systemImage: "figure.run")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ATHLTHArenaV3Style.gold)
                        .disabled(!eligibleToAttach)
                        Text("Start en utendørs økt fra Tren etter konkurransens startsignal. Koble den til her – samme opptak brukes i konkurransen.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                    }

                    if tournament.raceRules.discipline == .laps && attached {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(ATHLTHWorkoutRecordingArbiter.phone?.active?
                                     .competitionCapture?.lapSummary ??
                                     "0/\(tournament.raceRules.lapCount) runder")
                                    .font(.headline.monospacedDigit())
                            }
                            .foregroundStyle(ATHLTHArenaV3Style.gold)
                        }
                    }

                    if tournament.raceRules.allowOptInLiveLocation {
                        Toggle("Del min liveposisjon med deltakerne",
                               isOn: $sharing)
                            .tint(ATHLTHArenaV3Style.gold)
                            .font(.subheadline)
                            .disabled(!attached)
                        Text("Frivillig. Kun deltakere som selv deler posisjonen, kan se hverandre. Posisjoner utløper automatisk etter 25 sekunder.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHArenaV3Style.secondary)
                        if sharing {
                            if positions.isEmpty {
                                Text("Venter på GPS-posisjoner…")
                                    .font(.caption)
                            } else {
                                Map(initialPosition: .automatic) {
                                    ForEach(positions) { person in
                                        Marker(
                                            names[person.userID] ?? "Utøver",
                                            coordinate: CLLocationCoordinate2D(
                                                latitude: person.latitude,
                                                longitude: person.longitude
                                            )
                                        )
                                    }
                                }
                                .frame(height: 255)
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                            }
                        }
                    }
                } else {
                    Text("Liveposisjon vises bare under en aktiv konkurranse.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHArenaV3Style.secondary)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(15)
            .background(ATHLTHArenaV3Style.panel())
            .task(id: sharing) {
                guard sharing else { return }
                await publishUntilStopped()
            }
            .onDisappear {
                if sharing {
                    sharing = false
                    let id = tournament.id
                    Task { try? await cloud.stop(tournamentID: id) }
                }
            }
        }
    }

    @MainActor
    private func attachExistingWorkout() {
        guard eligibleToAttach, let start = raceStart,
              let phone = ATHLTHWorkoutRecordingArbiter.phone else {
            errorMessage = "Start en utendørs ATHLTH-økt etter startsignalet."
            return
        }
        if phone.attachCompetition(
            tournamentID: tournament.id,
            startSignalAt: start,
            raceRules: tournament.raceRules
        ) {
            boundWorkoutID = phone.active?.id
            errorMessage = nil
        } else {
            errorMessage = "Kunne ikke koble denne økten til konkurransen."
        }
    }

    @MainActor
    private func publishUntilStopped() async {
        defer {
            positions = []
            sharing = false
        }
        while sharing && !Task.isCancelled {
            guard attached,
                  let point = ATHLTHWorkoutRecordingArbiter.phone?
                      .active?.points.last,
                  abs(point.timestamp.timeIntervalSinceNow) <= 20,
                  point.accuracy >= 0, point.accuracy <= 30 else {
                errorMessage = "GPS-signalet må være ferskt og nøyaktig for å dele posisjon."
                break
            }
            do {
                try await cloud.share(tournamentID: tournament.id,
                                      point: point)
                positions = try await cloud.visible(tournamentID: tournament.id)
                errorMessage = nil
            } catch {
                errorMessage = "Deling av liveposisjon er midlertidig utilgjengelig."
                break
            }
            try? await Task.sleep(for: .seconds(8))
        }
        try? await cloud.stop(tournamentID: tournament.id)
    }
}
