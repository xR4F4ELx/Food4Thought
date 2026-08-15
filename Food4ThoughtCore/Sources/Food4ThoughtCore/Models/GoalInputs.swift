import Foundation

/// Everything the calorie and macro math needs, and nothing else. Onboarding
/// collects these; a later goal edit re-submits them with one field changed.
public struct GoalInputs: Equatable, Sendable {
    /// Stored rather than an age so it never goes stale between sessions.
    public let birthDate: Date
    public let sex: BiologicalSex
    public let heightCm: Double
    public let weightKg: Double
    public let activityLevel: ActivityLevel
    public let goal: GoalType

    public init(
        birthDate: Date,
        sex: BiologicalSex,
        heightCm: Double,
        weightKg: Double,
        activityLevel: ActivityLevel,
        goal: GoalType
    ) {
        self.birthDate = birthDate
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.goal = goal
    }
}
