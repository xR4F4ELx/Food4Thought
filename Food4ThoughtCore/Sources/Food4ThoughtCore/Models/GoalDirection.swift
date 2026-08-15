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
}
