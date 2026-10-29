import Foundation

/// A population-based estimate for adults who have not measured HRmax.
/// Never present this as a measured value; an individually tested HRmax
/// takes priority when setting zones and workout guidance.
enum ATHLTHMaximumHeartRateEstimator {
    struct Result: Equatable {
        let beatsPerMinute: Int
        let ageYears: Int
        let usesFemaleEquation: Bool
    }

    static func estimate(
        dateOfBirth: Date?,
        healthSex: HealthSex?,
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> Result? {
        guard let dateOfBirth,
              dateOfBirth <= date,
              let age = calendar.dateComponents(
                  [.year],
                  from: calendar.startOfDay(for: dateOfBirth),
                  to: calendar.startOfDay(for: date)
              ).year,
              (18...100).contains(age)
        else { return nil }

        // Gulati et al. (2010): women, 206 - 0.88 * age.
        // Tanaka et al. (2001): general adult population,
        // 208 - 0.7 * age. Used for men and unspecified sex.
        let usesFemaleEquation = healthSex == .female
        let predicted = usesFemaleEquation
            ? 206.0 - 0.88 * Double(age)
            : 208.0 - 0.7 * Double(age)
        guard predicted.isFinite else { return nil }

        return Result(
            beatsPerMinute: Int(predicted.rounded()),
            ageYears: age,
            usesFemaleEquation: usesFemaleEquation
        )
    }
}
