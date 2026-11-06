import CoreLocation
import MapKit
import SwiftUI

/// An iPad-only read-only spectator surface. Taps on this card never issue
/// start, pause, complete or other workout commands to the recording device.
struct ATHLTHStudioPrivateGhostSpectatorCard: View {
    let snapshot: ATHLTHPrivateGhostSpectatorSnapshot

    @State private var camera: MapCameraPosition = .automatic
    @State private var following = true

    private let runnerInk = Color(red: 0.13, green: 0.22, blue: 0.33)
    private let ghostAmber = Color(red: 0.77, green: 0.48, blue: 0.23)
    private let cream = Color(red: 0.978, green: 0.972, blue: 0.96)

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        snapshot.course.map(\.coordinate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    map
                        .frame(maxWidth: .infinity)
                    stats
                        .frame(width: 255, alignment: .topLeading)
                }
                VStack(spacing: 14) {
                    map
                    stats
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.shield")
                Text(tr(
                    "Private, read-only sync with your signed-in iPhone. Last update:",
                    "Privat, skrivebeskyttet synk fra din innloggede iPhone. Sist oppdatert:"
                ))
                Text(
                    Date(timeIntervalSince1970: snapshot.capturedAtEpoch)
                        .formatted(date: .omitted, time: .standard)
                )
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(runnerInk.opacity(0.10), lineWidth: 0.8)
        }
        .accessibilityIdentifier("ipad-private-fixed-ghost-live")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "figure.run")
                .font(.title2)
                .foregroundStyle(runnerInk)
                .frame(width: 46, height: 46)
                .background(cream, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.isSimulated
                    ? tr("SIMULATED GHOST · LIVE", "SIMULERT GHOST · LIVE")
                    : tr("GHOST RACE · LIVE", "GHOST RACE · LIVE")
                )
                .font(.caption2.weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(ghostAmber)
                Text(snapshot.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(runnerInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 4) {
                Label(
                    snapshot.paused
                        ? tr("Paused", "Pauset")
                        : snapshot.hasFreshPositions()
                            ? tr("Live", "Direkte")
                            : tr("Waiting for GPS", "Venter på GPS"),
                    systemImage: snapshot.hasFreshPositions()
                        ? "dot.radiowaves.left.and.right"
                        : "location.slash"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(snapshot.hasFreshPositions()
                                 ? ghostAmber : Color.secondary)
                Text(snapshot.sourceDevice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var map: some View {
        Map(position: $camera) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(runnerInk.opacity(0.36), lineWidth: 5)
            }
            if snapshot.hasFreshPositions(),
               let runner = snapshot.runner,
               let ghost = snapshot.ghost {
                Annotation(tr("You", "Du"), coordinate: runner.coordinate) {
                    runnerSymbol(color: runnerInk)
                }
                Annotation("Ghost", coordinate: ghost.coordinate) {
                    runnerSymbol(color: ghostAmber)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 315)
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 7) {
                Button {
                    following = true
                    centerOnRunners()
                } label: {
                    Label(tr("Follow", "Følg"), systemImage: "location.fill")
                }
                Button {
                    following = false
                    camera = .region(Self.courseRegion(coordinates))
                } label: {
                    Label(tr("Full route", "Hele ruten"), systemImage: "map")
                }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .tint(runnerInk)
            .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            if !snapshot.hasFreshPositions() {
                Label(
                    snapshot.paused
                        ? tr("Workout paused", "Økten er pauset")
                        : tr("Waiting for reliable positions",
                             "Venter på pålitelige posisjoner"),
                    systemImage: "location.slash"
                )
                .font(.caption.weight(.medium))
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(12)
            }
        }
        .onAppear {
            camera = .region(Self.courseRegion(coordinates))
            if snapshot.hasFreshPositions() { centerOnRunners() }
        }
        .onChange(of: snapshot.id) { _, _ in
            camera = .region(Self.courseRegion(coordinates))
            if following { centerOnRunners() }
        }
        .onChange(of: snapshot.capturedAtEpoch) { _, _ in
            if following && snapshot.hasFreshPositions() {
                centerOnRunners()
            }
        }
        .accessibilityIdentifier("ipad-fixed-ghost-two-runners-map")
    }

    private func runnerSymbol(color: Color) -> some View {
        Image(systemName: "figure.run")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                legend(tr("You", "Du"), color: runnerInk)
                Spacer()
                legend("Ghost", color: ghostAmber)
            }

            if snapshot.hasFreshPositions(),
               let you = snapshot.runnerProgress,
               let ghost = snapshot.ghostProgress,
               let gap = snapshot.signedDistanceMeters,
               let time = snapshot.signedTimeSeconds {
                Text(gapText(gap))
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(runnerInk)
                    .minimumScaleFactor(0.75)
                Text(tr("GAP ALONG THE ROUTE", "FORSKJELL LANGS RUTEN"))
                    .font(.caption2.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                progress(tr("You", "Du"), value: you, color: runnerInk)
                progress("Ghost", value: ghost, color: ghostAmber)

                HStack {
                    Label(tr("Time gap", "Tidsdifferanse"), systemImage: "timer")
                    Spacer()
                    Text(String(format: "%+.0f s", time))
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.medium))
            } else {
                Text(tr(
                    "The course remains available while GPS is missing or the workout is paused. No invented lead is shown.",
                    "Løypen vises fortsatt ved manglende GPS eller pause. Ingen beregnet ledelse vises uten gyldige data."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            Divider()
            Label(
                String(format: "%.1f km", snapshot.routeDistanceMeters / 1_000),
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(runnerInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 315, alignment: .topLeading)
        .background(cream, in: RoundedRectangle(cornerRadius: 17))
    }

    private func progress(_ title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            ProgressView(value: min(max(value, 0), 1))
                .tint(color)
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(runnerInk)
    }

    private func gapText(_ gap: Double) -> String {
        let meters = Int(abs(gap).rounded())
        if meters < 8 { return tr("Even", "Jevnt") }
        return gap > 0
            ? tr("\(meters) m ahead", "\(meters) m foran")
            : tr("\(meters) m behind", "\(meters) m bak")
    }

    private func centerOnRunners() {
        guard snapshot.hasFreshPositions(),
              let a = snapshot.runner?.coordinate,
              let b = snapshot.ghost?.coordinate else {
            camera = .region(Self.courseRegion(coordinates))
            return
        }
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (a.latitude + b.latitude) / 2,
                longitude: (a.longitude + b.longitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(abs(a.latitude - b.latitude) * 2.7, 0.004),
                longitudeDelta: max(abs(a.longitude - b.longitude) * 2.7, 0.004)
            )
        ))
    }

    static func courseRegion(_ points: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for point in points.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
            )
        )
    }
}
