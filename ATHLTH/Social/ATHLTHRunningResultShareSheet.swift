import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Dedicated ATHLTH result share experience. No posting or OS share happens
/// until the athlete explicitly chooses one of the actions below.
struct ATHLTHRunningResultShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let workout: SocialPublishableWorkout
    let averageHeartRateBPM: Double?
    let elevationGainMeters: Double?
    let rawRoute: [CLLocation]
    let highlights: [ATHLTHRunningResultInsights.KilometerSplit]

    @State private var includeRoute = false
    @State private var hideStartAndEnd = true
    @State private var mapSnapshot: UIImage?
    @State private var loadingMap = false
    @State private var showingPublish = false
    @State private var exportedImage: ATHLTHResultExport?
    @State private var exportError = false

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var safeCoordinates: [RouteCoordinate] {
        guard includeRoute, workout.isIndoor != true else { return [] }
        return WorkoutRouteSharing.preview(
            rawRoute, hideStartAndEnd: hideStartAndEnd
        )
    }

    private var hasUsableMap: Bool { safeCoordinates.count >= 2 }

    private var distance: String {
        guard let meters = workout.distanceMeters, meters.isFinite, meters > 0 else {
            return "—"
        }
        return String(format: "%.2f km", meters / 1_000)
    }

    private var duration: String {
        let seconds = max(0, Int(workout.duration.rounded()))
        return seconds >= 3_600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var pace: String {
        guard let meters = workout.distanceMeters, meters.isFinite, meters > 0,
              workout.duration.isFinite, workout.duration > 0 else { return "—" }
        let seconds = workout.duration / (meters / 1_000)
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
    }

    private var heartRate: String? {
        guard let hr = averageHeartRateBPM, hr.isFinite, hr > 0 else { return nil }
        return "\(Int(hr.rounded())) bpm"
    }

    private var highlight: String? {
        if let finish = ATHLTHRunningResultInsights.strongFinishPercent(highlights) {
            return tr("Strong finish · \(finish)% faster", "Sterk avslutning · \(finish) % raskere")
        }
        if let fastest = ATHLTHRunningResultInsights.bestKilometer(highlights) {
            let seconds = Int(fastest.paceSecondsPerKilometer.rounded())
            return tr("Fastest complete kilometre", "Raskeste hele kilometer")
                + String(format: " · %d:%02d /km", seconds / 60, seconds % 60)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tr("Your ATHLTH result", "Ditt ATHLTH-resultat"))
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                        .foregroundStyle(ATHLTHPlanDesign.ink)

                    Text(tr("Preview before sharing. The post and the image have separate privacy choices.",
                            "Se resultatet før du deler. Innlegget og bildet har egne personvernvalg."))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    resultCard
                        .padding(.horizontal, 2)

                    VStack(alignment: .leading, spacing: 11) {
                        Toggle(tr("Include GPS route in image", "Vis GPS-rute i bildet"),
                               isOn: $includeRoute)
                            .disabled(workout.isIndoor == true || rawRoute.count < 2)
                        if includeRoute {
                            Toggle(tr("Hide start and finish (250 m)",
                                      "Skjul start og mål (250 m)"), isOn: $hideStartAndEnd)
                            if !hideStartAndEnd {
                                Label(
                                    tr("Your start and finish locations may reveal private places.",
                                       "Start- og målpunkt kan avsløre private steder."),
                                    systemImage: "exclamationmark.shield"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            } else if !hasUsableMap {
                                Text(tr("There is not enough safe route to display. The image will contain only your result.",
                                        "Det er ikke nok trygg rute å vise. Bildet vil kun inneholde resultatet."))
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                    }
                    .tint(ATHLTHPlanDesign.accentInk)
                    .font(.subheadline)
                    .padding(17)
                    .athlthPlanCard()

                    Button {
                        showingPublish = true
                    } label: {
                        Label(tr("Publish in ATHLTH", "Publiser i ATHLTH"),
                              systemImage: "person.2.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 51)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(ATHLTHPlanDesign.ink,
                                in: RoundedRectangle(cornerRadius: 15))

                    Button {
                        exportResultImage()
                    } label: {
                        Label(tr("Share image with friends", "Del bilde med venner"),
                              systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 51)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 15))
                    .disabled(includeRoute && hasUsableMap && loadingMap)

                    Text(tr("Publishing opens ATHLTH's audience and route privacy settings. Nothing is posted automatically.",
                            "Ved publisering velger du hvem som kan se økten og rutekartet. Ingenting publiseres automatisk."))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                .padding(18)
            }
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .navigationTitle(tr("Share result", "Del resultat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done", "Ferdig")) { dismiss() }
                }
            }
            .task(id: "\(includeRoute)-\(hideStartAndEnd)") {
                await updateMapPreview()
            }
            .sheet(isPresented: $showingPublish) {
                WorkoutPublishView(initialWorkoutID: workout.id,
                                   initialVisibility: .friends)
            }
            .sheet(item: $exportedImage) { item in
                ATHLTHResultActivitySheet(image: item.image)
            }
            .alert(tr("Image unavailable", "Kunne ikke lage bildet"),
                   isPresented: $exportError) {
                Button("OK", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                ATHLTHBrandMark(size: .compact)
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                Spacer()
                Text(workout.startDate.formatted(.dateTime.day().month(.wide).year()))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Text(tr("RUNNING RESULT", "LØPERESULTAT"))
                .font(.caption2.weight(.bold))
                .tracking(2)
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(distance)
                .font(.system(size: 43, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                shareValue(tr("Time", "Tid"), duration)
                shareValue(tr("Pace", "Tempo"), pace)
                if let heartRate { shareValue(tr("Avg HR", "Snittpuls"), heartRate) }
            }
            if let gain = elevationGainMeters, gain.isFinite, gain >= 5 {
                Label("\(Int(gain.rounded())) " + tr("m elevation gain", "høydemeter"),
                      systemImage: "mountain.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
            }

            if includeRoute && hasUsableMap {
                if let mapSnapshot {
                    Image(uiImage: mapSnapshot)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 230)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                } else if loadingMap {
                    ProgressView(tr("Preparing private map", "Klargjør trygt kart"))
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .background(ATHLTHPlanDesign.warmSurface,
                                    in: RoundedRectangle(cornerRadius: 15))
                }
            }
            if let highlight {
                Label(highlight, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ATHLTHPlanDesign.selectedSurface,
                                in: RoundedRectangle(cornerRadius: 13))
            }
            Rectangle().fill(ATHLTHPlanDesign.warmDivider).frame(height: 0.7)
            Text("ATHLTH  ·  MOVE BETTER. LIVE LONGER.")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(ATHLTHPlanDesign.surface,
                    in: RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .strokeBorder(ATHLTHPlanDesign.warmDivider, lineWidth: 0.9)
        }
    }

    private func shareValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.warmSurface.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func updateMapPreview() async {
        mapSnapshot = nil
        guard includeRoute, hasUsableMap else {
            loadingMap = false
            return
        }
        loadingMap = true
        defer { loadingMap = false }
        let visible = safeCoordinates
        guard let first = visible.first else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for location in visible.dropFirst() {
            minLat = min(minLat, location.latitude)
            maxLat = max(maxLat, location.latitude)
            minLon = min(minLon, location.longitude)
            maxLon = max(maxLon, location.longitude)
        }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat - minLat) * 1.35),
                                   longitudeDelta: max(0.004, (maxLon - minLon) * 1.35))
        )
        options.size = CGSize(width: 800, height: 560)
        options.scale = 2
        options.mapType = .mutedStandard
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            guard !Task.isCancelled else { return }
            let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
            let overlaid = renderer.image { _ in
                snapshot.image.draw(at: .zero)
                let path = UIBezierPath()
                for (index, coordinate) in visible.enumerated() {
                    let point = snapshot.point(for: coordinate.coordinate)
                    if index == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }
                path.lineWidth = 9
                path.lineJoinStyle = .round
                path.lineCapStyle = .round
                UIColor.white.withAlphaComponent(0.93).setStroke()
                path.stroke()
                // The result image uses the same pace narrative as the
                // detail map. Only visible, sanitized points are rendered.
                // Never connect invisible private sections.
                let paces = paceValues(for: visible)
                let validPaces = paces.compactMap { $0 }.sorted()
                let fast = validPaces.first ?? 300
                let slow = validPaces.last ?? 600
                for index in 1..<visible.count {
                    let from = snapshot.point(for: visible[index - 1].coordinate)
                    let to = snapshot.point(for: visible[index].coordinate)
                    let segment = UIBezierPath()
                    segment.move(to: from)
                    segment.addLine(to: to)
                    segment.lineWidth = 6
                    segment.lineCapStyle = .round
                    let fallback = UIColor(red: 0.43, green: 0.32, blue: 0.20, alpha: 1)
                    if index - 1 < paces.count, let pace = paces[index - 1] {
                        let position = max(0, min(1, (pace - fast) / max(1, slow - fast)))
                        UIColor(
                            red: 0.05 + 0.91 * position,
                            green: 0.62 - 0.17 * position,
                            blue: 0.49 - 0.37 * position,
                            alpha: 1
                        ).setStroke()
                    } else {
                        fallback.setStroke()
                    }
                    segment.stroke()
                }
            }
            // The route list used for the snapshot is the same sanitized list
            // displayed in the preview, never the private original route.
            mapSnapshot = overlaid
        } catch {
            mapSnapshot = nil
        }
    }

    // Source coordinates are preserved exactly by WorkoutRouteSharing.
    // Monotonic matching avoids leaking gaps or colouring a line by a GPS
    // sample that was deliberately withheld from the shared preview.
    private func paceValues(for visible: [RouteCoordinate]) -> [Double?] {
        guard visible.count >= 2 else { return [] }
        var matched: [CLLocation] = []
        var next = 0
        for point in visible {
            while next < rawRoute.count {
                let original = rawRoute[next]
                next += 1
                if original.coordinate.latitude == point.latitude &&
                   original.coordinate.longitude == point.longitude {
                    matched.append(original)
                    break
                }
            }
        }
        guard matched.count == visible.count else {
            return Array(repeating: nil, count: visible.count - 1)
        }
        return zip(matched, matched.dropFirst()).map { before, after in
            let meters = after.distance(from: before)
            let seconds = after.timestamp.timeIntervalSince(before.timestamp)
            guard seconds > 0, seconds <= 300, meters >= 10,
                  meters.isFinite, meters / seconds <= 12.5 else { return nil }
            return seconds / (meters / 1_000)
        }
    }

    @MainActor
    private func exportResultImage() {
        if includeRoute && hasUsableMap && mapSnapshot == nil {
            exportError = true
            return
        }
        let renderer = ImageRenderer(
            content: resultCard
                .frame(width: 420)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        guard let image = renderer.uiImage else {
            exportError = true
            return
        }
        exportedImage = ATHLTHResultExport(image: image)
    }
}

private struct ATHLTHResultExport: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ATHLTHResultActivitySheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
