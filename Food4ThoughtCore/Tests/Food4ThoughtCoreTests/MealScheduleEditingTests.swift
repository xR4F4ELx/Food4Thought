import Foundation
import Testing
@testable import Food4ThoughtCore

/// Adding and removing meals, and the one-day slot.
///
/// A schedule chosen once during onboarding is wrong the first time someone
/// eats supper. These are the edits that let it change without re-running the
/// questionnaire.
@Suite("Meal schedule editing")
struct MealScheduleEditingTests {

    private let threeMeals = MealSchedule.Preset.threeMeals.schedule

    private func shares(_ schedule: MealSchedule) -> Double {
        schedule.slots.reduce(0) { $0 + $1.expectedShare }
    }

    // MARK: - Adding

    @Test("a new meal joins the schedule and the shares still sum to one")
    func addingKeepsSharesNormalised() {
        // expectedShare drives the pace pill, and a schedule summing to 1.15
        // would report someone behind all day for eating exactly their target.
        let updated = threeMeals.addingSlot(label: "Supper", typicalTime: TimeOfDay(hour: 21, minute: 30))

        #expect(updated.slots.count == 5)
        #expect(abs(shares(updated) - 1.0) < 0.0001)
    }

    @Test("a new meal takes an average share rather than a share of nothing")
    func newSlotTakesAnAverageShare() {
        // Four equal meals stay equal. A zero share would make the pace pill
        // expect nothing at supper and read "ahead" the moment one is eaten.
        let equal = MealSchedule(slots: (1...3).map {
            MealSlot(key: "m\($0)", label: "Meal \($0)", typicalTime: TimeOfDay(hour: $0 * 5, minute: 0), expectedShare: 1.0 / 3)
        })

        let updated = equal.addingSlot(label: "Supper", typicalTime: TimeOfDay(hour: 21, minute: 0))

        for slot in updated.slots {
            #expect(abs(slot.expectedShare - 0.25) < 0.0001)
        }
    }

    @Test("the key is derived from the label and stays unique")
    func keysAreDerivedAndUnique() {
        // meal_key is free text on the entry, so a collision would silently
        // merge two different meals into one row on Home.
        let once = threeMeals.addingSlot(label: "Late Snack!", typicalTime: TimeOfDay(hour: 22, minute: 0))
        #expect(once.slots.last?.key == "late_snack")

        let twice = once.addingSlot(label: "Late snack", typicalTime: TimeOfDay(hour: 23, minute: 0))
        #expect(twice.slots.last?.key == "late_snack_2")
        #expect(Set(twice.slots.map(\.key)).count == twice.slots.count)
    }

    @Test("a label with nothing usable in it still yields a key")
    func unusableLabelStillGetsAKey() {
        // Someone naming a meal "🍜" must not end up with an empty meal_key,
        // which would land every entry in a slot nothing can look up.
        let updated = threeMeals.addingSlot(label: "🍜", typicalTime: TimeOfDay(hour: 22, minute: 0))

        let key = updated.slots.last?.key ?? ""
        #expect(key.isEmpty == false)
        #expect(Set(updated.slots.map(\.key)).count == updated.slots.count)
    }

    // MARK: - The one-day slot

    @Test("a permanent meal has no expiry; an impromptu one expires that day")
    func lifetimeIsCarriedOnTheSlot() {
        let permanent = threeMeals.addingSlot(label: "Supper", typicalTime: TimeOfDay(hour: 21, minute: 0))
        #expect(permanent.slots.last?.expiresOn == nil)

        let today = threeMeals.addingSlot(
            label: "Birthday cake",
            typicalTime: TimeOfDay(hour: 15, minute: 0),
            expiresOn: "2026-08-17"
        )
        #expect(today.slots.last?.expiresOn == "2026-08-17")
    }

    @Test("an impromptu meal is in force on its own day and gone the next")
    func impromptuSlotExpires() {
        let schedule = threeMeals.addingSlot(
            label: "Birthday cake",
            typicalTime: TimeOfDay(hour: 15, minute: 0),
            expiresOn: "2026-08-17"
        )

        #expect(schedule.active(on: "2026-08-17").slots.count == 5)
        #expect(schedule.active(on: "2026-08-18").slots.count == 4)
        // Still there the morning it was added, not only after it.
        #expect(schedule.active(on: "2026-08-16").slots.count == 5)
    }

    @Test("dropping an expired meal renormalises what is left")
    func expiryRenormalises() {
        // Otherwise the day after a one-off, the shares sum to 0.75 and the
        // pace pill quietly expects three quarters of a day's food.
        let schedule = threeMeals.addingSlot(
            label: "Birthday cake",
            typicalTime: TimeOfDay(hour: 15, minute: 0),
            expiresOn: "2026-08-17"
        )

        #expect(abs(shares(schedule.active(on: "2026-08-18")) - 1.0) < 0.0001)
    }

    // MARK: - Removing

    @Test("removing a meal drops it and renormalises")
    func removingRenormalises() {
        let updated = threeMeals.removingSlot(key: "snack")

        #expect(updated.slots.map(\.key) == ["breakfast", "lunch", "dinner"])
        #expect(abs(shares(updated) - 1.0) < 0.0001)
    }

    @Test("the last meal cannot be removed")
    func lastSlotIsProtected() {
        // An empty schedule has no slot to log to, and mealSchedule() throws on
        // one — so this would lock the user out of logging entirely.
        let single = MealSchedule(slots: [
            MealSlot(key: "meal", label: "Meal", typicalTime: TimeOfDay(hour: 18, minute: 0), expectedShare: 1)
        ])

        #expect(single.canRemoveSlot == false)
        #expect(single.removingSlot(key: "meal").slots.count == 1)

        #expect(threeMeals.canRemoveSlot)
    }

    @Test("removing a key that isn't there changes nothing")
    func removingUnknownKeyIsANoOp() {
        let updated = threeMeals.removingSlot(key: "second_breakfast")
        #expect(updated == threeMeals)
    }

    // MARK: - Persistence

    @Test("the expiry survives the jsonb round trip, and old rows still decode")
    func encodingRoundTrip() throws {
        // profiles.meal_schedule is plain jsonb with no shape constraint, so
        // the new field needs no migration — but every schedule already stored
        // is missing it and has to keep decoding.
        let schedule = threeMeals.addingSlot(
            label: "Birthday cake",
            typicalTime: TimeOfDay(hour: 15, minute: 0),
            expiresOn: "2026-08-17"
        )

        let encoded = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(MealSchedule.self, from: encoded)
        #expect(decoded == schedule)

        let legacy = Data("""
        [{"key":"lunch","label":"Lunch","typical_time":"12:30","expected_share":1.0}]
        """.utf8)
        let old = try JSONDecoder().decode(MealSchedule.self, from: legacy)
        #expect(old.slots.first?.expiresOn == nil)
        #expect(old.slots.first?.label == "Lunch")
    }

    @Test("a permanent slot writes no expiry key at all")
    func permanentSlotOmitsTheKey() throws {
        let encoded = try JSONEncoder().encode(threeMeals)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("expires_on") == false)
    }

    // MARK: - Interaction with the rest of the model

    @Test("an impromptu meal takes part in slot inference on its day")
    func impromptuSlotIsInferable() {
        // The centre + button has to be able to land in it, or the meal exists
        // on Home but nothing can be logged to it without picking manually.
        let schedule = threeMeals
            .addingSlot(label: "Supper", typicalTime: TimeOfDay(hour: 22, minute: 0), expiresOn: "2026-08-17")
            .active(on: "2026-08-17")

        #expect(schedule.slot(at: TimeOfDay(hour: 21, minute: 45))?.key == "supper")
    }
}
