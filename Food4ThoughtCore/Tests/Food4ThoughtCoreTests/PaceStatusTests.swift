import Testing
@testable import Food4ThoughtCore

/// The pace pill. It is the one place the app volunteers a judgement, so it has
/// to be both correct and quiet — a false "ahead" at 11am is a lie that makes
/// someone skip lunch.
@Suite("Pace status")
struct PaceStatusTests {

    private let threeMeals = MealSchedule.Preset.threeMeals.schedule
    private let target = 2000

    private func pace(consumed: Double, at time: TimeOfDay) -> PaceStatus {
        PaceStatus(
            consumedKcal: consumed,
            target: target,
            schedule: threeMeals,
            time: time
        )
    }

    @Test("before any meal's grace has elapsed, nothing is expected yet")
    func earlyMorningExpectsNothing() {
        // 06:30 is before breakfast, so there is no pace to be off.
        let status = pace(consumed: 0, at: TimeOfDay(hour: 6, minute: 30))

        #expect(status.expectedKcal == 0)
        #expect(status.state == .onPace)
    }

    @Test("eating close to the expected share reads as on pace")
    func withinToleranceIsOnPace() {
        // Past breakfast and lunch's grace: those two slots' shares are due.
        let elapsed = threeMeals.expectedShareElapsed(at: TimeOfDay(hour: 15, minute: 0))
        let expected = elapsed * Double(target)

        let status = pace(consumed: expected, at: TimeOfDay(hour: 15, minute: 0))
        #expect(status.state == .onPace)
    }

    @Test("well past the expected share reads as ahead")
    func aheadOfPace() {
        let elapsed = threeMeals.expectedShareElapsed(at: TimeOfDay(hour: 15, minute: 0))
        let expected = elapsed * Double(target)

        let status = pace(consumed: expected + 400, at: TimeOfDay(hour: 15, minute: 0))
        #expect(status.state == .ahead)
    }

    @Test("well under the expected share reads as behind")
    func behindPace() {
        let elapsed = threeMeals.expectedShareElapsed(at: TimeOfDay(hour: 15, minute: 0))
        let expected = elapsed * Double(target)

        let status = pace(consumed: expected - 400, at: TimeOfDay(hour: 15, minute: 0))
        #expect(status.state == .behind)
    }

    @Test("the tolerance band is a share of the day, not a share of what is due")
    func toleranceIsAbsolute() {
        // Scaling the band to the expected figure makes it vanish at 08:00,
        // where expected is near zero and every logged breakfast reads "ahead".
        let morning = TimeOfDay(hour: 10, minute: 30)
        let expected = threeMeals.expectedShareElapsed(at: morning) * Double(target)

        // A 100 kcal coffee over a barely-started day is not "ahead".
        let status = pace(consumed: expected + 100, at: morning)
        #expect(status.state == .onPace)
    }

    @Test("an empty schedule falls back to on pace rather than dividing by nothing")
    func emptyScheduleIsSafe() {
        let status = PaceStatus(
            consumedKcal: 800,
            target: target,
            schedule: MealSchedule(slots: []),
            time: TimeOfDay(hour: 15, minute: 0)
        )

        #expect(status.expectedKcal == 0)
        #expect(status.state == .onPace)
    }

    @Test("a zero target has no pace to measure")
    func zeroTargetIsSafe() {
        let status = PaceStatus(
            consumedKcal: 0,
            target: 0,
            schedule: threeMeals,
            time: TimeOfDay(hour: 15, minute: 0)
        )

        #expect(status.state == .onPace)
    }

    @Test("consumed kcal is reported back rounded, for the pill's own caption")
    func reportsConsumed() {
        // The pill reads "● On pace · 1,180 eaten".
        let status = pace(consumed: 1180.4, at: TimeOfDay(hour: 15, minute: 0))
        #expect(status.consumedKcal == 1180)
    }
}
