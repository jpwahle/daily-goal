import AppKit
import Combine

/// Decides, several times a second, whether the pill should catch the mouse.
///
/// By default it shouldn't: the panel ignores mouse events, so every click
/// lands on whatever sits underneath — the pill is a pure display. Moving the
/// pointer over it fades it to a ghost, keeping the content behind readable.
/// Holding ⌥ while over it makes it solid and interactive (check off, edit,
/// drag). An empty pill is the exception: its whole job is to be clicked, so
/// plain hovering wakes it until a goal exists. The status-bar menu can turn
/// click-through off entirely, restoring the classic always-clickable pill.
///
/// A mouse-ignoring window receives no tracking events at all, so hover can't
/// come from the view — a lightweight poll of the global mouse state drives
/// the mode instead.
final class PillInteractionController: ObservableObject {
    enum Mode {
        case passive // catching nothing; normal look, idle dimming applies
        case ghost   // pointer over the pill without ⌥: faded, still click-through
        case live    // pointer over the pill with ⌥ (or pill empty): interactive
    }

    @Published private(set) var mode: Mode = .passive
    @Published private(set) var showHint = false

    var clickThroughEnabled: Bool {
        get { defaults.object(forKey: "clickThrough") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "clickThrough")
            refresh()
        }
    }

    private let panel: NSPanel
    private let store: GoalStore
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var ghostSince: Date?

    /// Once ⌥-interaction has been used a few times, the teaching hint retires.
    private var hintRetired: Bool { defaults.integer(forKey: "optionInteractCount") >= 3 }

    init(panel: NSPanel, store: GoalStore) {
        self.panel = panel
        self.store = store
        panel.ignoresMouseEvents = clickThroughEnabled

        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    deinit { timer?.invalidate() }

    /// Re-evaluates immediately; call when a mode input just changed (editing
    /// started, toggle flipped) instead of waiting out the poll interval.
    func refresh() {
        // Editing always accepts events — the user is typing in the pill.
        if store.isEditing {
            apply(mode: .live, interactive: true, hint: false)
            ghostSince = nil
            return
        }
        guard clickThroughEnabled else {
            apply(mode: .passive, interactive: true, hint: false)
            return
        }
        guard panel.isVisible else {
            apply(mode: .passive, interactive: false, hint: false)
            ghostSince = nil
            return
        }
        // Never flip states under a pressed button: it would yank the window
        // out from under its own ⌥-drag, or steal a drag passing over it.
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let pill = panel.frame.insetBy(dx: Layout.margin, dy: Layout.margin)
        guard pill.contains(NSEvent.mouseLocation) else {
            apply(mode: .passive, interactive: false, hint: false)
            ghostSince = nil
            return
        }

        if store.goal.isEmpty || optionHeld {
            if mode != .live && optionHeld && !store.goal.isEmpty {
                defaults.set(defaults.integer(forKey: "optionInteractCount") + 1,
                             forKey: "optionInteractCount")
            }
            apply(mode: .live, interactive: true, hint: false)
            ghostSince = nil
        } else {
            let since = ghostSince ?? Date()
            ghostSince = since
            // Lingering over a ghost usually means "why can't I click this?" —
            // answer it, until the gesture has demonstrably been learned.
            let lingering = Date().timeIntervalSince(since) > 0.7
            apply(mode: .ghost, interactive: false, hint: lingering && !hintRetired)
        }
    }

    private var optionHeld: Bool {
        // Real keyboards report through NSEvent; events posted by tests only
        // show up in the session's combined state.
        NSEvent.modifierFlags.contains(.option)
            || CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    private func apply(mode: Mode, interactive: Bool, hint: Bool) {
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
        if self.mode != mode { self.mode = mode }
        if showHint != hint { showHint = hint }
    }
}
