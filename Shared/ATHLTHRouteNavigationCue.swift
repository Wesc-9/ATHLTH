import CoreLocation
import Foundation

/// Route-geometry guidance for a running screen; this is deliberately not
/// road-level turn-by-turn navigation. The polyline does not prove that an
/// intersection exists, so never say "first street" or invent road names.
enum ATHLTHRouteNavigationCue {
    enum Direction: String, Equatable {
        case left
        case right
        case ahead
        case behind
    }

    struct Instruction: Equatable {
        let direction: Direction
        let distanceMeters: Double
        let offRoute: Bool
        let pointIndex: Int?

        var symbol: String {
            switch direction {
            case .left: return "arrow.turn.up.left"
            case .right: return "arrow.turn.up.right"
            case .ahead: return "arrow.up"
            case .behind: return "arrow.uturn.backward"
            }
        }

        func text(norwegian: Bool) -> String {
            if offRoute {
                switch direction {
                case .left:
                    return norwegian
                        ? "Ruten ligger til venstre. Gå mot den markerte ruten."
                        : "The route is to your left. Head toward the marked route."
                case .right:
                    return norwegian
                        ? "Ruten ligger til høyre. Gå mot den markerte ruten."
                        : "The route is to your right. Head toward the marked route."
                case .behind:
                    return norwegian
                        ? "Ruten ligger bak deg. Snu mot den markerte ruten."
                        : "The route is behind you. Turn toward the marked route."
                case .ahead:
                    return norwegian
                        ? "Fortsett mot den markerte ruten."
                        : "Continue toward the highlighted route."
                }
            }
            switch direction {
            case .left:
                return norwegian ? "Ruten svinger mot venstre." : "The route bends left."
            case .right:
                return norwegian ? "Ruten svinger mot høyre." : "The route bends right."
            case .ahead:
                return norwegian ? "Følg ruten videre." : "Follow the route ahead."
            case .behind:
                return norwegian ? "Ruten går tilbake." : "The route doubles back."
            }
        }
    }

    static func nextTurn(
        route: [CLLocationCoordinate2D],
        nearestIndex: Int
    ) -> Instruction? {
        guard route.count >= 4, route.indices.contains(nearestIndex) else {
            return nil
        }
        let cumulative = cumulativeDistance(route)
        let origin = cumulative[nearestIndex]
        // A meaningful turn must have stable geometry on both sides.
        // Ignore very short GPS zigzags and bends at the finish.
        for index in (nearestIndex + 1)..<(route.count - 1) {
            let distance = cumulative[index] - origin
            if distance < 15 { continue }
            if distance > 220 { break }
            guard let before = priorIndex(cumulative, cumulative[index] - 28),
                  let after = indexAtDistance(cumulative, cumulative[index] + 28),
                  before < index, after > index else { continue }
            let inbound = bearing(route[before], route[index])
            let outbound = bearing(route[index], route[after])
            let angle = signedAngle(from: inbound, to: outbound)
            guard abs(angle) >= 52, abs(angle) <= 160 else { continue }
            return Instruction(
                direction: angle > 0 ? .right : .left,
                distanceMeters: distance,
                offRoute: false,
                pointIndex: index
            )
        }
        return nil
    }

    static func recovery(
        user: CLLocationCoordinate2D,
        courseDegrees: Double?,
        route: [CLLocationCoordinate2D],
        nearestIndex: Int,
        deviationMeters: Double
    ) -> Instruction? {
        guard route.indices.contains(nearestIndex),
              CLLocationCoordinate2DIsValid(user),
              deviationMeters.isFinite, deviationMeters > 0 else { return nil }
        // Without a valid direction of travel we cannot label left/right.
        guard let courseDegrees, courseDegrees.isFinite,
              courseDegrees >= 0, courseDegrees < 360 else {
            return Instruction(direction: .ahead,
                               distanceMeters: deviationMeters, offRoute: true,
                               pointIndex: nil)
        }
        let angle = signedAngle(
            from: courseDegrees,
            to: bearing(user, route[nearestIndex])
        )
        let direction: Direction
        if abs(angle) > 145 { direction = .behind }
        else if angle >= 32 { direction = .right }
        else if angle <= -32 { direction = .left }
        else { direction = .ahead }
        return Instruction(
            direction: direction,
            distanceMeters: deviationMeters,
            offRoute: true,
            pointIndex: nil
        )
    }

    private static func cumulativeDistance(
        _ route: [CLLocationCoordinate2D]
    ) -> [Double] {
        var cumulative = [0.0]
        for index in 1..<route.count {
            cumulative.append(cumulative[index - 1] +
                CLLocation(latitude: route[index - 1].latitude,
                           longitude: route[index - 1].longitude)
                    .distance(from: CLLocation(latitude: route[index].latitude,
                                               longitude: route[index].longitude)))
        }
        return cumulative
    }

    private static func priorIndex(
        _ cumulative: [Double], _ distance: Double
    ) -> Int? {
        guard distance >= 0 else { return nil }
        return cumulative.lastIndex(where: { $0 <= distance })
    }

    private static func indexAtDistance(
        _ cumulative: [Double], _ distance: Double
    ) -> Int? {
        guard distance > 0, let last = cumulative.last,
              distance < last else { return nil }
        return cumulative.firstIndex(where: { $0 >= distance })
    }

    private static func bearing(
        _ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D
    ) -> Double {
        let first = from.latitude * .pi / 180
        let second = to.latitude * .pi / 180
        let difference = (to.longitude - from.longitude) * .pi / 180
        let y = sin(difference) * cos(second)
        let x = cos(first) * sin(second) -
            sin(first) * cos(second) * cos(difference)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func signedAngle(from: Double, to: Double) -> Double {
        (to - from + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}
