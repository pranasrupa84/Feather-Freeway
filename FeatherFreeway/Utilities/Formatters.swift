import Foundation

/// Formatting helpers for numbers, distances and dates shown in the interface.
enum Formatters {
    static func integer(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    /// Distance in metres such as `1,240 m`.
    static func meters(_ value: Int) -> String {
        "\(integer(value)) m"
    }

    /// Seconds with one decimal for power-up timers, e.g. `4.5s`.
    static func seconds(_ value: Double) -> String {
        String(format: "%.0fs", max(0, value.rounded(.up)))
    }

    static func tripDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "en_US")))
    }

    static func ticketDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).year().locale(Locale(identifier: "en_US")))
    }

    /// Hours and minutes until the errands refresh.
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%dh %02dm", total / 3600, (total % 3600) / 60)
    }
}
