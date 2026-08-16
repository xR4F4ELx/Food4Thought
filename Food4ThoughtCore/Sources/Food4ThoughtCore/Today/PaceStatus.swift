import Foundation

/// Whether today's intake is tracking with the user's own meal rhythm.
///
/// The only place the app volunteers a judgement, so it is deliberately hard to
/// trip. It measures against `MealSchedule.expectedShareElapsed`, which counts
/// only meals whose grace period has already passed — so an OMAD user is never
/// told they are "behind" at noon for not having eaten a breakfast they do not
/// eat.
public struct PaceStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case behind
        case onPace
        case ahead
    }

    /// The band either side of expected that still counts as on pace, as a
    /// share of the whole day's target.
    ///
    /// A share of the *day* rather than of what is currently due, because the
    /// latter collapses to nothing in the morning: at 09:00 expected is a few
    /// hundred kcal, and a proportional band would call a large breakfast
    /// "ahead" every single day.
    public static let toleranceShareOfDay = 0.08

    public let consumedKcal: Int
    public let expectedKcal: Int
    public let state: State

    public init(
        consumedKcal: Double,
        target: Int,
        schedule: MealSchedule,
        time: TimeOfDay,
        graceMinutes: Int = MealSchedule.defaultGraceMinutes
    ) {
        let consumed = consumedKcal.rounded()
        self.consumedKcal = Int(consumed)

        // No target, or no rhythm to measure one against. An empty schedule is
        // not "0 kcal expected" — it is no expectation at all, and reporting
        // "ahead" off the back of it would be a judgement with nothing behind
        // it. Early morning against a real schedule is a different thing and
        // does fall through: 800 kcal before breakfast genuinely is ahead.
        guard target > 0, !schedule.slots.isEmpty else {
            expectedKcal = 0
            state = .onPace
            return
        }

        let share = schedule.expectedShareElapsed(at: time, graceMinutes: graceMinutes)
        let expected = share * Double(target)
        expectedKcal = Int(expected.rounded())

        let tolerance = Double(target) * Self.toleranceShareOfDay
        let drift = consumed - expected

        if drift > tolerance {
            state = .ahead
        } else if drift < -tolerance {
            state = .behind
        } else {
            state = .onPace
        }
    }

    /// Plain and factual. Nothing here congratulates or scolds — "behind" is a
    /// position on a clock, not a verdict on the person.
    public var label: String {
        switch state {
        case .behind: "Behind pace"
        case .onPace: "On pace"
        case .ahead: "Ahead of pace"
        }
    }
}
