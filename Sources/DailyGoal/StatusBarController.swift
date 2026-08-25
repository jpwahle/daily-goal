import AppKit
import Combine
import ServiceManagement

/// Menu bar item: glanceable state (dashed circle → target → checkmark) plus
/// a small menu with the goal, streak, last-7-days dots, and app controls.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let store: GoalStore
    private unowned let app: AppDelegate
    private let item: NSStatusItem
    private var cancellable: AnyCancellable?

    init(store: GoalStore, app: AppDelegate) {
        self.store = store
        self.app = app
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        updateIcon()

        cancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateIcon() }
            }
    }

    private func updateIcon() {
        let symbol: String
        if store.goal.isEmpty {
            symbol = "circle.dashed"
        } else if store.isCompleted {
            symbol = "checkmark.circle.fill"
        } else {
            symbol = "target"
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Daily Goal")
        item.button?.toolTip = store.goal.isEmpty ? "Daily Goal — nothing set yet" : store.goal
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let headTitle: String
        if store.goal.isEmpty {
            headTitle = "No goal yet — set one"
        } else {
            let text = store.goal.count > 44 ? String(store.goal.prefix(44)) + "…" : store.goal
            headTitle = store.isCompleted ? "✓ \(text)" : text
        }
        let head = NSMenuItem(title: headTitle, action: #selector(editGoal), keyEquivalent: "")
        head.target = self
        menu.addItem(head)

        if store.streak >= 2 {
            let streak = NSMenuItem(title: "🔥 \(store.streak)-day streak", action: nil, keyEquivalent: "")
            streak.isEnabled = false
            menu.addItem(streak)
        }

        menu.addItem(weekItem())
        menu.addItem(.separator())

        let edit = NSMenuItem(
            title: store.goal.isEmpty ? "Set Today's Goal…" : "Edit Goal…",
            action: #selector(editGoal), keyEquivalent: "e")
        edit.target = self
        menu.addItem(edit)

        if !store.goal.isEmpty {
            let done = NSMenuItem(
                title: store.isCompleted ? "Mark as Not Done" : "Mark as Done",
                action: #selector(toggleDone), keyEquivalent: "d")
            done.target = self
            menu.addItem(done)
        }

        menu.addItem(.separator())
        menu.addItem(remindItem())

        let visibility = NSMenuItem(
            title: app.islandVisible ? "Hide From Notch" : "Show In Notch",
            action: #selector(toggleVisible), keyEquivalent: "")
        visibility.target = self
        menu.addItem(visibility)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        if let newer = UpdateChecker.shared.availableVersion {
            let install = NSMenuItem(
                title: "Install Daily Goal \(newer)…",
                action: #selector(installUpdate), keyEquivalent: "")
            install.target = self
            menu.addItem(install)
        }
        let check = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let auto = NSMenuItem(
            title: "Check Automatically", action: #selector(toggleAutoChecks), keyEquivalent: "")
        auto.target = self
        auto.state = UpdateChecker.shared.autoChecksEnabled ? .on : .off
        menu.addItem(auto)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Daily Goal", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func weekItem() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menuItem.isEnabled = false

        let text = NSMutableAttributedString(
            string: "Last 7 days   ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        for state in store.weekStates() {
            let glyph: String
            let color: NSColor
            switch state {
            case .done: glyph = "●"; color = .systemGreen
            case .missed: glyph = "●"; color = .tertiaryLabelColor
            case .pending: glyph = "○"; color = .systemBlue
            case .empty: glyph = "·"; color = .quaternaryLabelColor
            }
            text.append(NSAttributedString(
                string: glyph + " ",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color]))
        }
        menuItem.attributedTitle = text
        return menuItem
    }

    /// "Remind Me" submenu: how often the pill should demand attention while
    /// today's goal is still open (bounce when you're here, notification when
    /// you're away).
    private func remindItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Remind Me", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for choice in ReminderCenter.choices {
            let entry = NSMenuItem(title: choice.title, action: #selector(setReminder(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = choice.seconds
            entry.state = store.reminderInterval == choice.seconds ? .on : .off
            submenu.addItem(entry)
            if choice.seconds == 0 { submenu.addItem(.separator()) }
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func editGoal() {
        app.beginEditing()
    }

    @objc private func setReminder(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        store.setReminderInterval(seconds)
    }

    @objc private func toggleDone() {
        store.toggleCompleted()
    }

    @objc private func toggleVisible() {
        app.islandVisible ? app.hideIsland() : app.showIsland()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at Login toggle failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "Move Daily Goal.app to /Applications and try again.\n(\(error.localizedDescription))"
            alert.runModal()
        }
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkInteractively()
    }

    @objc private func installUpdate() {
        UpdateChecker.shared.installAvailableUpdate()
    }

    @objc private func toggleAutoChecks() {
        UpdateChecker.shared.autoChecksEnabled.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
