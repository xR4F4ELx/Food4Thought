import Foundation
import Testing
@testable import Food4ThoughtCore

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

private func inputs(
    birthDate: Date = date(2001, 1, 1),
    sex: BiologicalSex = .male,
    heightCm: Double = 180,
    weightKg: Double = 80,
    activityLevel: ActivityLevel = .moderatelyActive,
    goal: GoalType = .maintain
) -> GoalInputs {
    GoalInputs(
        birthDate: birthDate,
        sex: sex,
        heightCm: heightCm,
        weightKg: weightKg,
        activityLevel: activityLevel,
        goal: goal
    )
}

@Suite("Goal plan")
struct GoalPlanTests {
    private let asOf = date(2026, 1, 1)

    @Test("derives every stored figure for the reference 25yo male, 80kg, 180cm")
    func referencePlan() {
        // Arrange / Act
        let plan = TDEECalculator.plan(for: inputs(), asOf: asOf, calendar: utcCalendar)

        // Assert: matches the individual calculators' own reference values.
        #expect(abs(plan.basalMetabolicRate - 1805) < 0.01)
        #expect(abs(plan.totalDailyEnergyExpenditure - 2797.75) < 0.01)
        #expect(abs(plan.bodyMassIndex - 24.6913) < 0.01)
        #expect(plan.dailyCalorieTarget == 2798)
    }

    @Test("macros reconcile exactly to the integer calorie target that gets stored")
    func macrosReconcileToStoredTarget() {
        // The complete_onboarding RPC rejects a submission whose macros do not
        // add up to its calorie target, so the rounding has to happen before
        // the macro split, not after.
        let plan = TDEECalculator.plan(for: inputs(), asOf: asOf, calendar: utcCalendar)

        let macroCalories = plan.macros.proteinGrams * 4
            + plan.macros.carbsGrams * 4
            + plan.macros.fatGrams * 9

        #expect(abs(macroCalories - Double(plan.dailyCalorieTarget)) < 0.01)
    }

    @Test("macros reconcile even where the protein and fat floors collide")
    func macrosReconcileAtExtremeWeight() {
        // 50yo male, 200kg, 170cm, sedentary on a cut — the case where the
        // per-kilogram floors together demand more than the calorie target.
        let plan = TDEECalculator.plan(
            for: inputs(
                birthDate: date(1976, 1, 1),
                heightCm: 170,
                weightKg: 200,
                activityLevel: .sedentary,
                goal: .cut
            ),
            asOf: asOf,
            calendar: utcCalendar
        )

        let macroCalories = plan.macros.proteinGrams * 4
            + plan.macros.carbsGrams * 4
            + plan.macros.fatGrams * 9

        #expect(macroCalories <= Double(plan.dailyCalorieTarget) + 0.01)
    }

    @Test("age counts a birthday that has already passed this year")
    func ageAfterBirthday() {
        // Born 2001-01-01, asOf 2026-01-01: exactly 25.
        let plan = TDEECalculator.plan(for: inputs(), asOf: asOf, calendar: utcCalendar)
        // BMR at 25 is 1805; a year older would be 1800.
        #expect(abs(plan.basalMetabolicRate - 1805) < 0.01)
    }

    @Test("age does not count a birthday still to come this year")
    func ageBeforeBirthday() {
        // Born 2001-12-31, asOf 2026-01-01: still 24, not 25.
        let plan = TDEECalculator.plan(
            for: inputs(birthDate: date(2001, 12, 31)),
            asOf: asOf,
            calendar: utcCalendar
        )
        // 800 + 1125 - 120 + 5
        #expect(abs(plan.basalMetabolicRate - 1810) < 0.01)
    }
}
