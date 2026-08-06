import Foundation

/// A recurring wall-clock time with no date attached — encoded as "HH:mm".
public struct TimeOfDay: Equatable, Comparable, Codable, Sendable {
    public let hour: Int
    public let minute: Int

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(minutesSinceMidnight: Int) {
        self.init(hour: minutesSinceMidnight / 60, minute: minutesSinceMidnight % 60)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Expected HH:mm, got \(raw)")
            )
        }
        self.init(hour: hour, minute: minute)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%02d:%02d", hour, minute))
    }
}
