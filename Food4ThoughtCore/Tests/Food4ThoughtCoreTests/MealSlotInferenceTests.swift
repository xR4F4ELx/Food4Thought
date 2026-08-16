import Testing
@testable import Food4ThoughtCore

/// The centre + button has to pick a slot without asking. Getting this wrong
/// costs a tap on every single log, which is the whole budget.
@Suite("Meal slot inference")
struct MealSlotInferenceTests {

    private let threeMeals = MealSchedule.Preset.threeMeals.schedule

    @Test("mid-morning, past breakfast's grace, defaults to lunch")
    func midMorningPicksLunch() {
        let slot = threeMeals.slot(at: TimeOfDay(hour: 10, minute: 11))
        #expect(slot?.key == "lunch")
    }

    @Test("just after a meal's typical time it stays on that meal")
    func withinGraceStaysOnTheSlot() {
        // Logging lunch at 13:15 is logging lunch, not getting ahead to a snack.
        let slot = threeMeals.slot(at: TimeOfDay(hour: 13, minute: 15))
        #expect(slot?.key == "lunch")
    }

    @Test("before the first meal it picks the first meal")
    func earlyMorningPicksBreakfast() {
        let slot = threeMeals.slot(at: TimeOfDay(hour: 6, minute: 30))
        #expect(slot?.key == "breakfast")
    }

    @Test("late at night it stays on the last meal rather than rolling to tomorrow")
    func lateNightStaysOnTheLastSlot() {
        let slot = threeMeals.slot(at: TimeOfDay(hour: 23, minute: 40))
        #expect(slot?.key == "dinner")
    }

    @Test("a one-meal-a-day schedule always picks its single slot")
    func omadAlwaysPicksItsOneSlot() {
        let omad = MealSchedule.Preset.oneMealADay.schedule

        #expect(omad.slot(at: TimeOfDay(hour: 7, minute: 0))?.key == "meal")
        #expect(omad.slot(at: TimeOfDay(hour: 22, minute: 0))?.key == "meal")
    }

    @Test("an empty schedule has nothing to infer")
    func emptyScheduleInfersNothing() {
        #expect(MealSchedule(slots: []).slot(at: TimeOfDay(hour: 12, minute: 0)) == nil)
    }

    @Test("slots are considered in time order, not in stored order")
    func outOfOrderSlotsStillInferCorrectly() {
        let scrambled = MealSchedule(slots: [
            MealSlot(key: "dinner", label: "Dinner", typicalTime: TimeOfDay(hour: 19, minute: 0), expectedShare: 0.5),
            MealSlot(key: "breakfast", label: "Breakfast", typicalTime: TimeOfDay(hour: 8, minute: 0), expectedShare: 0.5)
        ])

        #expect(scrambled.slot(at: TimeOfDay(hour: 7, minute: 0))?.key == "breakfast")
        #expect(scrambled.slot(at: TimeOfDay(hour: 18, minute: 0))?.key == "dinner")
    }
}
