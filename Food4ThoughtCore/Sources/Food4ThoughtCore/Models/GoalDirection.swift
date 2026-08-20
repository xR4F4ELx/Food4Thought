/// The two questions a person can actually answer, which together pick a
/// `GoalType`. Nobody knows whether they want "lose weight" or "cut", but
/// everybody knows which way they want to go and how hard they want to push.
public enum GoalDirection: String, CaseIterable, Sendable {
    case lose
    case maintain
    case gain

    /// Maintain has no faster or slower version of itself.
    public var offersPaceChoice: Bool {
        self != .maintain
    }
}

public enum GoalPace: String, CaseIterable, Sendable {
    case steady
    case aggressive
}

extension GoalType {
    public init(direction: GoalDirection, pace: GoalPace) {
        switch (direction, pace) {
        case (.lose, .steady): self = .loseWeight
        case (.lose, .aggressive): self = .cut
        case (.maintain, _): self = .maintain
        case (.gain, .steady): self = .leanBulk
        case (.gain, .aggressive): self = .gainWeight
        }
    }

    /// Back to the two questions, so a stored goal can be reopened in the same
    /// terms it was chosen in. Editing a plan has to start from what the user
    /// actually picked, not from the internal name it was filed under.
    public var direction: GoalDirection {
        switch self {
        case .loseWeight, .cut: .lose
        case .maintain: .maintain
        case .leanBulk, .gainWeight: .gain
        }
    }

    /// Maintain has no pace of its own; `steady` is what the questionnaire
    /// carries for it, and round-tripping through it must not change the goal.
    public var pace: GoalPace {
        switch self {
        case .cut, .gainWeight: .aggressive
        case .loseWeight, .leanBulk, .maintain: .steady
        }
    }
}
