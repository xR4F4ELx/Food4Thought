public enum GoalType: String, Codable, Sendable, CaseIterable {
    case loseWeight = "lose_weight"
    case cut
    case maintain
    case leanBulk = "lean_bulk"
    case gainWeight = "gain_weight"

    var calorieMultiplier: Double {
        switch self {
        case .loseWeight: 0.85
        case .cut: 0.80
        case .maintain: 1.0
        case .leanBulk: 1.10
        case .gainWeight: 1.15
        }
    }

    /// Protein rises as the deficit deepens to protect lean mass; a surplus
    /// carries more of the growth signal, so a bulk needs less.
    var proteinGramsPerKilogram: Double {
        switch self {
        case .cut: 2.2
        case .loseWeight: 2.0
        case .maintain: 1.8
        case .leanBulk, .gainWeight: 1.6
        }
    }
}
