import Foundation

/// Targets for one strength set. Keeping these on the parent exercise prevents
/// the planning timeline from turning every set into a separate exercise.
struct ATHLTHStrengthSetTarget: Codable, Hashable {
    var repetitions: Int?
    var weightKilograms: Double?
}
