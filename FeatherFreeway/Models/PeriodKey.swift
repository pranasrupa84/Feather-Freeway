import Foundation

/// Calendar keys for things that reset daily (errands).
enum PeriodKey {
    /// `2026-10-26`
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// ISO week such as `2026-W44`.
    static func week(_ date: Date, calendar: Calendar = .current) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    /// Start of the next ISO week, for countdowns.
    static func nextWeekStart(after date: Date, calendar: Calendar = .current) -> Date {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let start = iso.dateInterval(of: .weekOfYear, for: date)?.end
        return start ?? date.addingTimeInterval(7 * 86_400)
    }

    /// A stable 64-bit seed from a key string (FNV-1a).
    static func seed(_ key: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        return hash
    }
}
