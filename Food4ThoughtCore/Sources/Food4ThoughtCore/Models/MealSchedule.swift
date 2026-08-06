public struct MealSlot: Equatable, Codable, Sendable {
    public let key: String
    public let label: String
    public let typicalTime: TimeOfDay
    public let expectedShare: Double

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case typicalTime = "typical_time"
        case expectedShare = "expected_share"
    }

    public init(key: String, label: String, typicalTime: TimeOfDay, expectedShare: Double) {
        self.key = key
        self.label = label
        self.typicalTime = typicalTime
        self.expectedShare = expectedShare
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
                expectedShare: $0.expectedShare / total
            )
        })
    }
}
