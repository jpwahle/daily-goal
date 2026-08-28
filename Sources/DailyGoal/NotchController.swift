import AppKit
import Combine

/// One island per screen: the physical notch grows on the MacBook display,
/// and every external screen hangs a virtual island from its top edge, so
/// the goal is wherever you're looking. This coordinator owns the fleet —
/// one shared poll ticks every island, screens changing rebuilds them — and
/// keeps the one-island API the rest of the app talks to.
final class NotchController {
    private let store: GoalStore
    private(set) var islands: [NotchIsland] = []
    private var poll: Timer?
    /// "Hide From Notch" in the menu: survives screen changes, and a nudge
    /// or a fresh day deliberately lifts it.
    private var userHidden = false
    private var editingEnded: AnyCancellable?

    init(store: GoalStore) {
        self.store = store
    }

    func install() {
        rebuild()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.islands.forEach { $0.tick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        poll = timer

        // Editing ends in one place (commit, cancel, hide) but hosts are
        // per-island: release whichever island held the field.
        editingEnded = store.$isEditing
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in self?.islands.forEach { $0.endEditingHost() } }
    }

    deinit {
        poll?.invalidate()
    }

    @objc private func screensChanged() {
        rebuild()
    }

    private func rebuild() {
        islands.forEach { $0.dismantle() }
        islands = NSScreen.screens.map { NotchIsland(store: store, screen: $0) }
        islands.forEach { $0.install() }
        if userHidden { islands.forEach { $0.hidePanel() } }
    }

    // MARK: - API (status bar menu, reminders, day rollover)

    var isVisible: Bool { islands.contains { $0.isPanelVisible } }

    func show() {
        userHidden = false
        islands.forEach { $0.showPanel() }
    }

    func hide() {
        userHidden = true
        store.isEditing = false
        islands.forEach { $0.hidePanel() }
    }

    /// Editing happens on one island: the one under the pointer, else the
    /// primary. The rest just come back into view.
    func beginEditing() {
        show()
        let mouse = NSEvent.mouseLocation
        let island = islands.first { $0.screen.frame.contains(mouse) }
            ?? islands.first { $0.screen == NSScreen.islandScreen }
            ?? islands.first
        island?.beginEditing()
    }

    /// Reminder nudge: every island opens up and glows.
    func nudge() {
        userHidden = false
        islands.forEach { $0.nudge() }
    }

    /// A fresh day deserves attention on every screen (even if hidden).
    func promptNewDay() {
        userHidden = false
        islands.forEach { $0.promptNewDay() }
    }
}
