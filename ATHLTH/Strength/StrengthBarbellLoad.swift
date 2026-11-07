import Foundation

/// Live barbell inputs express loose plate load (both sides combined).
/// Stored set weights, Watch snapshots and historical records always remain
/// total kilograms, including the bar.
enum StrengthBarbellLoad {
    static func plates(totalKilograms: Double, barKilograms: Double) -> Double {
        guard totalKilograms.isFinite, barKilograms.isFinite else { return 0 }
        return max(0, totalKilograms - max(0, barKilograms))
    }

    static func total(platesKilograms: Double, barKilograms: Double) -> Double {
        guard platesKilograms.isFinite, barKilograms.isFinite else { return 0 }
        return max(0, platesKilograms) + max(0, barKilograms)
    }

    /// Changing bar size changes the *active draft* total to preserve the
    /// number of plates entered, without rewriting planned/completed sets.
    static func totalPreservingPlates(
        totalKilograms: Double,
        previousBarKilograms: Double,
        newBarKilograms: Double
    ) -> Double {
        total(
            platesKilograms: plates(
                totalKilograms: totalKilograms, barKilograms: previousBarKilograms
            ),
            barKilograms: newBarKilograms
        )
    }
}
