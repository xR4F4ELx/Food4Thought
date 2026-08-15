/// One question per screen, in the order they are asked.
enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case aboutYou
    case body
    case activity
    case goalDirection
    case pace
    case mealRhythm
    case plan

    static func < (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .aboutYou: "About you"
        case .body: "Your measurements"
        case .activity: "How active are you?"
        case .goalDirection: "What are you aiming for?"
        case .pace: "How fast?"
        case .mealRhythm: "When do you eat?"
        case .plan: "Your plan"
        }
    }

    /// The plan screen is the destination, not a question, so it sits outside
    /// the progress count.
    static var questionCount: Int { allCases.count - 1 }
}
