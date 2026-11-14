import CoreLocation
import Foundation
import MapKit
import SwiftUI

/// Shared truth for the route detail screen and the owner's route builder.
/// Percentages are explicitly supplied by the route owner; never guessed
/// from the map style or raw road geometry.
enum ATHLTHRouteSurface: String, CaseIterable, Identifiable {
    case asphalt
    case gravel
    case trail
    case dirt
    case track
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .asphalt: return ATHLTHLocalization.choose(english: "Asphalt", norwegian: "Asfalt")
        case .gravel: return ATHLTHLocalization.choose(english: "Gravel", norwegian: "Grus")
        case .trail: return ATHLTHLocalization.choose(english: "Trail", norwegian: "Sti")
        case .dirt: return ATHLTHLocalization.choose(english: "Dirt road", norwegian: "Jordvei")
        case .track: return ATHLTHLocalization.choose(english: "Running track", norwegian: "Løpebane")
        case .other: return ATHLTHLocalization.choose(english: "Other", norwegian: "Annet")
        }
    }
}

enum ATHLTHRouteDetailsPolicy {
    enum Shape: Equatable {
        case loop
        case outAndBack
        case pointToPoint

        var label: String {
            switch self {
            case .loop: return ATHLTHLocalization.choose(english: "Loop", norwegian: "Rundtur")
            case .outAndBack: return ATHLTHLocalization.choose(english: "Out and back", norwegian: "Tur/retur")
            case .pointToPoint: return ATHLTHLocalization.choose(english: "Point-to-point", norwegian: "A til B")
            }
        }
    }

    static func ordered(_ route: TrainingRoute) -> [RouteCoordinate] {
        route.coordinates.sorted { $0.sequence < $1.sequence }
    }

    static func shape(_ route: TrainingRoute) -> Shape {
        let coordinates = ordered(route).map(\.coordinate)
        guard let first = coordinates.first, let last = coordinates.last,
              CLLocationCoordinate2DIsValid(first),
              CLLocationCoordinate2DIsValid(last) else { return .pointToPoint }
        let source = (route.routeSource ?? "").lowercased()
        if source.contains("out_and_back") ||
            ATHLTHRouteDirectionGeometry.turnaroundIndex(coordinates) != nil {
            return .outAndBack
        }
        let separation = CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
        return separation < 45 ? .loop : .pointToPoint
    }

    static func cleanedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value -> String? in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 28 else { return nil }
            let key = clean.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: Locale(identifier: "nb_NO"))
            guard seen.insert(key).inserted else { return nil }
            return clean
        }.prefix(8).map { $0 }
    }

    static func cleanedSurfaces(_ values: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        var remaining = 100
        for item in ATHLTHRouteSurface.allCases {
            guard let value = values[item.rawValue], value > 0, remaining > 0 else { continue }
            let percent = min(remaining, max(0, value))
            result[item.rawValue] = percent
            remaining -= percent
        }
        return result
    }

    static func unclassifiedPercent(_ values: [String: Int]) -> Int {
        max(0, 100 - cleanedSurfaces(values).values.reduce(0, +))
    }

    static func estimateSeconds(distanceKilometers: Double, running: Bool) -> TimeInterval? {
        guard distanceKilometers.isFinite, distanceKilometers > 0 else { return nil }
        // General estimates only. Do not imply personalized pace or map routing.
        return distanceKilometers * (running ? 6 : 12) * 60
    }

    static func elevationSamples(_ route: TrainingRoute, maximum: Int = 160) -> [Double] {
        let altitudes = ordered(route).compactMap { point -> Double? in
            guard let altitude = point.altitude, altitude.isFinite,
                  altitude >= -500, altitude <= 9000 else { return nil }
            return altitude
        }
        guard altitudes.count >= 2 else { return [] }
        let limit = max(2, maximum)
        guard altitudes.count > limit else { return altitudes }
        let strideCount = max(1, (altitudes.count - 1) / (limit - 1) + 1)
        var samples = Swift.stride(from: 0, to: altitudes.count, by: strideCount)
            .map { altitudes[$0] }
        if let last = altitudes.last, samples.last != last { samples.append(last) }
        return samples
    }

    static func ascentDescent(_ elevations: [Double]) -> (ascent: Double, descent: Double)? {
        guard elevations.count >= 2 else { return nil }
        var ascent = 0.0
        var descent = 0.0
        for index in 1..<elevations.count {
            let delta = elevations[index] - elevations[index - 1]
            // Reject tiny GPS vertical jitter without making up elevation.
            if delta >= 3 { ascent += delta }
            if delta <= -3 { descent += -delta }
        }
        return (ascent, descent)
    }
}

/// Reused on the route creation screen and the owner's route detail page.
/// All fields remain optional; unselected surface means "unknown".
struct ATHLTHRouteMetadataForm: View {
    @Binding var tags: [String]
    @Binding var surfacePercentages: [String: Int]
    @State private var pendingTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(ATHLTHLocalization.choose(english: "Tags", norwegian: "Emneknagger"))
                    .font(.headline)
                HStack(spacing: 8) {
                    TextField(
                        ATHLTHLocalization.choose(
                            english: "e.g. Intervals, Scenic",
                            norwegian: "F.eks. Intervall, Utsikt"
                        ),
                        text: $pendingTag
                    )
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .padding(11)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    Button(action: addTag) {
                        Image(systemName: "plus")
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(pendingTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !tags.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Label(tag, systemImage: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .padding(9)
                                    .background(
                                        ATHLTHPlanDesign.selectedSurface, in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                ATHLTHLocalization.choose(
                                    english: "Remove \(tag)", norwegian: "Fjern \(tag)"
                                )
                            )
                        }
                    }
                }
                Text(ATHLTHLocalization.choose(
                    english: "Up to eight tags. Visible to people who can view this route.",
                    norwegian: "Inntil åtte emneknagger. Vises for dem som har tilgang til ruten."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(ATHLTHLocalization.choose(english: "Surface", norwegian: "Underlag"))
                        .font(.headline)
                    Spacer()
                    Text("\(ATHLTHRouteDetailsPolicy.unclassifiedPercent(surfacePercentages)) % " +
                        ATHLTHLocalization.choose(english: "unknown", norwegian: "ukjent"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(ATHLTHLocalization.choose(
                    english: "Choose the approximate proportions. If you know only one surface, selecting it sets 100%.",
                    norwegian: "Velg omtrentlige andeler. Velger du ett underlag, settes det til 100 %."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(ATHLTHRouteSurface.allCases) { surface in
                    let value = surfacePercentages[surface.rawValue]
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            if value != nil {
                                surfacePercentages.removeValue(forKey: surface.rawValue)
                            } else {
                                let occupied = surfacePercentages.values.reduce(0, +)
                                if occupied == 0 {
                                    surfacePercentages[surface.rawValue] = 100
                                } else if occupied < 100 {
                                    // Explicitly account for previously unknown surface.
                                    surfacePercentages[surface.rawValue] = 100 - occupied
                                } else if let largest = surfacePercentages.max(
                                    by: { $0.value < $1.value }
                                ) {
                                    // Adding another surface should be usable
                                    // immediately, not be stuck at 0% until
                                    // the athlete finds another slider.
                                    let allocation = surfacePercentages.count == 1
                                        ? 50 : min(25, max(5, largest.value / 2))
                                    surfacePercentages[largest.key] =
                                        max(0, largest.value - allocation)
                                    surfacePercentages[surface.rawValue] = allocation
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: value != nil ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                                Text(surface.title)
                                Spacer()
                                if let value { Text("\(value) %").monospacedDigit() }
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHPlanDesign.ink)
                        }
                        .buttonStyle(.plain)
                        if value != nil {
                            Slider(
                                value: Binding(
                                    get: { Double(surfacePercentages[surface.rawValue] ?? 0) },
                                    set: { proposed in
                                        let other = surfacePercentages
                                            .filter { $0.key != surface.rawValue }
                                            .values.reduce(0, +)
                                        surfacePercentages[surface.rawValue] =
                                            min(max(0, 100 - other), Int(proposed.rounded()))
                                    }
                                ),
                                in: 0...100,
                                step: 5
                            )
                            .tint(ATHLTHPlanDesign.accentInk)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if surfacePercentages.isEmpty {
                    Text(ATHLTHLocalization.choose(
                        english: "Surface unknown – nothing has been assumed.",
                        norwegian: "Underlag ukjent – ingenting er antatt."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }

    private func addTag() {
        let cleaned = ATHLTHRouteDetailsPolicy.cleanedTags(tags + [pendingTag])
        if cleaned.count > tags.count { tags = cleaned }
        pendingTag = ""
    }
}
