import Foundation

/// What the user typed into the weigh-in sheet, and whether it can be stored.
///
/// Units live here rather than in the view because the conversion is the part
/// that can be wrong: a pounds figure written to a kilograms column is a silent
/// error that only shows up as an impossible weight trend weeks later.
public struct WeighInDraft: Equatable, Sendable {

    public enum Units: String, CaseIterable, Identifiable, Sendable {
        case metric
        case imperial

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .metric: "kg"
            case .imperial: "lb"
            }
        }
    }

    /// The international pound, exactly.
    public static let kgPerPound = 0.45359237

    /// Wide enough to hold every adult and most children, narrow enough to
    /// catch the two typos that matter: a missed decimal point (7.4 for 74)
    /// and a doubled digit (744 for 74).
    public static let plausibleKg = 20.0...400.0

    public var amount: String
    public var units: Units

    public init(amount: String = "", units: Units = .metric) {
        self.amount = amount
        self.units = units
    }

    /// The weight in kilograms, or nil if the entry is not usable.
    public var validatedKg: Double? {
        guard problem == nil else { return nil }
        return kilograms
    }

    /// Why this cannot be saved yet, in words meant for the user. Nil when it
    /// can — an empty field is not an error, it is an unfinished one, so it
    /// reports the same "not yet" as a bad number without a scolding message.
    public var problem: String? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }

        guard let kilograms, kilograms > 0 else {
            return "Enter your weight as a number."
        }

        guard Self.plausibleKg.contains(kilograms) else {
            let low = Self.plausibleKg.lowerBound
            let high = Self.plausibleKg.upperBound
            return switch units {
            case .metric: "That looks off — enter a weight between \(Int(low)) and \(Int(high)) kg."
            case .imperial: "That looks off — enter a weight between \(Int(low / Self.kgPerPound)) and \(Int(high / Self.kgPerPound)) lb."
            }
        }

        return nil
    }

    private var kilograms: Double? {
        // A comma decimal separator is what half the world's keyboards offer,
        // and Double("74,3") is nil.
        let normalised = amount
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")

        guard let entered = Double(normalised) else { return nil }
        return units == .metric ? entered : entered * Self.kgPerPound
    }

    /// Re-writes the field so switching units converts what is there rather
    /// than reinterpreting it — 74 kg becomes 163 lb, not 74 lb.
    public func converted(to newUnits: Units) -> WeighInDraft {
        guard newUnits != units, let kilograms else {
            return WeighInDraft(amount: amount, units: newUnits)
        }

        let value = newUnits == .metric ? kilograms : kilograms / Self.kgPerPound
        return WeighInDraft(amount: Self.format(value), units: newUnits)
    }

    /// One decimal place: scales report one, and a stored 74.28 would render
    /// as a precision the user never claimed.
    public static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
