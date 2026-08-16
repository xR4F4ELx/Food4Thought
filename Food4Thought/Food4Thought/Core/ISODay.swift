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
}
