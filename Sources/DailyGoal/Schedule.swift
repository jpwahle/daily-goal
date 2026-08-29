import Foundation

/// When a goal is expected: which weekdays carry one, and — if you want it —
/// the stretch of those days it's live for.
///
/// Weekends start out off: a goal you can't act on isn't a goal, it's guilt.
/// The hours start out 4 a.m. → 4 a.m. — the app's own day, edge to edge — so
/// until someone narrows them nothing about the ring changes.
struct Schedule: Equatable {
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday) that carry a goal.
    var activeDays: Set<Int>
    /// Wall-clock minutes past midnight. An end at or before the start runs on
    /// into the next morning — night shifts are days too — and an end *equal*
    /// to the start is the whole day, which is how "no restriction" is said
    /// without a switch to say it with.
    var startMinutes: Int
    var endMinutes: Int

    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
    static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    /// The day the app already believed in: 4 a.m. to 4 a.m., Mon–Fri.
    static let dayStartMinutes = 4 * 60

    static let standard = Schedule(
        activeDays: weekdays,
        startMinutes: dayStartMinutes, endMinutes: dayStartMinutes)

    /// The full logical day, edge to edge. Any other pair of equal times is a
    /// window that simply runs until the day ends.
    var isAllDay: Bool {
        startMinutes == Self.dayStartMinutes && endMinutes == Self.dayStartMinutes
    }

    func isActive(weekday: Int) -> Bool { activeDays.contains(weekday) }

    // MARK: - The live window

    /// The stretch of the logical day starting at `dayStart` that the goal is
    /// live for: the configured hours, or the whole day when they're off.
    ///
    /// Hours resolve *inside* the logical day rather than on the calendar
    /// date, so an edge before the 4 a.m. flip (a 10 p.m. → 2 a.m. evening,
    /// say) lands on the following morning — still the same logical day — and
    /// the window never spills past the rollover. All of it steps through the
    /// calendar, so a DST shift moves the window with the wall clock.
    func window(inDayStarting dayStart: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86400)

        func firstOccurrence(ofMinutes minutes: Int) -> Date {
            var parts = calendar.dateComponents([.year, .month, .day], from: dayStart)
            parts.hour = minutes / 60
            parts.minute = minutes % 60
            guard var stamp = calendar.date(from: parts) else { return dayStart }
            if stamp < dayStart {
                stamp = calendar.date(byAdding: .day, value: 1, to: stamp)
                    ?? stamp.addingTimeInterval(86400)
            }
            return stamp
        }

        let from = firstOccurrence(ofMinutes: startMinutes)
        var to = firstOccurrence(ofMinutes: endMinutes)
        if to <= from {
            to = calendar.date(byAdding: .day, value: 1, to: to) ?? to.addingTimeInterval(86400)
        }
        return (min(from, dayEnd), min(to, dayEnd))
    }

    // MARK: - Labels

    /// "9 AM – 6 PM" in the user's own clock format.
    var hoursLabel: String {
        "\(Self.clockLabel(startMinutes)) – \(Self.clockLabel(endMinutes))"
    }

    /// A time of day the way this locale writes it: "9 AM" and "9:30 AM" on a
    /// 12-hour clock, "09:00" and "09:30" on a 24-hour one — where the bare
    /// hour would read as a lone number, the minutes stay.
    static func clockLabel(_ minutes: Int) -> String {
        let calendar = Calendar.current
        var parts = DateComponents()
        parts.year = 2001
        parts.month = 1
        parts.day = 1
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        guard let date = calendar.date(from: parts) else { return "" }
        let bare = minutes % 60 == 0 && twelveHourClock
        return (bare ? hourFormatter : hourMinuteFormatter).string(from: date)
    }

    private static let twelveHourClock: Bool =
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")

    private static let hourFormatter = formatter(template: "j")
    private static let hourMinuteFormatter = formatter(template: "jmm")

    private static func formatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: .current)
        return formatter
    }
}
