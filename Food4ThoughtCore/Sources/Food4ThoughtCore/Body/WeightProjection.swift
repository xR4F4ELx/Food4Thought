import Foundation

/// The line a plan predicts: where weight should be on a given day if the
/// calorie target is met.
///
/// It exists so progress can be read against something. A weight chart on its
/// own answers "what happened"; the question people actually have is "is this
/// working", and that needs the plan drawn next to the scale.
public struct WeightProjection: Equatable, Sendable {

    /// The conventional energy density of body tissue — about 7,700 kcal per
    /// kilogram, the metric form of the 3,500 kcal-per-pound rule.
    ///
    /// It is an approximation, and a known-imperfect one: early loss runs
    /// faster because glycogen carries water with it, and the deficit itself
    /// shrinks as body mass does. Good enough to draw an expectation against,
    /// which is why everything built on it is labelled an estimate.
    public static let kcalPerKg = 7_700.0

    /// Where the line starts: the first weight recorded under this plan.
    public let anchorDate: Date
    public let anchorKg: Double

    /// Target minus TDEE. Negative for a deficit, positive for a surplus, zero
    /// for maintenance — which draws a flat line, correctly.
    public let dailyKcalDelta: Double

    public init(anchorDate: Date, anchorKg: Double, dailyKcalDelta: Double) {
        self.anchorDate = anchorDate
        self.anchorKg = anchorKg
        self.dailyKcalDelta = dailyKcalDelta
    }

    public var dailyKgChange: Double {
        dailyKcalDelta / Self.kcalPerKg
    }

    /// Weekly change, which is the unit people actually think in.
    public var weeklyKgChange: Double {
        dailyKgChange * 7
    }

    public func expectedKg(on date: Date, calendar: Calendar = .current) -> Double {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchorDate),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        return anchorKg + dailyKgChange * Double(days)
    }
}

/// How an actual weight compares to the line.
public enum ProgressStanding: Equatable, Sendable {
    /// Moving faster towards the goal than planned.
    case ahead(kg: Double)
    case onTrack
    /// Moving slower than planned, or the wrong way.
    case behind(kg: Double)

    /// Daily weight swings of a kilogram are ordinary — water, salt, what is
    /// still in transit. A band narrower than the noise would call the same
    /// person ahead on Tuesday and behind on Wednesday, which is worse than
    /// saying nothing.
    public static let toleranceKg = 1.0

    /// Compares an actual weight against the plan on the same day.
    ///
    /// `goalIsLoss` decides which direction counts as ahead: 200 g under the
    /// line is progress when cutting and a shortfall when bulking.
    public init(actualKg: Double, expectedKg: Double, goalIsLoss: Bool) {
        let difference = actualKg - expectedKg

        guard abs(difference) > Self.toleranceKg else {
            self = .onTrack
            return
        }

        let isAhead = goalIsLoss ? difference < 0 : difference > 0
        self = isAhead ? .ahead(kg: abs(difference)) : .behind(kg: abs(difference))
    }
}
