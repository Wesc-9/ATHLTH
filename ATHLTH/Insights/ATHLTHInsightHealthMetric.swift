import Foundation
import HealthKit

/// The six editorial areas in Insights. All measurements remain optional.
enum ATHLTHInsightHealthArea: String, CaseIterable, Identifiable {
    case sleep, vitalSigns, fitness, recovery, movement, body, activity, mobility, nutrition, hearing, clinical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return ATHLTHLocalization.choose(english: "Sleep", norwegian: "Søvn")
        case .vitalSigns: return ATHLTHLocalization.choose(english: "Vital signs", norwegian: "Kroppens signaler")
        case .fitness: return ATHLTHLocalization.choose(english: "Fitness", norwegian: "Kondisjon")
        case .recovery: return ATHLTHLocalization.choose(english: "After exercise", norwegian: "Etter trening")
        case .movement: return ATHLTHLocalization.choose(english: "Walking & running", norwegian: "Gange og løping")
        case .body: return ATHLTHLocalization.choose(english: "Body measurements", norwegian: "Kroppsutvikling")
        case .activity: return ATHLTHLocalization.choose(english: "Daily activity", norwegian: "Daglig aktivitet")
        case .mobility: return ATHLTHLocalization.choose(english: "Mobility", norwegian: "Bevegelighet og gange")
        case .nutrition: return ATHLTHLocalization.choose(english: "Nutrition", norwegian: "Ernæring")
        case .hearing: return ATHLTHLocalization.choose(english: "Hearing", norwegian: "Hørsel og lydmiljø")
        case .clinical: return ATHLTHLocalization.choose(english: "Additional health", norwegian: "Andre helsemålinger")
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
        case .activity: return "figure.walk.motion"
        case .mobility: return "figure.walk"
        case .nutrition: return "drop.fill"
        case .hearing: return "ear.badge.waveform"
        case .clinical: return "cross.case"
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
        case .activity: return ATHLTHLocalization.choose(english: "Energy, distance and daily activity", norwegian: "Energi, distanse og daglig aktivitet")
        case .mobility: return ATHLTHLocalization.choose(english: "Steadiness, symmetry and walking tests", norwegian: "Stabilitet, symmetri og gangtester")
        case .nutrition: return ATHLTHLocalization.choose(english: "Recorded food, water and nutrients", norwegian: "Registrert mat, drikke og næringsstoffer")
        case .hearing: return ATHLTHLocalization.choose(english: "Recorded sound exposure", norwegian: "Registrert lydpåvirkning")
        case .clinical: return ATHLTHLocalization.choose(english: "Optional readings; not medical advice", norwegian: "Valgfrie målinger, ikke medisinske råd")
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
    case heartRate
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case bodyTemperature
    case basalBodyTemperature
    case activeEnergy
    case basalEnergy
    case exerciseMinutes
    case standMinutes
    case walkingRunningDistance
    case cyclingDistance
    case swimmingDistance
    case flightsClimbed
    case daylightMinutes
    case runningSpeed
    case runningPower
    case cyclingSpeed
    case cyclingPower
    case swimmingStrokeCount
    case walkingAsymmetry
    case walkingDoubleSupport
    case walkingSteadiness
    case stairAscentSpeed
    case stairDescentSpeed
    case sixMinuteWalkDistance
    case height
    case leanBodyMass
    case waistCircumference
    case dietaryEnergy
    case dietaryWater
    case dietaryProtein
    case dietaryCarbohydrates
    case dietaryFat
    case dietaryFiber
    case dietarySugar
    case dietarySodium
    case dietaryCaffeine
    case dietaryPotassium
    case dietaryIron
    case dietaryCalcium
    case dietaryVitaminD
    case environmentalAudioExposure
    case headphoneAudioExposure
    case bloodGlucose
    case insulinDelivery
    case numberOfTimesFallen
    case inhalerUsage
    case forcedExpiratoryVolume1
    case forcedVitalCapacity
    case peakExpiratoryFlowRate
    case peripheralPerfusionIndex
    case atrialFibrillationBurden

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
        case .heartRate, .bloodPressureSystolic, .bloodPressureDiastolic, .bodyTemperature, .basalBodyTemperature: .vitalSigns
        case .activeEnergy, .basalEnergy, .exerciseMinutes, .standMinutes, .walkingRunningDistance, .cyclingDistance, .swimmingDistance, .flightsClimbed, .daylightMinutes: .activity
        case .runningSpeed, .runningPower, .cyclingSpeed, .cyclingPower, .swimmingStrokeCount: .fitness
        case .walkingAsymmetry, .walkingDoubleSupport, .walkingSteadiness, .stairAscentSpeed, .stairDescentSpeed, .sixMinuteWalkDistance: .mobility
        case .height, .leanBodyMass, .waistCircumference: .body
        case .dietaryEnergy, .dietaryWater, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat, .dietaryFiber, .dietarySugar, .dietarySodium, .dietaryCaffeine, .dietaryPotassium, .dietaryIron, .dietaryCalcium, .dietaryVitaminD: .nutrition
        case .environmentalAudioExposure, .headphoneAudioExposure: .hearing
        case .bloodGlucose, .insulinDelivery, .numberOfTimesFallen, .inhalerUsage, .forcedExpiratoryVolume1, .forcedVitalCapacity, .peakExpiratoryFlowRate, .peripheralPerfusionIndex, .atrialFibrillationBurden: .clinical
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
        case .heartRate: return ATHLTHLocalization.choose(english: "Heart rate", norwegian: "Puls")
        case .bloodPressureSystolic: return ATHLTHLocalization.choose(english: "Systolic blood pressure", norwegian: "Overtrykk")
        case .bloodPressureDiastolic: return ATHLTHLocalization.choose(english: "Diastolic blood pressure", norwegian: "Undertrykk")
        case .bodyTemperature: return ATHLTHLocalization.choose(english: "Body temperature", norwegian: "Kroppstemperatur")
        case .basalBodyTemperature: return ATHLTHLocalization.choose(english: "Basal temperature", norwegian: "Basaltemperatur")
        case .activeEnergy: return ATHLTHLocalization.choose(english: "Active energy", norwegian: "Aktive kalorier")
        case .basalEnergy: return ATHLTHLocalization.choose(english: "Resting energy", norwegian: "Hvileforbrenning")
        case .exerciseMinutes: return ATHLTHLocalization.choose(english: "Exercise time", norwegian: "Treningstid")
        case .standMinutes: return ATHLTHLocalization.choose(english: "Standing time", norwegian: "Ståtid")
        case .walkingRunningDistance: return ATHLTHLocalization.choose(english: "Walking and running distance", norwegian: "Gå- og løpedistanse")
        case .cyclingDistance: return ATHLTHLocalization.choose(english: "Cycling distance", norwegian: "Sykkeldistanse")
        case .swimmingDistance: return ATHLTHLocalization.choose(english: "Swimming distance", norwegian: "Svømmedistanse")
        case .flightsClimbed: return ATHLTHLocalization.choose(english: "Flights climbed", norwegian: "Etasjer gått")
        case .daylightMinutes: return ATHLTHLocalization.choose(english: "Time in daylight", norwegian: "Tid i dagslys")
        case .runningSpeed: return ATHLTHLocalization.choose(english: "Running speed", norwegian: "Løpshastighet")
        case .runningPower: return ATHLTHLocalization.choose(english: "Running power", norwegian: "Løpskraft")
        case .cyclingSpeed: return ATHLTHLocalization.choose(english: "Cycling speed", norwegian: "Sykkelhastighet")
        case .cyclingPower: return ATHLTHLocalization.choose(english: "Cycling power", norwegian: "Sykkelwatt")
        case .swimmingStrokeCount: return ATHLTHLocalization.choose(english: "Swimming strokes", norwegian: "Svømmetak")
        case .walkingAsymmetry: return ATHLTHLocalization.choose(english: "Walking asymmetry", norwegian: "Gangeasymmetri")
        case .walkingDoubleSupport: return ATHLTHLocalization.choose(english: "Double support time", norwegian: "Dobbel støttetid")
        case .walkingSteadiness: return ATHLTHLocalization.choose(english: "Walking steadiness", norwegian: "Gangstabilitet")
        case .stairAscentSpeed: return ATHLTHLocalization.choose(english: "Stair ascent speed", norwegian: "Hastighet opp trapper")
        case .stairDescentSpeed: return ATHLTHLocalization.choose(english: "Stair descent speed", norwegian: "Hastighet ned trapper")
        case .sixMinuteWalkDistance: return ATHLTHLocalization.choose(english: "Six-minute walk distance", norwegian: "6-minutters gangtest")
        case .height: return ATHLTHLocalization.choose(english: "Height", norwegian: "Høyde")
        case .leanBodyMass: return ATHLTHLocalization.choose(english: "Lean body mass", norwegian: "Fettfri kroppsmasse")
        case .waistCircumference: return ATHLTHLocalization.choose(english: "Waist circumference", norwegian: "Midjemål")
        case .dietaryEnergy: return ATHLTHLocalization.choose(english: "Energy intake", norwegian: "Energiinntak")
        case .dietaryWater: return ATHLTHLocalization.choose(english: "Water intake", norwegian: "Væskeinntak")
        case .dietaryProtein: return ATHLTHLocalization.choose(english: "Protein", norwegian: "Protein")
        case .dietaryCarbohydrates: return ATHLTHLocalization.choose(english: "Carbohydrates", norwegian: "Karbohydrater")
        case .dietaryFat: return ATHLTHLocalization.choose(english: "Total fat", norwegian: "Totalt fett")
        case .dietaryFiber: return ATHLTHLocalization.choose(english: "Fiber", norwegian: "Kostfiber")
        case .dietarySugar: return ATHLTHLocalization.choose(english: "Sugar", norwegian: "Sukker")
        case .dietarySodium: return ATHLTHLocalization.choose(english: "Sodium", norwegian: "Natrium")
        case .dietaryCaffeine: return ATHLTHLocalization.choose(english: "Caffeine", norwegian: "Koffein")
        case .dietaryPotassium: return ATHLTHLocalization.choose(english: "Potassium", norwegian: "Kalium")
        case .dietaryIron: return ATHLTHLocalization.choose(english: "Iron", norwegian: "Jern")
        case .dietaryCalcium: return ATHLTHLocalization.choose(english: "Calcium", norwegian: "Kalsium")
        case .dietaryVitaminD: return ATHLTHLocalization.choose(english: "Vitamin D", norwegian: "Vitamin D")
        case .environmentalAudioExposure: return ATHLTHLocalization.choose(english: "Environmental noise", norwegian: "Miljøstøy")
        case .headphoneAudioExposure: return ATHLTHLocalization.choose(english: "Headphone audio level", norwegian: "Lydnivå i hodetelefoner")
        case .bloodGlucose: return ATHLTHLocalization.choose(english: "Blood glucose", norwegian: "Blodsukker")
        case .insulinDelivery: return ATHLTHLocalization.choose(english: "Insulin delivery", norwegian: "Insulindose")
        case .numberOfTimesFallen: return ATHLTHLocalization.choose(english: "Falls recorded", norwegian: "Registrerte fall")
        case .inhalerUsage: return ATHLTHLocalization.choose(english: "Inhaler use", norwegian: "Inhalatorbruk")
        case .forcedExpiratoryVolume1: return ATHLTHLocalization.choose(english: "FEV1", norwegian: "FEV1")
        case .forcedVitalCapacity: return ATHLTHLocalization.choose(english: "Forced vital capacity", norwegian: "Forsert vitalkapasitet")
        case .peakExpiratoryFlowRate: return ATHLTHLocalization.choose(english: "Peak expiratory flow", norwegian: "Maksimal ekspirasjonsstrøm")
        case .peripheralPerfusionIndex: return ATHLTHLocalization.choose(english: "Perfusion index", norwegian: "Perfusjonsindeks")
        case .atrialFibrillationBurden: return ATHLTHLocalization.choose(english: "Atrial fibrillation burden", norwegian: "Andel tid med atrieflimmer")
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
        case .activity: "figure.walk.motion"
        case .mobility: "figure.walk"
        case .nutrition: "drop.fill"
        case .hearing: "ear.badge.waveform"
        case .clinical: "cross.case"
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
        case .heartRate: return "bpm"
        case .bloodPressureSystolic: return "mmHg"
        case .bloodPressureDiastolic: return "mmHg"
        case .bodyTemperature: return "°C"
        case .basalBodyTemperature: return "°C"
        case .activeEnergy: return "kcal"
        case .basalEnergy: return "kcal"
        case .exerciseMinutes: return "min"
        case .standMinutes: return "min"
        case .walkingRunningDistance: return "km"
        case .cyclingDistance: return "km"
        case .swimmingDistance: return "m"
        case .flightsClimbed: return "etasjer"
        case .daylightMinutes: return "min"
        case .runningSpeed: return "km/t"
        case .runningPower: return "W"
        case .cyclingSpeed: return "km/t"
        case .cyclingPower: return "W"
        case .swimmingStrokeCount: return "tak"
        case .walkingAsymmetry: return "%"
        case .walkingDoubleSupport: return "%"
        case .walkingSteadiness: return "%"
        case .stairAscentSpeed: return "m/s"
        case .stairDescentSpeed: return "m/s"
        case .sixMinuteWalkDistance: return "m"
        case .height: return "cm"
        case .leanBodyMass: return "kg"
        case .waistCircumference: return "cm"
        case .dietaryEnergy: return "kcal"
        case .dietaryWater: return "ml"
        case .dietaryProtein: return "g"
        case .dietaryCarbohydrates: return "g"
        case .dietaryFat: return "g"
        case .dietaryFiber: return "g"
        case .dietarySugar: return "g"
        case .dietarySodium: return "mg"
        case .dietaryCaffeine: return "mg"
        case .dietaryPotassium: return "mg"
        case .dietaryIron: return "mg"
        case .dietaryCalcium: return "mg"
        case .dietaryVitaminD: return "µg"
        case .environmentalAudioExposure: return "dB(A)"
        case .headphoneAudioExposure: return "dB(A)"
        case .bloodGlucose: return "mg/dL"
        case .insulinDelivery: return "IE"
        case .numberOfTimesFallen: return "fall"
        case .inhalerUsage: return "doser"
        case .forcedExpiratoryVolume1: return "L"
        case .forcedVitalCapacity: return "L"
        case .peakExpiratoryFlowRate: return "L/min"
        case .peripheralPerfusionIndex: return "%"
        case .atrialFibrillationBurden: return "%"
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
        case .heartRate: return (.heartRate, HKUnit.count().unitDivided(by: .minute()), 1)
        case .bloodPressureSystolic: return (.bloodPressureSystolic, HKUnit.millimeterOfMercury(), 1)
        case .bloodPressureDiastolic: return (.bloodPressureDiastolic, HKUnit.millimeterOfMercury(), 1)
        case .bodyTemperature: return (.bodyTemperature, HKUnit.degreeCelsius(), 1)
        case .basalBodyTemperature: return (.basalBodyTemperature, HKUnit.degreeCelsius(), 1)
        case .activeEnergy: return (.activeEnergyBurned, HKUnit.kilocalorie(), 1)
        case .basalEnergy: return (.basalEnergyBurned, HKUnit.kilocalorie(), 1)
        case .exerciseMinutes: return (.appleExerciseTime, HKUnit.minute(), 1)
        case .standMinutes: return (.appleStandTime, HKUnit.minute(), 1)
        case .walkingRunningDistance: return (.distanceWalkingRunning, HKUnit.meter(), 0.001)
        case .cyclingDistance: return (.distanceCycling, HKUnit.meter(), 0.001)
        case .swimmingDistance: return (.distanceSwimming, HKUnit.meter(), 1)
        case .flightsClimbed: return (.flightsClimbed, HKUnit.count(), 1)
        case .daylightMinutes: return (.timeInDaylight, HKUnit.minute(), 1)
        case .runningSpeed: return (.runningSpeed, HKUnit.meter().unitDivided(by: .second()), 3.6)
        case .runningPower: return (.runningPower, HKUnit.watt(), 1)
        case .cyclingSpeed: return (.cyclingSpeed, HKUnit.meter().unitDivided(by: .second()), 3.6)
        case .cyclingPower: return (.cyclingPower, HKUnit.watt(), 1)
        case .swimmingStrokeCount: return (.swimmingStrokeCount, HKUnit.count(), 1)
        case .walkingAsymmetry: return (.walkingAsymmetryPercentage, HKUnit.percent(), 100)
        case .walkingDoubleSupport: return (.walkingDoubleSupportPercentage, HKUnit.percent(), 100)
        case .walkingSteadiness: return (.appleWalkingSteadiness, HKUnit.percent(), 100)
        case .stairAscentSpeed: return (.stairAscentSpeed, HKUnit.meter().unitDivided(by: .second()), 1)
        case .stairDescentSpeed: return (.stairDescentSpeed, HKUnit.meter().unitDivided(by: .second()), 1)
        case .sixMinuteWalkDistance: return (.sixMinuteWalkTestDistance, HKUnit.meter(), 1)
        case .height: return (.height, HKUnit.meter(), 100)
        case .leanBodyMass: return (.leanBodyMass, HKUnit.gramUnit(with: .kilo), 1)
        case .waistCircumference: return (.waistCircumference, HKUnit.meter(), 100)
        case .dietaryEnergy: return (.dietaryEnergyConsumed, HKUnit.kilocalorie(), 1)
        case .dietaryWater: return (.dietaryWater, HKUnit.literUnit(with: .milli), 1)
        case .dietaryProtein: return (.dietaryProtein, HKUnit.gram(), 1)
        case .dietaryCarbohydrates: return (.dietaryCarbohydrates, HKUnit.gram(), 1)
        case .dietaryFat: return (.dietaryFatTotal, HKUnit.gram(), 1)
        case .dietaryFiber: return (.dietaryFiber, HKUnit.gram(), 1)
        case .dietarySugar: return (.dietarySugar, HKUnit.gram(), 1)
        case .dietarySodium: return (.dietarySodium, HKUnit.gramUnit(with: .milli), 1)
        case .dietaryCaffeine: return (.dietaryCaffeine, HKUnit.gramUnit(with: .milli), 1)
        case .dietaryPotassium: return (.dietaryPotassium, HKUnit.gramUnit(with: .milli), 1)
        case .dietaryIron: return (.dietaryIron, HKUnit.gramUnit(with: .milli), 1)
        case .dietaryCalcium: return (.dietaryCalcium, HKUnit.gramUnit(with: .milli), 1)
        case .dietaryVitaminD: return (.dietaryVitaminD, HKUnit.gramUnit(with: .micro), 1)
        case .environmentalAudioExposure: return (.environmentalAudioExposure, HKUnit.decibelAWeightedSoundPressureLevel(), 1)
        case .headphoneAudioExposure: return (.headphoneAudioExposure, HKUnit.decibelAWeightedSoundPressureLevel(), 1)
        case .bloodGlucose: return (.bloodGlucose, HKUnit(from: "mg/dL"), 1)
        case .insulinDelivery: return (.insulinDelivery, HKUnit.internationalUnit(), 1)
        case .numberOfTimesFallen: return (.numberOfTimesFallen, HKUnit.count(), 1)
        case .inhalerUsage: return (.inhalerUsage, HKUnit.count(), 1)
        case .forcedExpiratoryVolume1: return (.forcedExpiratoryVolume1, HKUnit.liter(), 1)
        case .forcedVitalCapacity: return (.forcedVitalCapacity, HKUnit.liter(), 1)
        case .peakExpiratoryFlowRate: return (.peakExpiratoryFlowRate, HKUnit.liter().unitDivided(by: .minute()), 1)
        case .peripheralPerfusionIndex: return (.peripheralPerfusionIndex, HKUnit.percent(), 100)
        case .atrialFibrillationBurden: return (.atrialFibrillationBurden, HKUnit.percent(), 100)
        }
    }

    var cumulative: Bool {
        switch self {
        case .steps, .activeEnergy, .basalEnergy, .exerciseMinutes, .standMinutes, .walkingRunningDistance, .cyclingDistance, .swimmingDistance, .flightsClimbed, .daylightMinutes, .swimmingStrokeCount, .dietaryEnergy, .dietaryWater, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat, .dietaryFiber, .dietarySugar, .dietarySodium, .dietaryCaffeine, .dietaryPotassium, .dietaryIron, .dietaryCalcium, .dietaryVitaminD, .insulinDelivery, .numberOfTimesFallen, .inhalerUsage: return true
        default: return false
        }
    }

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
        guard let value, value.isFinite, value >= 0 || self == .wristTemperature else { return "—" }
        let precision = switch self {
        case .sleepDuration, .sleepCore, .sleepDeep, .sleepREM, .sleepAwake,
             .vo2Max, .bodyMass, .bodyMassIndex, .bodyFatPercentage,
             .wristTemperature, .walkingSpeed, .runningStrideLength: 1
        case .runningVerticalOscillation, .walkingStepLength,
             .bodyTemperature, .basalBodyTemperature, .walkingRunningDistance, .cyclingDistance, .runningSpeed, .cyclingSpeed, .walkingAsymmetry, .walkingDoubleSupport, .walkingSteadiness, .stairAscentSpeed, .stairDescentSpeed, .leanBodyMass, .waistCircumference, .dietaryVitaminD, .environmentalAudioExposure, .headphoneAudioExposure, .bloodGlucose, .insulinDelivery, .forcedExpiratoryVolume1, .forcedVitalCapacity, .peakExpiratoryFlowRate, .peripheralPerfusionIndex, .atrialFibrillationBurden: 1
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
