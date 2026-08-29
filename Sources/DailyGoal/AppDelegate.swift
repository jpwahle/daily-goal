import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = GoalStore()
    private(set) var notch: NotchController!
    private var statusBar: StatusBarController!
    private var reminders: ReminderCenter!
    private var rolloverTimer: Timer?
    /// A new day's invite, waiting for the day's hours to actually open.
    private var pendingDayPrompt = false
    private var reminderResets = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(store: store)
        notch.install()

        statusBar = StatusBarController(store: store, app: self)
        reminders = ReminderCenter(store: store, app: self)
        UpdateChecker.shared.start()

        // Touching the goal restarts the reminder countdown, so a nudge never
        // fires right after the user just dealt with the goal.
        store.$goal.dropFirst().removeDuplicates()
            .merge(with: store.$isCompleted.dropFirst().removeDuplicates().map { _ in "" })
            .merge(with: store.$reminderInterval.dropFirst().removeDuplicates().map { _ in "" })
            .merge(with: store.$schedule.dropFirst().removeDuplicates().map { _ in "" })
            .sink { [weak self] _ in self?.reminders.reschedule() }
            .store(in: &reminderResets)

        rolloverTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.dayTick()
        }
        rolloverTimer?.tolerance = 5

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWoke),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: - Day rollover

    private func dayTick() {
        if store.rolloverIfNeeded() {
            // A new day deserves attention — but only a day that expects a
            // goal. Days off roll over in silence.
            pendingDayPrompt = !store.isDayOff
        }
        guard pendingDayPrompt else { return }
        // The goal beat us to it: no invite needed.
        if !store.goal.isEmpty {
            pendingDayPrompt = false
            return
        }
        // Hold the invite until the day's hours open. Rolling over at 4 a.m.
        // (or on a 7 a.m. wake, with the day starting at 9) would spend it on
        // nobody.
        if store.isWithinActiveHours() {
            pendingDayPrompt = false
            notch.promptNewDay()
        }
    }

    @objc private func systemWoke() {
        dayTick()
    }

    // MARK: - Island control (used by the status bar menu and reminders)

    func beginEditing() {
        notch.beginEditing()
    }

    func showIsland() {
        notch.show()
    }

    func hideIsland() {
        notch.hide()
    }

    var islandVisible: Bool { notch.isVisible }

    /// Attention nudge: the island opens and glows until it's dealt with.
    func nudgeGoal() {
        notch.nudge()
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.3
            sound.play()
        }
    }
}
