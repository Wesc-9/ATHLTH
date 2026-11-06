import CoreLocation
import MapKit
import SwiftUI

/// A local, privacy-preserving live replay of the prepared Ghost course.
///
/// The reference may represent a recorded run, a shared historical run or a
/// synthetic finish-time opponent. Markers are shown only after the existing
/// route matcher has accepted a fresh GPS comparison. This view neither
/// uploads position samples nor calculates a second competing lead metric.
struct ATHLTHGhostRaceLiveCourseMap: View {
    let reference: GhostRaceReference
    let comparison: GhostRaceComparison?
    var runnerTrail: [CLLocationCoordinate2D] = []
    var paused = false
    var mapHeight: CGFloat = 280

    @State private var camera: MapCameraPosition = .automatic
    @State private var following = true

    private let runnerInk = Color(red: 0.13, green: 0.22, blue: 0.33)
    private let ghostGold = Color(red: 0.76, green: 0.47, blue: 0.22)
    private let cream = Color(red: 0.983, green: 0.978, blue: 0.964)

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var route: [CLLocationCoordinate2D] {
        reference.points.map(\.coordinate)
    }

    private var actualTrail: [CLLocationCoordinate2D] {
        guard runnerTrail.count > 1 else { return [] }
        let step = max(runnerTrail.count / 350, 1)
        var points = stride(from: 0, to: runnerTrail.count, by: step)
            .map { runnerTrail[$0] }
        if let last = runnerTrail.last,
           points.last?.latitude != last.latitude ||
            points.last?.longitude != last.longitude {
            points.append(last)
        }
        return points
    }

    private func freshComparison(at date: Date) -> GhostRaceComparison? {
        ATHLTHGhostRaceLiveMapPolicy.acceptedComparison(
            comparison, paused: paused, at: date
        )
    }

    private func ghostTrail(for comparison: GhostRaceComparison) -> [CLLocationCoordinate2D] {
        let metres = comparison.ghostProgress * reference.routeDistanceMeters
        var values = reference.points.prefix(while: {
            $0.cumulativeMeters <= metres
        }).map(\.coordinate)
        values.append(comparison.ghostCoordinate)
        return values
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            let live = freshComparison(at: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(
                        reference.title.hasPrefix("Target ·")
                            ? tr("SIMULATED GHOST", "SIMULERT GHOST")
                            : tr("GHOST RACE LIVE", "GHOST RACE LIVE"),
                        systemImage: "figure.run"
                    )
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(runnerInk)
                    Spacer(minLength: 2)
                    Label(
                        paused ? tr("Paused", "Pauset")
                            : live == nil
                                ? tr("Finding GPS", "Finner GPS")
                                : tr("Live", "Direkte"),
                        systemImage: live == nil
                            ? "location.slash"
                            : "dot.radiowaves.left.and.right"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(live == nil ? Color.secondary : ghostGold)
                }

                Map(position: $camera) {
                    if route.count >= 2 {
                        MapPolyline(coordinates: route)
                            .stroke(runnerInk.opacity(0.25), lineWidth: 5)
                    }
                    if actualTrail.count >= 2 {
                        MapPolyline(coordinates: actualTrail)
                            .stroke(
                                runnerInk,
                                style: StrokeStyle(
                                    lineWidth: 5,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                    if let live {
                        let behindGhost = ghostTrail(for: live)
                        if behindGhost.count >= 2 {
                            MapPolyline(coordinates: behindGhost)
                                .stroke(
                                    ghostGold.opacity(0.8),
                                    style: StrokeStyle(
                                        lineWidth: 3,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }

                        Annotation(
                            tr("You", "Du"),
                            coordinate: live.userCoordinate,
                            anchor: .bottom
                        ) {
                            runnerMarker
                        }
                        Annotation(
                            "Ghost",
                            coordinate: live.ghostCoordinate,
                            anchor: .bottom
                        ) {
                            ghostMarker
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: mapHeight)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .topTrailing) {
                    Menu {
                        Button {
                            following = true
                            centerMap(on: live)
                        } label: {
                            Label(
                                tr("Follow runners", "Følg løperne"),
                                systemImage: "location.north.line.fill"
                            )
                        }

                        Button {
                            following = false
                            camera = .region(Self.courseRegion(reference))
                        } label: {
                            Label(
                                tr("Show full course", "Vis hele løypen"),
                                systemImage: "map"
                            )
                        }
                    } label: {
                        Image(systemName: following
                            ? "location.north.line.fill" : "map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(runnerInk)
                            .frame(width: 42, height: 42)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(tr("Map camera options", "Kartvalg"))
                    .padding(12)
                }
                .overlay {
                    if live == nil {
                        Text(
                            paused
                                ? tr("Race paused", "Løpet er pauset")
                                : tr("Waiting for reliable GPS on the course",
                                     "Venter på pålitelig GPS langs løypen")
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(runnerInk)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .onAppear {
                    camera = .region(Self.courseRegion(reference))
                }
                .onChange(of: reference.id) { _, _ in
                    following = true
                    camera = .region(Self.courseRegion(reference))
                }
                .onChange(of: live?.updatedAt) { _, _ in
                    if following { centerMap(on: live) }
                }

                HStack(spacing: 9) {
                    legend(tr("You", "Du"), color: runnerInk)
                    legend("Ghost", color: ghostGold)
                    Spacer(minLength: 0)
                    if let live {
                        Text(leadText(live.signedDistanceMeters))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(runnerInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("—")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let live {
                    HStack(spacing: 8) {
                        progressMetric(
                            title: tr("Your progress", "Din fremdrift"),
                            value: live.userProgress
                        )
                        progressMetric(
                            title: tr("Ghost progress", "Ghost-fremdrift"),
                            value: live.ghostProgress
                        )
                    }
                    Text(
                        tr("Time difference", "Tidsforskjell") + " · " +
                        signedTime(live.signedTimeSeconds)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(tr(
                        "No lead is calculated from missing, stale or unreliable GPS. The saved route remains visible.",
                        "Ingen ledelse beregnes fra manglende, gammel eller upålitelig GPS. Den lagrede løypen vises fortsatt."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 23))
            .overlay {
                RoundedRectangle(cornerRadius: 23)
                    .stroke(runnerInk.opacity(0.08), lineWidth: 0.8)
            }
        }
        .accessibilityIdentifier("athlth-ghost-race-live-course-map")
    }

    private var runnerMarker: some View {
        Image(systemName: "figure.run")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(runnerInk, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            .accessibilityLabel(tr("Your GPS position", "Din GPS-posisjon"))
    }

    private var ghostMarker: some View {
        Image(systemName: "figure.run")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(ghostGold, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            .accessibilityLabel(tr("Ghost position", "Ghost-posisjon"))
    }

    private func legend(_ name: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption.weight(.medium))
        }
        .foregroundStyle(runnerInk)
    }

    private func progressMetric(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(title).font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(runnerInk)
            }
            ProgressView(value: min(max(value, 0), 1))
                .tint(title == tr("Your progress", "Din fremdrift") ? runnerInk : ghostGold)
        }
        .padding(10)
        .background(cream, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity)
    }

    private func leadText(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let meters = Int(abs(value).rounded())
        if meters < 8 { return tr("Neck and neck", "Helt jevnt") }
        return value > 0
            ? tr("\(meters) m ahead", "\(meters) m foran")
            : tr("\(meters) m behind", "\(meters) m bak")
    }

    private func signedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        return String(format: "%+.0f s", seconds)
    }

    private func centerMap(on comparison: GhostRaceComparison?) {
        guard let comparison else {
            camera = .region(Self.courseRegion(reference))
            return
        }
        let a = comparison.userCoordinate
        let b = comparison.ghostCoordinate
        camera = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (a.latitude + b.latitude) / 2,
                    longitude: (a.longitude + b.longitude) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: max(abs(a.latitude - b.latitude) * 2.6, 0.004),
                    longitudeDelta: max(abs(a.longitude - b.longitude) * 2.6, 0.004)
                )
            )
        )
    }

    static func courseRegion(_ reference: GhostRaceReference) -> MKCoordinateRegion {
        let coordinates = reference.points.map(\.coordinate)
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        let bounds = coordinates.reduce(
            (minLat: first.latitude, maxLat: first.latitude,
             minLon: first.longitude, maxLon: first.longitude)
        ) { result, coordinate in
            (
                min(result.minLat, coordinate.latitude),
                max(result.maxLat, coordinate.latitude),
                min(result.minLon, coordinate.longitude),
                max(result.maxLon, coordinate.longitude)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (bounds.minLat + bounds.maxLat) / 2,
                longitude: (bounds.minLon + bounds.maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((bounds.maxLat - bounds.minLat) * 1.3, 0.006),
                longitudeDelta: max((bounds.maxLon - bounds.minLon) * 1.3, 0.006)
            )
        )
    }
}
