import Foundation

/// Formats a `Date` as a bare `yyyy-MM-dd` for Postgres `date` columns.
///
/// Sending a full timestamp instead would let the server's timezone conversion
/// shift the day backwards — which is how a birth date silently changes the
/// user's age, and how a rollup rebuild starts on the wrong day.
enum ISODay {
    static func string(from date: Date, in calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Reads one back.
    ///
    /// Decoding a `date` column straight into a `Date` fails — the client's
    /// decoder expects a full ISO 8601 timestamp and a bare `1994-03-02` is
    /// not one. Parsed at noon, local, so no timezone shift can move it onto
    /// the day before, which for a birth date is a year of age at the boundary.
    static func date(from string: String, in calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12

        return calendar.date(from: components)
    }
}
