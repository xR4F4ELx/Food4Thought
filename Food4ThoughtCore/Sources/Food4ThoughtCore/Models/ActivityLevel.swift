public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
    case sedentary
    case lightlyActive = "lightly_active"
    case moderatelyActive = "moderately_active"
    case veryActive = "very_active"
    case extremelyActive = "extremely_active"

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .lightlyActive: 1.375
        case .moderatelyActive: 1.55
        case .veryActive: 1.725
        case .extremelyActive: 1.9
        }
    }
}
