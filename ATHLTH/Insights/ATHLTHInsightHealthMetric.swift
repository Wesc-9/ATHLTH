import Foundation
import HealthKit

/// The six editorial areas in Insights. All measurements remain optional.
enum ATHLTHInsightHealthArea: String, CaseIterable, Identifiable {
    case sleep, vitalSigns, fitness, recovery, movement, body

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return ATHLTHLocalization.choose(english: "Sleep", norwegian: "Søvn")
        case .vitalSigns: return ATHLTHLocalization.choose(english: "Vital signs", norwegian: "Kroppens signaler")
        case .fitness: return ATHLTHLocalization.choose(english: "Fitness", norwegian: "Kondisjon")
        case .recovery: return ATHLTHLocalization.choose(english: "After exercise", norwegian: "Etter trening")
        case .movement: return ATHLTHLocalization.choose(english: "Walking & running", norwegian: "Gange og løping")
        case .body: return ATHLTHLocalization.choose(english: "Body measurements", norwegian: "Kroppsutvikling")
        }
    }

    var icon: String {
        switch self {
        case .sleep: "moon.stars.fill"
        case .vitalSigns: "waveform.path.ecg"
        case .fitness: "heart.fill"
        case .recovery: "heart.text.square"
        case .movement: "figure.run"
        case .body: "scalemass"
        }
    }

    var detail: String {
        switch self {
        case .sleep: return ATHLTHLocalization.choose(english: "Stages and overnight history", norwegian: "Søvnfaser og søvnhistorikk")
        case .vitalSigns: return ATHLTHLocalization.choose(english: "Personal trends, not diagnoses", norwegian: "Personlige trender, ikke diagnoser")
        case .fitness: return ATHLTHLocalization.choose(english: "Cardio fitness over time", norwegian: "Kondisjon over tid")
        case .recovery: return ATHLTHLocalization.choose(english: "Measured post-workout heart-rate recovery", norwegian: "Målt pulsfall etter trening")
        case .movement: return ATHLTHLocalization.choose(english: "Walking and running mechanics", norwegian: "Gang- og løpsmålinger")
        case .body: return ATHLTHLocalization.choose(english: "Measurements without weight targets", norwegian: "Målinger uten vektmål")
        }
    }
}

enum ATHLTHInsightHealthMetric: String, CaseIterable, Identifiable {
    case sleepDuration, sleepCore, sleepDeep, sleepREM, sleepAwake
    case restingHeartRate, hrv, respiratoryRate, oxygenSaturation, wristTemperature
    case vo2Max, heartRateRecovery, walkingHeartRate
    case walkingSpeed, walkingStepLength, runningStrideLength
    case runningVerticalOscillation, runningGroundContactTime, steps
    case bodyMass, bodyMassIndex, bodyFatPercentage

    var id: String { rawValue }

    var area: ATHLTHInsightHealthArea {
        switch self {
        case .sleepDuration, .sleepCore, .sleepDeep, .sleepREM, .sleepAwake: .sleep
        case .restingHeartRate, .hrv, .respiratoryRate, .oxygenSaturation, .wristTemperature: .vitalSigns
        case .vo2Max, .walkingHeartRate: .fitness
        case .heartRateRecovery: .recovery
        case .walkingSpeed, .walkingStepLength, .runningStrideLength,
             .runningVerticalOscillation, .runningGroundContactTime, .steps: .movement
        case .bodyMass, .bodyMassIndex, .bodyFatPercentage: .body
        }
    }

    var title: String {
        switch self {
        case .sleepDuration: return ATHLTHLocalization.choose(english: "Total sleep", norwegian: "Total søvn")
        case .sleepCore: return ATHLTHLocalization.choose(english: "Core sleep", norwegian: "Kjernesøvn")
        case .sleepDeep: return ATHLTHLocalization.choose(english: "Deep sleep", norwegian: "Dyp søvn")
        case .sleepREM: return "REM"
        case .sleepAwake: return ATHLTHLocalization.choose(english: "Awake", norwegian: "Våken")
        case .restingHeartRate: return ATHLTHLocalization.choose(english: "Resting heart rate", norwegian: "Hvilepuls")
        case .hrv: return "HRV"
        case .respiratoryRate: return ATHLTHLocalization.choose(english: "Respiratory rate", norwegian: "Respirasjon")
        case .oxygenSaturation: return ATHLTHLocalization.choose(english: "Oxygen saturation", norwegian: "Oksygenmetning")
        case .wristTemperature: return ATHLTHLocalization.choose(english: "Wrist temperature", norwegian: "Håndleddtemperatur")
        case .vo2Max: return "VO₂ maks"
        case .heartRateRecovery: return ATHLTHLocalization.choose(english: "Heart-rate recovery", norwegian: "Pulsfall etter økt")
        case .walkingHeartRate: return ATHLTHLocalization.choose(english: "Walking heart rate", norwegian: "Gåpuls")
        case .walkingSpeed: return ATHLTHLocalization.choose(english: "Walking speed", norwegian: "Ganghastighet")
        case .walkingStepLength: return ATHLTHLocalization.choose(english: "Walking step length", norwegian: "Steglengde gange")
        case .runningStrideLength: return ATHLTHLocalization.choose(english: "Running stride length", norwegian: "Steglengde løping")
        case .runningVerticalOscillation: return ATHLTHLocalization.choose(english: "Vertical oscillation", norwegian: "Vertikal bevegelse")
        case .runningGroundContactTime: return ATHLTHLocalization.choose(english: "Ground contact time", norwegian: "Bakkekontakttid")
        case .steps: return ATHLTHLocalization.choose(english: "Daily steps", norwegian: "Daglige skritt")
        case .bodyMass: return ATHLTHLocalization.choose(english: "Body weight", norwegian: "Vekt")
        case .bodyMassIndex: return "BMI"
        case .bodyFatPercentage: return ATHLTHLocalization.choose(english: "Body fat", norwegian: "Fettprosent")
        }
    }

    var icon: String {
        switch area {
        case .sleep: "moon.stars.fill"
        case .vitalSigns: "heart.text.square"
        case .fitness: "heart.fill"
        case .recovery: "heart.circle"
        case .movement: "figure.walk"
        case .body: "scalemass"
        }
    }

    var unitLabel: String {
        switch self {
        case .sleepDuration, .sleepCore, .sleepDeep, .sleepREM, .sleepAwake: return "t"
        case .restingHeartRate, .walkingHeartRate: return "bpm"
        case .hrv, .runningGroundContactTime: return "ms"
        case .respiratoryRate: return ATHLTHLocalization.choose(english: "breaths/min", norwegian: "pust/min")
        case .oxygenSaturation, .bodyFatPercentage: return "%"
        case .wristTemperature: return "°C"
        case .vo2Max: return "ml/kg/min"
        case .heartRateRecovery: return "slag"
        case .walkingSpeed: return "km/t"
        case .walkingStepLength, .runningVerticalOscillation: return "cm"
        case .runningStrideLength: return "m"
        case .steps: return ATHLTHLocalization.choose(english: "steps", norwegian: "skritt")
        case .bodyMass: return "kg"
        case .bodyMassIndex: return ""
        }
    }

    /// Raw HealthKit unit and normalization into the displayed value.
    var query: (identifier: HKQuantityTypeIdentifier, unit: HKUnit, multiplier: Double)? {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        switch self {
        case .sleepDuration, .sleepCore, .sleepDeep, .sleepREM, .sleepAwake: return nil
        case .restingHeartRate: return (.restingHeartRate, perMinute, 1)
        case .hrv: return (.heartRateVariabilitySDNN, .secondUnit(with: .milli), 1)
        case .respiratoryRate: return (.respiratoryRate, perMinute, 1)
        case .oxygenSaturation: return (.oxygenSaturation, .percent(), 100)
        case .wristTemperature: return (.appleSleepingWristTemperature, .degreeCelsius(), 1)
        case .vo2Max: return (.vo2Max, HKUnit(from: "ml/kg*min"), 1)
        case .heartRateRecovery: return (.heartRateRecoveryOneMinute, .count(), 1)
        case .walkingHeartRate: return (.walkingHeartRateAverage, perMinute, 1)
        case .walkingSpeed: return (.walkingSpeed, .meter().unitDivided(by: .second()), 3.6)
        case .walkingStepLength: return (.walkingStepLength, .meter(), 100)
        case .runningStrideLength: return (.runningStrideLength, .meter(), 1)
        case .runningVerticalOscillation: return (.runningVerticalOscillation, .meter(), 100)
        case .runningGroundContactTime: return (.runningGroundContactTime, .secondUnit(with: .milli), 1)
        case .steps: return (.stepCount, .count(), 1)
        case .bodyMass: return (.bodyMass, .gramUnit(with: .kilo), 1)
        case .bodyMassIndex: return (.bodyMassIndex, .count(), 1)
        case .bodyFatPercentage: return (.bodyFatPercentage, .percent(), 100)
        }
    }

    var cumulative: Bool { self == .steps }

    /// A missing measurement remains nil. Never synthesize a reading from age,
    /// workout duration, or a different physiological quantity.
    @MainActor
    func currentValue(in health: HealthKitManager) -> Double? {
        switch self {
        case .sleepDuration: return health.sleep.totalAsleep > 0 ? health.sleep.totalAsleep / 3600 : nil
        case .sleepCore: return health.sleep.core > 0 ? health.sleep.core / 3600 : nil
        case .sleepDeep: return health.sleep.deep > 0 ? health.sleep.deep / 3600 : nil
        case .sleepREM: return health.sleep.rem > 0 ? health.sleep.rem / 3600 : nil
        case .sleepAwake: return health.sleep.awake > 0 ? health.sleep.awake / 3600 : nil
        case .restingHeartRate: return health.heart.restingHeartRate
        case .hrv: return health.heart.hrvMilliseconds
        case .respiratoryRate: return health.training.respiratoryRate
        case .oxygenSaturation: return health.training.oxygenSaturationPercent
        case .vo2Max: return health.training.vo2Max
        case .walkingHeartRate: return health.training.walkingHeartRateAverage
        case .steps: return health.training.stepsToday
        default: return nil
        }
    }

    func formatted(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        let precision = switch self {
        case .sleepDuration, .sleepCore, .sleepDeep, .sleepREM, .sleepAwake,
             .vo2Max, .bodyMass, .bodyMassIndex, .bodyFatPercentage,
             .wristTemperature, .walkingSpeed, .runningStrideLength: 1
        case .runningVerticalOscillation, .walkingStepLength: 1
        default: 0
        }
        let result = value.formatted(.number.precision(.fractionLength(0...precision)))
        return unitLabel.isEmpty ? result : result + " " + unitLabel
    }
}

struct ATHLTHInsightHealthDay: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}
