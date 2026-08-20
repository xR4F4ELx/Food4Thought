import Foundation

/// How a day's macros divide against each other, as shares of the energy they
/// carry rather than of their weight.
///
/// Grams are the wrong denominator for "how much of my day was fat": a gram of
/// fat carries a bit over twice the energy of a gram of carbohydrate, so a day
/// that is 30% fat by weight is closer to 50% fat by calories. Every target in
/// the app is set as an energy split, so this reads in the same terms.
public struct MacroSplit: Equatable, Sendable {

    public static let kcalPerGramProtein = 4.0
    public static let kcalPerGramCarbs = 4.0
    public static let kcalPerGramFat = 9.0

    /// Fractions of the macro energy, summing to 1.
    public let protein: Double
    public let carbs: Double
    public let fat: Double

    /// Nil for a day with nothing logged — a split of nothing is not zero
    /// percent of each, it is no answer at all, and drawing it as an empty bar
    /// would imply the day was recorded and empty.
    public init?(proteinGrams: Double, carbsGrams: Double, fatGrams: Double) {
        let proteinKcal = max(proteinGrams, 0) * Self.kcalPerGramProtein
        let carbsKcal = max(carbsGrams, 0) * Self.kcalPerGramCarbs
        let fatKcal = max(fatGrams, 0) * Self.kcalPerGramFat
        let total = proteinKcal + carbsKcal + fatKcal

        guard total > 0 else { return nil }

        // Normalised across the three rather than against the day's logged
        // calories: those two disagree whenever something was quick-added as
        // calories only, and a split that does not add up to 100% is a chart
        // with a gap nobody can explain.
        protein = proteinKcal / total
        carbs = carbsKcal / total
        fat = fatKcal / total
    }

    /// Percentages, rounded for display and adjusted so they still read as 100.
    ///
    /// Rounding each independently gives 33/33/33 for a third each, and a
    /// reader who adds them up finds 99 and wonders what is missing. The
    /// largest share absorbs the difference, where one point is least visible.
    public var roundedPercentages: (protein: Int, carbs: Int, fat: Int) {
        var values = [
            (name: "protein", value: Int((protein * 100).rounded())),
            (name: "carbs", value: Int((carbs * 100).rounded())),
            (name: "fat", value: Int((fat * 100).rounded()))
        ]

        let drift = 100 - values.reduce(0) { $0 + $1.value }
        if drift != 0, let largest = values.indices.max(by: { values[$0].value < values[$1].value }) {
            values[largest].value += drift
        }

        return (
            protein: values.first { $0.name == "protein" }?.value ?? 0,
            carbs: values.first { $0.name == "carbs" }?.value ?? 0,
            fat: values.first { $0.name == "fat" }?.value ?? 0
        )
    }
}
