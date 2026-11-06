import Foundation

/// Bar mass is part of the TOTAL kilograms shown for a working set.
/// It must never be added again to volume or PR calculations.
@MainActor
enum StrengthBarWeightPreferences {
    static let supportedMasses: [Double] = [
        0, 2.5, 5, 7.5, 10, 12.5, 15, 17.5, 20, 22.5, 25, 30
    ]

    static func defaultMass(userID: UUID?) -> Double {
        guard let userID else { return 20 }
        return AccountLocalStorage.read(
            Double.self,
            name: "strengthBarDefaultMassV1",
            userID: userID
        ) ?? 20
    }

    static func setDefaultMass(_ kilograms: Double, userID: UUID) {
        guard kilograms.isFinite, (0...40).contains(kilograms) else {
            return
        }
        AccountLocalStorage.write(
            kilograms, name: "strengthBarDefaultMassV1", userID: userID
        )
    }

    private static func key(for exercise: String) -> String {
        exercise
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func overrides(userID: UUID) -> [String: Double] {
        AccountLocalStorage.read(
            [String: Double].self,
            name: "strengthBarExerciseMassV1",
            userID: userID
        ) ?? [:]
    }

    static func mass(for exercise: String, userID: UUID?) -> Double {
        guard let userID else { return 20 }
        return overrides(userID: userID)[key(for: exercise)] ??
            defaultMass(userID: userID)
    }

    static func setExerciseMass(
        _ kilograms: Double?,
        for exercise: String,
        userID: UUID
    ) {
        guard kilograms == nil ||
              (kilograms!.isFinite && (0...40).contains(kilograms!))
        else { return }
        var values = overrides(userID: userID)
        values[key(for: exercise)] = kilograms
        AccountLocalStorage.write(
            values,
            name: "strengthBarExerciseMassV1",
            userID: userID
        )
    }
}
