import Foundation

/// A calendar date as the server keeps it, such as `2026-09-01`, turned into the `Date` a date
/// picker shows (midnight on that day, in the phone's time zone) and back.
nonisolated enum CalendarDay {
    static func date(from text: String?, calendar: Calendar = .current) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = calendar.timeZone
        guard components.isValidDate, let date = components.date else { return nil }
        return date
    }

    static func text(from date: Date?, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let day = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }
}
