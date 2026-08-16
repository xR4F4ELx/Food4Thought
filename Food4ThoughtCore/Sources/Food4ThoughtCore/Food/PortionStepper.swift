import Foundation

/// Drops the decimal point when there isn't one to show: "320", not "320.0".
enum PortionFormatter {
    static func string(from value: Double) -> String {
        value.rounded() == value
            ? String(Int(value))
            : String(format: "%g", (value * 100).rounded() / 100)
    }
}

/// What the − / value / + control is counting.
public enum PortionUnit: Equatable, Sendable {
    /// Grams. Anything the user might weigh, and everything USDA quotes by mass.
    case grams
    /// Whole and half portions of a named serving — "1.5 bowls".
    case servings(label: String)
}

/// The quantity half of the 2d sheet: one immutable value, stepped into new
/// ones, that knows both what to display and what to multiply the food's
/// nutrients by.
///
/// The default matters more than the stepping does. Opening on the serving the
/// user actually logs is what makes the common case zero taps; the steppers are
/// the opt-in precision behind it.
public struct PortionStepper: Equatable, Sendable {
    public static let gramStep: Double = 10
    public static let servingStep: Double = 0.5

    public let food: FoodItem
    public let unit: PortionUnit

    /// In grams or in servings, matching `unit`.
    public let value: Double

    public init(food: FoodItem, usualServings: Double?) {
        // A serving with no size can't be stepped by weight and can't scale
        // anything, so it falls back to the unit portion.
        let servings = usualServings.map { max(0, $0) } ?? 1
        let unit: PortionUnit = food.serving.isMass && food.serving.amount > 0
            ? .grams
            : .servings(label: food.serving.unit)

        // The opening value is floored but never snapped to the step grid: a
        // banana's 118 g is the right default precisely because it is the
        // serving, and rounding it to 120 g would edit the user's own history
        // before they had touched anything.
        self.init(
            food: food,
            unit: unit,
            value: unit == .grams
                ? max(Self.gramStep, servings * food.serving.amount)
                : max(Self.servingStep, servings)
        )
    }

    private init(food: FoodItem, unit: PortionUnit, value: Double) {
        self.food = food
        self.unit = unit
        self.value = value
    }

    /// The multiplier to apply to `food.facts`.
    public var servings: Double {
        switch unit {
        case .grams: food.serving.amount > 0 ? value / food.serving.amount : 0
        case .servings: value
        }
    }

    public var facts: NutritionFacts { food.facts.scaled(by: servings) }

    public func incremented() -> PortionStepper {
        stepped(by: step)
    }

    public func decremented() -> PortionStepper {
        stepped(by: -step)
    }

    // MARK: - Display

    public var displayValue: String { PortionFormatter.string(from: value) }

    /// Pluralised, because "1 bowls" is the kind of detail that makes an app
    /// feel unfinished.
    public var displayUnit: String {
        switch unit {
        case .grams:
            "grams"
        case .servings(let label):
            value == 1 ? label : "\(label)s"
        }
    }

    // MARK: - Stepping

    private var step: Double {
        switch unit {
        case .grams: Self.gramStep
        case .servings: Self.servingStep
        }
    }

    private func stepped(by delta: Double) -> PortionStepper {
        let stepped = value + delta
        return PortionStepper(
            food: food,
            unit: unit,
            value: unit == .grams
                ? Self.clampedGrams(stepped)
                : Self.clampedServings(stepped)
        )
    }

    /// Stepping snaps to the grid, so a default of 118 g walks to 120, 130 …
    /// rather than carrying an odd remainder forever.
    ///
    /// `food_log_entries.quantity` carries a `> 0` check, so one step is the
    /// floor — the control never offers a quantity the database would refuse.
    private static func clampedGrams(_ value: Double) -> Double {
        max(gramStep, (value / gramStep).rounded() * gramStep)
    }

    private static func clampedServings(_ value: Double) -> Double {
        max(servingStep, (value / servingStep).rounded() * servingStep)
    }
}
