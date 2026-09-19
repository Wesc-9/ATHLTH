import Foundation

enum SignInMethod: String, Codable {
    case apple
    case email
}

enum HealthSex: String, CaseIterable, Identifiable, Codable {
    case female
    case male
    case other
    case preferNotToSay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

enum ATHLTHGoal: String, CaseIterable, Identifiable, Codable, Hashable {
    case strength
    case running
    case walking
    case endurance
    case recovery
    case mobility
    case bodyComposition
    case consistency
    case event
    case tracking
    case plans
    case social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength: return "Strength & muscle"
        case .running: return "Running"
        case .walking: return "Walking & daily movement"
        case .endurance: return "Fitness & endurance"
        case .recovery: return "Recovery & sleep"
        case .mobility: return "Mobility & flexibility"
        case .bodyComposition: return "Body composition"
        case .consistency: return "Build consistency"
        case .event: return "Train for an event"
        case .tracking: return "Track health & progress"
        case .plans: return "Follow training plans"
        case .social: return "Friends & challenges"
        }
    }

    var subtitle: String {
        switch self {
        case .strength: return "Build strength, muscle and gym progress."
        case .running: return "Improve pace, distance and running fitness."
        case .walking: return "Move more and stay active every day."
        case .endurance: return "Improve general conditioning and stamina."
        case .recovery: return "Use sleep and recovery signals to train smarter."
        case .mobility: return "Move better and improve flexibility and mobility."
        case .bodyComposition: return "Support body-composition goals through training and progress tracking."
        case .consistency: return "Create habits and keep a steady routine."
        case .event: return "Prepare for a race, challenge or goal date."
        case .tracking: return "Bring workouts and health trends into one place."
        case .plans: return "Use structured plans and calendars."
        case .social: return "Share, compare and train with other people."
        }
    }

    var systemImage: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .endurance: return "heart.circle.fill"
        case .recovery: return "moon.stars.fill"
        case .mobility: return "figure.flexibility"
        case .bodyComposition: return "scalemass.fill"
        case .consistency: return "calendar.badge.checkmark"
        case .event: return "flag.checkered"
        case .tracking: return "chart.xyaxis.line"
        case .plans: return "list.bullet.clipboard.fill"
        case .social: return "person.2.fill"
        }
    }
}

struct OnboardingProfileData: Codable, Hashable {
    var dateOfBirth: Date
    var healthSex: HealthSex
    var weightKilograms: Double
    var heightCentimeters: Double
    var goals: Set<ATHLTHGoal>
    var primaryGoal: ATHLTHGoal?
}

enum OnboardingStep: Int, CaseIterable {
    case account
    case username
    case personal
    case goals
    case connections
    case ready

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }
}
