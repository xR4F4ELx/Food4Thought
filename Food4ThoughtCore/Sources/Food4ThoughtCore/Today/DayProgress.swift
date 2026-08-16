import Foundation

/// The three macros, as something a ring can be built from generically.
public enum Macro: String, CaseIterable, Identifiable, Sendable {
    case protein
    case carbs
    case fat

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        }
    }
}

/// Today's intake measured against today's targets — every figure the Home
/// rings display.
///
/// Kept here rather than in the view so the arithmetic is testable without a
/// screen, and so the sign convention lives in exactly one place: `remaining`
/// is `target − consumed` and stays negative when the user is over. Clamping it
/// would erase the only thing 1e has to say.
public struct DayProgress: Equatable, Sendable {
    public let target: Int
    public let macroTargets: MacroTargets
    public let consumed: NutritionFacts

    public init(target: Int, macroTargets: MacroTargets, consumed: NutritionFacts) {
        self.target = target
        self.macroTargets = macroTargets
        self.consumed = consumed
    }

    // MARK: - Calories

    public var consumedKcal: Int { Int(consumed.calories.rounded()) }

    /// Signed. Positive is headroom, negative is the overage 1e puts in red.
    public var remainingKcal: Int { target - consumedKcal }

    public var isOverTarget: Bool { consumedKcal > target }

    /// 0…1. The ring stops at full when the target is passed — a stroke winding
    /// past 360° reads as less progress, not more, and the number already says
    /// how far over the day went.
    public var calorieFraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(consumedKcal) / Double(target))
    }

    // MARK: - Macros

    public func grams(of macro: Macro) -> Int {
        Int(consumedGrams(of: macro).rounded())
    }

    public func targetGrams(of macro: Macro) -> Int {
        Int(targetValue(of: macro).rounded())
    }

    public func fraction(of macro: Macro) -> Double {
        let target = targetValue(of: macro)
        guard target > 0 else { return 0 }
        return min(1, consumedGrams(of: macro) / target)
    }

    /// A macro with no target can never be over it. Flagging one would put a red
    /// ring on a number the user was never given.
    public func isOver(_ macro: Macro) -> Bool {
        let target = targetValue(of: macro)
        return target > 0 && consumedGrams(of: macro) > target
    }

    // MARK: - Helpers

    private func consumedGrams(of macro: Macro) -> Double {
        switch macro {
        case .protein: consumed.protein
        case .carbs: consumed.carbs
        case .fat: consumed.fat
        }
    }

    private func targetValue(of macro: Macro) -> Double {
        switch macro {
        case .protein: macroTargets.proteinGrams
        case .carbs: macroTargets.carbsGrams
        case .fat: macroTargets.fatGrams
        }
    }
}
