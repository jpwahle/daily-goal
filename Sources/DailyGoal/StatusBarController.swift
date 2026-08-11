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

        let visibility = NSMenuItem(
            title: app.panelVisible ? "Hide From Screen" : "Show On Screen",
            action: #selector(toggleVisible), keyEquivalent: "")
        visibility.target = self
        menu.addItem(visibility)

        let reset = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

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

    // MARK: - Actions

    @objc private func editGoal() {
        app.beginEditing()
    }

    @objc private func toggleDone() {
        store.toggleCompleted()
    }

    @objc private func toggleVisible() {
        app.panelVisible ? app.hidePanel() : app.showPanel()
    }

    @objc private func resetPosition() {
        app.showPanel()
        app.resetPosition()
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
