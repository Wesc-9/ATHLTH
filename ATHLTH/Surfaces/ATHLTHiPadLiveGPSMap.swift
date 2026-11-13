import MapKit
import SwiftUI

/// A read-only, private spectator map. Never requests the iPad's location.
struct ATHLTHiPadLiveGPSMap: View {
    let snapshot: ATHLTHCrossDeviceWorkoutSnapshot
    @State private var camera: MapCameraPosition = .automatic

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private var validCoordinate: CLLocationCoordinate2D? {
        guard let latitude = snapshot.liveLatitude,
              let longitude = snapshot.liveLongitude,
              let sampled = snapshot.livePositionAt,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              abs(latitude) > 0.00001 || abs(longitude) > 0.00001,
              (-5...30).contains(Date().timeIntervalSince(sampled))
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(tr("LIVE POSITION", "LIVE-POSISJON"),
                      systemImage: "location.north.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Spacer()
                Text(tr("From workout source", "Fra treningsenheten"))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }

            if let point = validCoordinate {
                Map(position: $camera) {
                    Annotation(tr("You", "Du"), coordinate: point) {
                        ZStack {
                            Circle()
                                .fill(ATHLTHPlanDesign.accentInk.opacity(0.18))
                                .frame(width: 42, height: 42)
                            Circle()
                                .fill(ATHLTHPlanDesign.accentInk)
                                .frame(width: 16, height: 16)
                                .overlay {
                                    Circle().strokeBorder(.white, lineWidth: 3)
                                }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: 245)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topTrailing) {
                    Button {
                        center(on: point)
                    } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(tr("Follow GPS position",
                                            "Følg GPS-posisjon"))
                    .padding(8)
                }
                .onAppear { center(on: point) }
                .onChange(of: snapshot.liveLatitude) { _, _ in
                    if let next = validCoordinate { center(on: next) }
                }
                .onChange(of: snapshot.liveLongitude) { _, _ in
                    if let next = validCoordinate { center(on: next) }
                }
            } else {
                Label(
                    tr("Waiting for a fresh GPS position from the recording device",
                       "Venter på fersk GPS-posisjon fra treningsenheten"),
                    systemImage: "location.slash"
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .padding(.vertical, 18)
            }

            Text(tr("Only the latest position is shared for this approved workout.",
                    "Bare siste posisjon deles for denne godkjente økten."))
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHPlanDesign.surface, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("athlth-ipad-live-gps-map")
    }

    private func center(on point: CLLocationCoordinate2D) {
        camera = .region(MKCoordinateRegion(
            center: point,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        ))
    }
}
