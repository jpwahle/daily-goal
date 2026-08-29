import AppKit
import Combine

/// A "logical day" runs 4 a.m. → 4 a.m., so finishing a goal at 1 a.m. still
/// counts for the evening it belongs to.
enum DayState {
    case done      // goal set and completed
    case missed    // goal set, never completed
    case pending   // today, still open
    case empty     // no goal that day
    case off       // a day the schedule keeps clear
}

struct DayRecord: Codable {
    let day: String
    let goal: String
    let completed: Bool
}

final class GoalStore: ObservableObject {
    @Published var goal = ""
    @Published var isCompleted = false
    @Published var streak = 0
    @Published var isEditing = false
    @Published private(set) var celebrationTick = 0

    /// Seconds between reminder nudges; 0 turns reminders off.
    @Published private(set) var reminderInterval: TimeInterval = 3600
    /// Which days carry a goal, and the hours they run for.
    @Published private(set) var schedule = Schedule.standard
    /// Bumped whenever the pill should bounce for attention.
    @Published var nudgeTick = 0

    private(set) var history: [DayRecord] = []
    private var dayKey = ""
    private var lastCompletedDay: String?
    private var undoSnapshot: (streak: Int, lastCompleted: String?)?

    private let defaults = UserDefaults.standard
    private var calendar: Calendar { Calendar.current }

    static let dayStartHour: TimeInterval = 4
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    init() {
        load()
        rolloverIfNeeded()
    }

    // MARK: - Logical day math

    func logicalDayKey(for date: Date = Date()) -> String {
        Self.dayFormatter.string(from: date.addingTimeInterval(-Self.dayStartHour * 3600))
    }

    /// Noon on the date a key names — a safe anchor for day arithmetic, since
    /// stepping days from midday never lands in a DST gap.
    private func noon(forDayKey key: String) -> Date? {
        guard let midnight = Self.dayFormatter.date(from: key) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: midnight)
        parts.hour = 12
        return calendar.date(from: parts)
    }

    /// The key `days` away from `key`, stepped through the calendar.
    func shiftDayKey(_ key: String, by days: Int) -> String {
        guard let anchor = noon(forDayKey: key),
              let shifted = calendar.date(byAdding: .day, value: days, to: anchor)
        else { return key }
        return Self.dayFormatter.string(from: shifted)
    }

    /// 4 a.m. on the day a key names: where its progress ring starts.
    private func dayStart(forDayKey key: String) -> Date? {
        guard let anchor = noon(forDayKey: key) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: anchor)
        parts.hour = Int(Self.dayStartHour)
        return calendar.date(from: parts)
    }

    // MARK: - Days on and days off

    /// A day the schedule keeps clear: no invite, no nudges, and the streak
    /// steps straight over it.
    func isDayOff(_ key: String) -> Bool {
        guard let anchor = noon(forDayKey: key) else { return false }
        return !schedule.isActive(weekday: calendar.component(.weekday, from: anchor))
    }

    var isDayOff: Bool { isDayOff(logicalDayKey()) }

    /// Today is off *and* nothing was set anyway — the state the island shows
    /// as a day off. Setting a goal on a day off makes it an ordinary day.
    var isResting: Bool { isDayOff && goal.isEmpty }

    /// Today's live stretch: the schedule's hours on an active day, the whole
    /// logical day on a day off.
    ///
    /// A goal set on a day off anyway keeps the whole day — the hours describe
    /// working days, so a Saturday goal picked up at 8 p.m. would otherwise
    /// arrive after its own window had already closed.
    func activeWindow(at date: Date = Date()) -> (start: Date, end: Date) {
        let key = logicalDayKey(for: date)
        let start = dayStart(forDayKey: key) ?? date
        guard !isDayOff(key) else {
            let end = calendar.date(byAdding: .day, value: 1, to: start)
                ?? start.addingTimeInterval(86400)
            return (start, end)
        }
        return schedule.window(inDayStarting: start, calendar: calendar)
    }

    func isWithinActiveHours(at date: Date = Date()) -> Bool {
        let window = activeWindow(at: date)
        return date >= window.start && date < window.end
    }

    /// The window has closed, but the day hasn't: the ring is full and the
    /// goal is still there to check off until 4 a.m.
    func isAfterHours(at date: Date = Date()) -> Bool {
        date >= activeWindow(at: date).end
    }

    /// Whether a nudge is welcome right now — inside the day's window, and
    /// never on a day off unless a goal was deliberately set anyway.
    func isGoalLive(at date: Date = Date()) -> Bool {
        guard !isDayOff(logicalDayKey(for: date)) || !goal.isEmpty else { return false }
        return isWithinActiveHours(at: date)
    }

    /// 0 when the day's window opens, 1 when it closes.
    func dayProgress(at date: Date = Date()) -> Double {
        let window = activeWindow(at: date)
        let span = window.end.timeIntervalSince(window.start)
        guard span > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(window.start) / span))
    }

    func secondsLeft(at date: Date = Date()) -> TimeInterval {
        max(0, activeWindow(at: date).end.timeIntervalSince(date))
    }

    // MARK: - Schedule settings

    func setActiveDays(_ days: Set<Int>) {
        schedule.activeDays = days.filter { (1...7).contains($0) }
        save()
    }

    func toggleActiveDay(_ weekday: Int) {
        var days = schedule.activeDays
        days.formSymmetricDifference([weekday])
        setActiveDays(days)
    }

    /// Wall-clock minutes past midnight. Equal values mean the whole day.
    func setActiveHours(start: Int, end: Int) {
        schedule.startMinutes = min(max(0, start), 1439)
        schedule.endMinutes = min(max(0, end), 1439)
        save()
    }

    // MARK: - Day rollover

    /// Returns true when a new day started: yesterday is archived, the pill resets.
    @discardableResult
    func rolloverIfNeeded() -> Bool {
        let today = logicalDayKey()
        guard today != dayKey else { return false }

        if !dayKey.isEmpty && !goal.isEmpty {
            history.append(DayRecord(day: dayKey, goal: goal, completed: isCompleted))
            if history.count > 90 { history.removeFirst(history.count - 90) }
        }

        // The streak survives only if nothing but days off has passed since
        // it was last fed.
        let streakSurvives = lastCompletedDay
            .map { $0 == today || isStreakAdjacent($0, to: today) } ?? false
        if !streakSurvives { streak = 0 }

        dayKey = today
        goal = ""
        isCompleted = false
        isEditing = false
        undoSnapshot = nil
        save()
        return true
    }

    // MARK: - Streak continuity

    /// True when nothing but days off separates `day` from `today` — a streak
    /// steps over a weekend, but never over a working day you skipped.
    func isStreakAdjacent(_ day: String, to today: String) -> Bool {
        guard day < today else { return false }
        var cursor = shiftDayKey(day, by: 1)
        var steps = 0
        while cursor != today {
            guard cursor < today, steps < 370 else { return false }
            guard isDayOff(cursor) else { return false }
            cursor = shiftDayKey(cursor, by: 1)
            steps += 1
        }
        return true
    }

    /// The next day that carries a goal — nil when the schedule holds none.
    func nextActiveDay(after key: String) -> String? {
        var cursor = shiftDayKey(key, by: 1)
        for _ in 0..<7 {
            if !isDayOff(cursor) { return cursor }
            cursor = shiftDayKey(cursor, by: 1)
        }
        return nil
    }

    /// A day's own name, the way this locale writes it.
    func weekdayName(forDayKey key: String) -> String {
        guard let anchor = noon(forDayKey: key) else { return "" }
        return Self.weekdayNameFormatter.string(from: anchor)
    }

    private static let weekdayNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()

    /// The active day before `key` — where a streak's previous link sits.
    func previousActiveDay(before key: String) -> String {
        var cursor = shiftDayKey(key, by: -1)
        for _ in 0..<370 {
            if !isDayOff(cursor) { return cursor }
            cursor = shiftDayKey(cursor, by: -1)
        }
        return cursor
    }

    // MARK: - Actions

    func setGoal(_ text: String) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        goal = trimmed
        if trimmed.isEmpty { isCompleted = false }
        save()
    }

    func toggleCompleted() {
        isCompleted ? uncomplete() : complete()
    }

    func setReminderInterval(_ seconds: TimeInterval) {
        reminderInterval = max(0, seconds)
        save()
    }

    func complete() {
        guard !goal.isEmpty, !isCompleted else { return }
        undoSnapshot = (streak, lastCompletedDay)
        let continues = lastCompletedDay.map { isStreakAdjacent($0, to: dayKey) } ?? false
        streak = continues ? streak + 1 : 1
        lastCompletedDay = dayKey
        isCompleted = true
        celebrationTick += 1
        save()

        if let sound = NSSound(named: "Pop") {
            sound.volume = 0.5
            sound.play()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    func uncomplete() {
        guard isCompleted else { return }
        if let snapshot = undoSnapshot {
            streak = snapshot.streak
            lastCompletedDay = snapshot.lastCompleted
        } else {
            // App restarted since completion; reconstruct best-effort.
            streak = max(0, streak - 1)
            lastCompletedDay = streak > 0 ? previousActiveDay(before: dayKey) : nil
        }
        undoSnapshot = nil
        isCompleted = false
        save()
    }

    /// Last 7 logical days, oldest first, today last.
    func weekStates() -> [DayState] {
        (0..<7).reversed().map { offset in
            let key = shiftDayKey(dayKey, by: -offset)
            if key == dayKey {
                if goal.isEmpty { return isDayOff(key) ? .off : .empty }
                return isCompleted ? .done : .pending
            }
            guard let record = history.last(where: { $0.day == key }) else {
                return isDayOff(key) ? .off : .empty
            }
            return record.completed ? .done : .missed
        }
    }

    // MARK: - Persistence

    private func load() {
        goal = defaults.string(forKey: "goal") ?? ""
        isCompleted = defaults.bool(forKey: "completed")
        streak = defaults.integer(forKey: "streak")
        dayKey = defaults.string(forKey: "dayKey") ?? ""
        lastCompletedDay = defaults.string(forKey: "lastCompletedDay")
        reminderInterval = defaults.object(forKey: "reminderInterval") as? Double ?? 3600
        // An empty array is a real answer here — every day turned off — so
        // only an absent key falls back to the default week.
        if let days = defaults.array(forKey: "activeDays") as? [Int] {
            schedule.activeDays = Set(days.filter { (1...7).contains($0) })
        }
        if let start = defaults.object(forKey: "activeHoursStart") as? Int,
           let end = defaults.object(forKey: "activeHoursEnd") as? Int {
            // An earlier build kept a separate on/off flag beside the range.
            // Off now simply means a range that spans the whole day.
            let legacyFlag = defaults.object(forKey: "activeHoursEnabled") as? Bool
            let restricted = legacyFlag ?? true
            schedule.startMinutes = restricted ? start : Schedule.dayStartMinutes
            schedule.endMinutes = restricted ? end : Schedule.dayStartMinutes
            if legacyFlag != nil {
                // Write the reinterpretation through now. Once the flag is
                // gone there is nothing left to reinterpret the old range
                // *with*, so a launch that only migrated in memory would read
                // the narrow window straight back.
                defaults.set(schedule.startMinutes, forKey: "activeHoursStart")
                defaults.set(schedule.endMinutes, forKey: "activeHoursEnd")
            }
        }
        // Drop the flag the moment it has been read: left behind, a stale
        // `false` would quietly undo every range set from here on.
        defaults.removeObject(forKey: "activeHoursEnabled")
        if let data = defaults.data(forKey: "history"),
           let records = try? JSONDecoder().decode([DayRecord].self, from: data) {
            history = records
        }
    }

    private func save() {
        defaults.set(goal, forKey: "goal")
        defaults.set(isCompleted, forKey: "completed")
        defaults.set(streak, forKey: "streak")
        defaults.set(dayKey, forKey: "dayKey")
        defaults.set(lastCompletedDay, forKey: "lastCompletedDay")
        defaults.set(reminderInterval, forKey: "reminderInterval")
        defaults.set(schedule.activeDays.sorted(), forKey: "activeDays")
        defaults.set(schedule.startMinutes, forKey: "activeHoursStart")
        defaults.set(schedule.endMinutes, forKey: "activeHoursEnd")
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: "history")
        }
    }
}
