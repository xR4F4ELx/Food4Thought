public struct MealSlot: Equatable, Codable, Sendable {
    public let key: String
    public let label: String
    public let typicalTime: TimeOfDay
    public let expectedShare: Double

    /// The last day this meal is in force, as `yyyy-MM-dd`. Nil for the normal
    /// case — a meal the user eats every day.
    ///
    /// Set for the impromptu one: a birthday cake, a work lunch, a supper that
    /// happened once. Those need a slot to be logged against, but writing them
    /// in permanently would leave an empty row on Home for the rest of the
    /// user's life.
    ///
    /// Optional, so every schedule already stored without it still decodes.
    /// `profiles.meal_schedule` is plain jsonb with no shape constraint, so
    /// carrying it costs no migration.
    public let expiresOn: String?

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case typicalTime = "typical_time"
        case expectedShare = "expected_share"
        case expiresOn = "expires_on"
    }

    public init(
        key: String,
        label: String,
        typicalTime: TimeOfDay,
        expectedShare: Double,
        expiresOn: String? = nil
    ) {
        self.key = key
        self.label = label
        self.typicalTime = typicalTime
        self.expectedShare = expectedShare
        self.expiresOn = expiresOn
    }
}

/// The meals a given user actually eats. Drives both the log-entry meal picker
/// and the nudge pace curve, so an OMAD or 16:8 user is never measured against
/// a three-meal assumption they don't follow.
public struct MealSchedule: Equatable, Codable, Sendable {
    /// Logging a meal late shouldn't immediately read as "behind".
    public static let defaultGraceMinutes = 60

    public let slots: [MealSlot]

    public init(slots: [MealSlot]) {
        self.slots = slots
    }

    public init(from decoder: any Decoder) throws {
        slots = try decoder.singleValueContainer().decode([MealSlot].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(slots)
    }

    /// Fraction of the day's intake expected by `time`, counting only meals
    /// whose typical time plus grace period has already passed.
    public func expectedShareElapsed(at time: TimeOfDay, graceMinutes: Int = defaultGraceMinutes) -> Double {
        slots
            .filter { time.minutesSinceMidnight > $0.typicalTime.minutesSinceMidnight + graceMinutes }
            .reduce(0) { $0 + $1.expectedShare }
    }

    /// Rescales shares to sum to 1.0 so a hand-edited schedule stays coherent.
    public func normalised() -> MealSchedule {
        let total = slots.reduce(0) { $0 + $1.expectedShare }
        guard total > 0 else { return self }

        return MealSchedule(slots: slots.map {
            MealSlot(
                key: $0.key,
                label: $0.label,
                typicalTime: $0.typicalTime,
                expectedShare: $0.expectedShare / total,
                // Carried, not defaulted. Rebuilding a slot here and letting
                // the expiry fall away would make every one-day meal permanent
                // the moment the schedule was rebalanced — which is on the same
                // call that creates it.
                expiresOn: $0.expiresOn
            )
        })
    }
}
