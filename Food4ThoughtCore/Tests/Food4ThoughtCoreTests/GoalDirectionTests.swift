import Foundation
import Testing
@testable import Food4ThoughtCore

@Suite("Goal direction and pace")
struct GoalDirectionTests {
    @Test("direction and pace together select the goal type", arguments: [
        (GoalDirection.lose, GoalPace.steady, GoalType.loseWeight),
        (.lose, .aggressive, .cut),
        (.gain, .steady, .leanBulk),
        (.gain, .aggressive, .gainWeight)
    ])
    func mapping(direction: GoalDirection, pace: GoalPace, expected: GoalType) {
        #expect(GoalType(direction: direction, pace: pace) == expected)
    }

    @Test("maintain ignores pace entirely", arguments: [GoalPace.steady, .aggressive])
    func maintainIgnoresPace(pace: GoalPace) {
        #expect(GoalType(direction: .maintain, pace: pace) == .maintain)
    }

    @Test("only lose and gain offer a pace choice")
    func paceIsOfferedForDirectionalGoalsOnly() {
        #expect(GoalDirection.lose.offersPaceChoice)
        #expect(GoalDirection.gain.offersPaceChoice)
        #expect(!GoalDirection.maintain.offersPaceChoice)
    }
}

@Suite("Projected weekly weight change")
struct ProjectedWeeklyChangeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func plan(weightKg: Double, heightCm: Double, age: Int, sex: BiologicalSex,
                      activity: ActivityLevel, goal: GoalType) -> GoalPlan {
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let birthDate = calendar.date(from: DateComponents(year: 2026 - age, month: 1, day: 1))!
        return TDEECalculator.plan(
            for: GoalInputs(
                birthDate: birthDate, sex: sex, heightCm: heightCm,
                weightKg: weightKg, activityLevel: activity, goal: goal
            ),
            asOf: asOf,
            calendar: calendar
        )
    }

    @Test("maintain projects no change")
    func maintainProjectsNothing() {
        let maintain = plan(weightKg: 80, heightCm: 180, age: 25, sex: .male,
                            activity: .moderatelyActive, goal: .maintain)
        #expect(abs(maintain.projectedWeeklyWeightChangeKg) < 0.01)
    }

    @Test("a deficit projects a loss and a surplus projects a gain")
    func directionOfChange() {
        let cut = plan(weightKg: 80, heightCm: 180, age: 25, sex: .male,
                       activity: .moderatelyActive, goal: .cut)
        let bulk = plan(weightKg: 80, heightCm: 180, age: 25, sex: .male,
                        activity: .moderatelyActive, goal: .leanBulk)

        #expect(cut.projectedWeeklyWeightChangeKg < 0)
        #expect(bulk.projectedWeeklyWeightChangeKg > 0)
    }

    @Test("the projection is derived from the clamped target, not the goal multiplier")
    func derivedFromClampedTarget() {
        // 25yo female, 50kg, 155cm, sedentary. A 20% cut lands under the 1200
        // kcal floor, so the real deficit is far smaller than 20% implies.
        let aggressive = plan(weightKg: 50, heightCm: 155, age: 25, sex: .female,
                              activity: .sedentary, goal: .cut)
        let steady = plan(weightKg: 50, heightCm: 155, age: 25, sex: .female,
                          activity: .sedentary, goal: .loseWeight)

        // Reading the multiplier alone would promise a meaningfully faster loss;
        // once the floor binds the two paces are near-identical.
        #expect(abs(aggressive.projectedWeeklyWeightChangeKg
                    - steady.projectedWeeklyWeightChangeKg) < 0.05)
    }
}
