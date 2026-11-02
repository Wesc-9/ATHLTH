import Foundation

/// Route identity only applies while a matching outdoor route step exists.
/// The metrics always come from the remaining workout timeline.
enum ATHLTHPlannedRoutePreviewPolicy {
    static func activeRouteID(
        selectedRouteID: UUID?,
        routeTitle: String?,
        blocks: [WorkoutTemplateBlock]
    ) -> UUID? {
        guard let selectedRouteID else { return nil }
        return blocks.contains { block in
            block.kind == .run && block.isIndoor != true &&
                (block.routeID == selectedRouteID ||
                 (block.routeID == nil && routeTitle != nil &&
                  block.title == routeTitle))
        } ? selectedRouteID : nil
    }

    static func selectedRouteIDAfterDeleting(
        _ block: WorkoutTemplateBlock,
        selectedRouteID: UUID?,
        routeTitle: String?
    ) -> UUID? {
        guard let selectedRouteID else { return nil }
        let removedRoute = block.kind == .run &&
            (block.routeID == selectedRouteID ||
             (block.routeID == nil && routeTitle != nil &&
              block.title == routeTitle))
        return removedRoute ? nil : selectedRouteID
    }

    static func distanceKilometers(for blocks: [WorkoutTemplateBlock]) -> Double? {
        let meters = blocks.compactMap(\.distanceMeters)
            .filter { $0.isFinite && $0 > 0 }
            .reduce(0, +)
        return meters.isFinite && meters > 0 ? meters / 1_000 : nil
    }
}
