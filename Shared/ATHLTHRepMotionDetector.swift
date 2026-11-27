import Foundation

/// Conservative experimental wrist-rotation cycle detector. This is NOT
/// exercise recognition or a trained model. Reject incomplete cycles,
/// gaps, noise and very fast reversals. Only proposes a draft count.
struct ATHLTHRepMotionDetector {
    private(set) var count = 0
    private var lastTimestamp: Double?
    private var axis: Int?
    private var direction: Double = 0
    private var outward = 0.0
    private var inward = 0.0
    private var cycleStart: Double?
    private var returning = false

    mutating func reset() { self = Self() }

    private mutating func resetCycle() {
        axis = nil; direction = 0; outward = 0; inward = 0
        cycleStart = nil; returning = false
    }

    @discardableResult
    mutating func ingest(timestamp: Double, x: Double, y: Double, z: Double) -> Int {
        guard timestamp.isFinite, x.isFinite, y.isFinite, z.isFinite else {
            resetCycle(); lastTimestamp = nil; return count
        }
        let previous = lastTimestamp
        lastTimestamp = timestamp
        guard let previous else { return count }
        let dt = timestamp - previous
        guard dt > 0, dt <= 0.25 else { resetCycle(); return count }
        let rates = [x, y, z]
        guard rates.allSatisfy({ abs($0) <= 12 }) else { resetCycle(); return count }
        if let cycleStart, timestamp - cycleStart > 10 { resetCycle() }
        if axis == nil {
            guard let dominant = rates.indices.max(by: { abs(rates[$0]) < abs(rates[$1]) }),
                  abs(rates[dominant]) >= 0.45 else { return count }
            axis = dominant
            direction = rates[dominant] > 0 ? 1 : -1
            cycleStart = timestamp
        }
        guard let axis, let cycleStart else { return count }
        let signed = rates[axis] * direction
        if !returning {
            if signed > 0.15 { outward += signed * dt }
            else if signed < -0.25 {
                guard outward >= 0.6 else { resetCycle(); return count }
                returning = true
                inward = -signed * dt
            }
        } else {
            if signed < -0.15 { inward += -signed * dt }
            else if signed > 0.35 { resetCycle(); return count }
            if inward >= max(0.55, outward * 0.8) {
                if timestamp - cycleStart >= 0.7 && count < 100 { count += 1 }
                resetCycle()
            }
        }
        return count
    }
}
