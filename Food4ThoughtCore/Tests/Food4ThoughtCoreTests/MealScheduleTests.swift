import Foundation
import Testing
@testable import Food4ThoughtCore

@Suite("Meal schedule presets")
struct MealSchedulePresetTests {
    @Test("every preset's shares sum to 1.0", arguments: MealSchedule.Preset.allCases)
    func sharesSumToOne(preset: MealSchedule.Preset) {
        let total = preset.schedule.slots.reduce(0) { $0 + $1.expectedShare }
        #expect(abs(total - 1.0) < 0.0001, "\(preset) sums to \(total)")
    }

    @Test("every preset's slots are ordered by time", arguments: MealSchedule.Preset.allCases)
    func slotsAreChronological(preset: MealSchedule.Preset) {
        let minutes = preset.schedule.slots.map(\.typicalTime.minutesSinceMidnight)
        #expect(minutes == minutes.sorted())
    }

    @Test("every preset uses unique slot keys", arguments: MealSchedule.Preset.allCases)
    func keysAreUnique(preset: MealSchedule.Preset) {
        let keys = preset.schedule.slots.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("one meal a day is a single slot carrying the whole day's intake")
    func oneMealADay() {
        let slots = MealSchedule.Preset.oneMealADay.schedule.slots
        #expect(slots.count == 1)
        #expect(slots[0].expectedShare == 1.0)
    }

    @Test("no-breakfast has no slot before 11:00")
    func noBreakfastSkipsMorning() {
        let earliest = MealSchedule.Preset.noBreakfast.schedule.slots
            .map(\.typicalTime.minutesSinceMidnight)
            .min()
        #expect(earliest ?? 0 >= 11 * 60)
    }

    @Test("16:8 confines every slot to an eight-hour window")
    func timeRestrictedWindowIsEightHours() {
        let minutes = MealSchedule.Preset.timeRestricted16_8.schedule.slots
            .map(\.typicalTime.minutesSinceMidnight)
        let span = (minutes.max() ?? 0) - (minutes.min() ?? 0)
        #expect(span <= 8 * 60)
    }
}

@Suite("Meal schedule behaviour")
struct MealScheduleBehaviourTests {
    @Test("expected share elapsed accumulates only slots whose time has passed")
    func expectedShareElapsed() {
        let schedule = MealSchedule.Preset.threeMeals.schedule
        // Before the first meal nothing is expected yet.
        #expect(schedule.expectedShareElapsed(at: TimeOfDay(hour: 6, minute: 0)) == 0)
        // After the last meal the full day is expected.
        let endOfDay = schedule.expectedShareElapsed(at: TimeOfDay(hour: 23, minute: 59))
        #expect(abs(endOfDay - 1.0) < 0.0001)
    }

    @Test("a one-meal-a-day user expects nothing before their single meal")
    func omadExpectsNothingEarly() {
        let schedule = MealSchedule.Preset.oneMealADay.schedule
        #expect(schedule.expectedShareElapsed(at: TimeOfDay(hour: 17, minute: 0)) == 0)
    }

    @Test("a slot counts as elapsed only after its grace period")
    func gracePeriodDelaysExpectation() {
        let lunch = MealSlot(key: "lunch", label: "Lunch", typicalTime: TimeOfDay(hour: 12, minute: 30), expectedShare: 1.0)
        let schedule = MealSchedule(slots: [lunch])
        // Default grace is 60 minutes, so 13:00 is still within it.
        #expect(schedule.expectedShareElapsed(at: TimeOfDay(hour: 13, minute: 0)) == 0)
        #expect(schedule.expectedShareElapsed(at: TimeOfDay(hour: 13, minute: 31)) == 1.0)
    }

    @Test("normalising rescales arbitrary weights to sum to 1.0")
    func normalisation() {
        let schedule = MealSchedule(slots: [
            MealSlot(key: "a", label: "A", typicalTime: TimeOfDay(hour: 9, minute: 0), expectedShare: 3),
            MealSlot(key: "b", label: "B", typicalTime: TimeOfDay(hour: 18, minute: 0), expectedShare: 1)
        ]).normalised()

        #expect(abs(schedule.slots[0].expectedShare - 0.75) < 0.0001)
        #expect(abs(schedule.slots[1].expectedShare - 0.25) < 0.0001)
    }

    @Test("normalising a schedule with no slots does not divide by zero")
    func normalisingEmptyScheduleIsSafe() {
        #expect(MealSchedule(slots: []).normalised().slots.isEmpty)
    }
}

@Suite("Meal schedule persistence")
struct MealSchedulePersistenceTests {
    @Test("round-trips through the jsonb column shape")
    func codableRoundTrip() throws {
        let original = MealSchedule.Preset.noBreakfast.schedule
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealSchedule.self, from: data)
        #expect(decoded == original)
    }

    @Test("encodes snake_case keys and HH:mm times matching the Postgres column")
    func wireFormat() throws {
        let schedule = MealSchedule(slots: [
            MealSlot(key: "lunch", label: "Lunch", typicalTime: TimeOfDay(hour: 12, minute: 30), expectedShare: 1.0)
        ])
        let json = String(data: try JSONEncoder().encode(schedule), encoding: .utf8) ?? ""

        #expect(json.contains("\"typical_time\""))
        #expect(json.contains("\"12:30\""))
        #expect(json.contains("\"expected_share\""))
    }
}
