import MapKit
import SwiftUI

/// Uses ONLY the public city/area from a Train Together listing. Exact
/// meeting coordinates stay in train_together_post_meetups and are never
/// used for discovery pins. Apple Maps resolves the rough city center.
struct TrainTogetherAreaMapView: View {
    @EnvironmentObject private var marketplace: TrainTogetherMarketplaceStore

    let posts: [TrainTogetherPost]

    @State private var pins: [AreaPin] = []
    @State private var cachedAreas: [String: CLLocationCoordinate2D] = [:]
    @State private var isResolving = false
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 65.2, longitude: 13.8),
            span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)
        )
    )

    private struct AreaPin: Identifiable {
        let post: TrainTogetherPost
        let coordinate: CLLocationCoordinate2D
        var id: UUID { post.id }
    }

    private var lookupKey: String {
        posts.map {
            $0.id.uuidString + ":" + $0.broadArea
        }.sorted().joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "map.fill")
                    .foregroundStyle(ATHLTHTheme.vitality)
                Text(
                    ATHLTHLocalization.choose(
                        english: "Nearby training on the map",
                        norwegian: "Trening på kartet"
                    )
                )
                .font(.subheadline.weight(.bold))

                Spacer()

                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Map(position: $cameraPosition) {
                ForEach(pins) { pin in
                    Annotation(
                        pin.post.broadArea,
                        coordinate: pin.coordinate,
                        anchor: .bottom
                    ) {
                        NavigationLink {
                            TrainTogetherPostDetailView(postID: pin.post.id)
                                .environmentObject(marketplace)
                        } label: {
                            VStack(spacing: 3) {
                                Image(
                                    systemName: pin.post.workoutKind == "strength"
                                        ? "dumbbell.fill"
                                        : "figure.run"
                                )
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(ATHLTHTheme.vitality, in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(.white, lineWidth: 2)
                                }

                                Text(
                                    pin.post.scheduledStart.formatted(
                                        date: .omitted,
                                        time: .shortened
                                    )
                                )
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            pin.post.title + ", " + pin.post.broadArea
                        )
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            if pins.isEmpty && !isResolving {
                Text(
                    ATHLTHLocalization.choose(
                        english: "No workouts have a public city to show on the map. Switch to List to see all workouts.",
                        norwegian: "Ingen økter har et offentlig område som kan vises på kartet. Bytt til Liste for å se alle."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Label(
                ATHLTHLocalization.choose(
                    english: "Pins show approximate city centers, not private meetup locations. Exact locations unlock only after approval.",
                    norwegian: "Markørene viser omtrentlige bysentrum, aldri privat møtested. Nøyaktig plassering vises først etter godkjenning."
                ),
                systemImage: "lock.shield"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            Color.white.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .task(id: lookupKey) {
            await resolvePublicAreas()
        }
    }

    @MainActor
    private func resolvePublicAreas() async {
        isResolving = true
        defer { isResolving = false }
        var resolved: [AreaPin] = []
        // Bounded and cached: don't issue a map lookup for every row.
        for post in posts.prefix(20) {
            if Task.isCancelled { return }
            let area = post.broadArea.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !area.isEmpty,
                  area.lowercased() != "online",
                  area.lowercased() != "på avstand"
            else { continue }

            let key = area.lowercased()
            if let cached = cachedAreas[key] {
                resolved.append(AreaPin(post: post, coordinate: cached))
                continue
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = area
            request.resultTypes = .address
            // Search for publicly named places only.
            do {
                let response = try await MKLocalSearch(request: request).start()
                if let item = response.mapItems.first {
                    let location = item.placemark.coordinate
                    cachedAreas[key] = location
                    resolved.append(AreaPin(post: post, coordinate: location))
                }
            } catch {
                // Show the other pins if one area can't be resolved.
                continue
            }
        }

        pins = resolved
        if let first = resolved.first {
            let latitudes = resolved.map { $0.coordinate.latitude }
            let longitudes = resolved.map { $0.coordinate.longitude }
            let minLat = latitudes.min() ?? first.coordinate.latitude
            let maxLat = latitudes.max() ?? first.coordinate.latitude
            let minLon = longitudes.min() ?? first.coordinate.longitude
            let maxLon = longitudes.max() ?? first.coordinate.longitude
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: (minLat + maxLat) / 2,
                        longitude: (minLon + maxLon) / 2
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: max(0.08, (maxLat - minLat) * 1.6),
                        longitudeDelta: max(0.12, (maxLon - minLon) * 1.6)
                    )
                )
            )
        }
    }
}
