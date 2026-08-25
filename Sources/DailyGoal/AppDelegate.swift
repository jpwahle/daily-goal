import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = GoalStore()
    private(set) var notch: NotchController!
    private var statusBar: StatusBarController!
    private var reminders: ReminderCenter!
    private var rolloverTimer: Timer?
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
            // A new day deserves attention: open with the invite, even if the
            // island was hidden.
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
