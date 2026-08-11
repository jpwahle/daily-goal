import AppKit
import Combine

/// A "logical day" runs 4 a.m. → 4 a.m., so finishing a goal at 1 a.m. still
/// counts for the evening it belongs to.
enum DayState {
    case done      // goal set and completed
    case missed    // goal set, never completed
    case pending   // today, still open
    case empty     // no goal that day
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
    /// Bumped whenever the pill should bounce for attention.
    @Published var nudgeTick = 0

    private(set) var history: [DayRecord] = []
    private var dayKey = ""
    private var lastCompletedDay: String?
    private var undoSnapshot: (streak: Int, lastCompleted: String?)?

    private let defaults = UserDefaults.standard

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

    /// 0 at 4 a.m., 1 at the next 4 a.m.
    func dayProgress(at date: Date = Date()) -> Double {
        let shifted = date.addingTimeInterval(-Self.dayStartHour * 3600)
        let start = Calendar.current.startOfDay(for: shifted)
        return min(1, max(0, shifted.timeIntervalSince(start) / 86400))
    }

    func secondsLeft(at date: Date = Date()) -> TimeInterval {
        (1 - dayProgress(at: date)) * 86400
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

        let yesterday = logicalDayKey(for: Date().addingTimeInterval(-86400))
        if lastCompletedDay != yesterday && lastCompletedDay != today {
            streak = 0
        }

        dayKey = today
        goal = ""
        isCompleted = false
        isEditing = false
        undoSnapshot = nil
        save()
        return true
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
        let yesterday = logicalDayKey(for: Date().addingTimeInterval(-86400))
        streak = (lastCompletedDay == yesterday) ? streak + 1 : 1
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
            lastCompletedDay = streak > 0 ? logicalDayKey(for: Date().addingTimeInterval(-86400)) : nil
        }
        undoSnapshot = nil
        isCompleted = false
        save()
    }

    /// Last 7 logical days, oldest first, today last.
    func weekStates() -> [DayState] {
        (0..<7).reversed().map { offset in
            let key = logicalDayKey(for: Date().addingTimeInterval(-Double(offset) * 86400))
            if key == dayKey {
                if goal.isEmpty { return .empty }
                return isCompleted ? .done : .pending
            }
            guard let record = history.last(where: { $0.day == key }) else { return .empty }
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
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: "history")
        }
    }
}
