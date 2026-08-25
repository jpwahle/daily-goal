import AppKit
import Combine
import SwiftUI

/// Owns the notch window and decides when the island grows and shrinks.
///
/// The island is pure display while collapsed: the panel ignores the mouse,
/// so clicks land on whatever is underneath. A pointer resting on the notch
/// (or a click on it) expands the island into the interactive card; moving
/// away collapses it. All of it is driven by a lightweight poll of the global
/// mouse state — a mouse-ignoring window receives no tracking events at all,
/// and polling needs no permissions.
final class NotchController: ObservableObject {
    enum IslandState {
        case collapsed // hugging the notch, mouse passes through
        case expanded  // the card is open and interactive
    }

    @Published private(set) var state: IslandState = .collapsed
    /// True while a reminder wants attention: the island glows violet.
    @Published private(set) var nudging = false
    @Published private(set) var hasNotch = true
    @Published private(set) var notchSize = CGSize(width: 190, height: 32)

    /// Geometry the SwiftUI view reports back so hit-testing matches what is
    /// actually on screen (preferences don't survive NSHostingView, so this
    /// travels through plain assignment on the main thread).
    struct IslandMetrics {
        var size = CGSize.zero
        /// Horizontal offset of the collapsed island's center from the notch
        /// center — the wings are asymmetric, so the shape sits off-center.
        var collapsedShift: CGFloat = 0
    }
    var metrics = IslandMetrics()

    private(set) var panel: NotchPanel!
    private let store: GoalStore
    private var poll: Timer?
    private var hoverSince: Date?   // pointer resting on the collapsed island
    private var awaySince: Date?    // pointer gone from the expanded island
    private var insideSince: Date?  // pointer resting inside the open island
    private var wasPressed = false
    private var autoCollapse: DispatchWorkItem?
    /// While set, the island keeps itself open even though the pointer is
    /// elsewhere — nudges and the new-day prompt would otherwise collapse
    /// before anyone saw them. A click outside still dismisses.
    private var holdUntil: Date?

    /// DG_SHOT_STATE=expanded|editing pins the island for screenshot staging
    /// (Scripts/make-shots.sh), like DG_APPEARANCE pins the theme.
    private let pinnedState = ProcessInfo.processInfo.environment["DG_SHOT_STATE"]

    private static let windowSize = CGSize(width: 640, height: 320)

    init(store: GoalStore) {
        self.store = store
    }

    func install() {
        panel = NotchPanel()
        panel.onReturnKey = { [weak self] in
            guard let self, !self.store.isEditing else { return }
            self.beginEditing()
        }
        panel.onSpaceKey = { [weak self] in
            guard let self, !self.store.isEditing else { return }
            self.store.toggleCompleted()
        }
        panel.contentView = NSHostingView(rootView: NotchIslandView(store: store, notch: self))
        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
        syncMouseAcceptance()

        switch pinnedState {
        case "expanded": expand()
        case "editing": DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.beginEditing() }
        default: break
        }
    }

    deinit {
        poll?.invalidate()
    }

    // MARK: - Window placement

    @objc private func screensChanged() {
        layout()
    }

    /// Centers the window on the notch (or where a notch would be). Sizes are
    /// measured from the system, so this is exact on every notched Mac and
    /// falls back to a virtual island on plain displays.
    private func layout() {
        guard let screen = NSScreen.islandScreen else { return }
        hasNotch = screen.hasNotch
        notchSize = screen.notchArea
        let frame = NSRect(
            x: screen.frame.midX - Self.windowSize.width / 2,
            y: screen.frame.maxY - Self.windowSize.height,
            width: Self.windowSize.width,
            height: Self.windowSize.height)
        panel.setFrame(frame, display: true)
    }

    // MARK: - API (status bar menu, reminders, day rollover)

    var isVisible: Bool { panel.isVisible }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        store.isEditing = false
        collapse()
        panel.orderOut(nil)
    }

    func beginEditing() {
        show()
        expand()
        store.isEditing = true
        makeKeyPanel()
    }

    /// The view calls this when the goal field needs keyboard focus.
    func makeKeyPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    /// Reminder nudge: open up, glow violet, and retreat unless engaged.
    func nudge() {
        show()
        expand()
        nudging = true
        holdUntil = Date().addingTimeInterval(2.8)
        scheduleAutoCollapse(after: 2.8) { [weak self] in self?.nudging = false }
    }

    /// A fresh day: open with the empty-goal invite, then retreat quietly.
    func promptNewDay() {
        show()
        expand()
        holdUntil = Date().addingTimeInterval(6)
        scheduleAutoCollapse(after: 6)
    }

    // MARK: - State machine

    private func expand() {
        hoverSince = nil
        awaySince = nil
        insideSince = nil
        if state != .expanded { state = .expanded }
        syncMouseAcceptance()
    }

    private func collapse() {
        guard !store.isEditing else { return }
        if state != .collapsed { state = .collapsed }
        if nudging { nudging = false }
        holdUntil = nil
        awaySince = nil
        insideSince = nil
        syncMouseAcceptance()
    }

    private func scheduleAutoCollapse(after seconds: TimeInterval, also: (() -> Void)? = nil) {
        autoCollapse?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            also?()
            self.holdUntil = nil
            // Engaged means the pointer is in the island or the user is
            // typing — never slam the door in their face.
            let engaged = self.store.isEditing
                || self.islandRect().insetBy(dx: -26, dy: -26).contains(NSEvent.mouseLocation)
            if !engaged { self.collapse() }
        }
        autoCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func tick() {
        guard pinnedState == nil else { return }
        guard panel.isVisible else {
            hoverSince = nil
            awaySince = nil
            return
        }
        let pressed = NSEvent.pressedMouseButtons & 1 == 1
        defer { wasPressed = pressed }
        let mouse = NSEvent.mouseLocation
        let island = islandRect()

        switch state {
        case .collapsed:
            // The whole notch counts, padded a little, so aiming is forgiving.
            var hot = island.union(notchRect())
            hot.origin.x -= 10
            hot.size.width += 20
            hot.origin.y -= 6
            hot.size.height += 6
            guard hot.contains(mouse) else {
                hoverSince = nil
                return
            }
            if pressed && !wasPressed {
                expand() // a deliberate click opens instantly
            } else if !pressed {
                let since = hoverSince ?? Date()
                hoverSince = since
                // A short dwell filters out cursors merely passing through
                // the top of the screen.
                if Date().timeIntervalSince(since) >= 0.25 { expand() }
            } else {
                hoverSince = nil // dragging something past — never yank open
            }

        case .expanded:
            hoverSince = nil
            if store.isEditing {
                awaySince = nil
                return
            }
            if island.insetBy(dx: -26, dy: -26).contains(mouse) {
                awaySince = nil
                // A pointer *resting* inside an empty island means "type
                // here" — focus the field. Resting, not passing: hover-expand
                // already fired once, so require a beat of stillness.
                if store.goal.isEmpty && island.contains(mouse) {
                    let since = insideSince ?? Date()
                    insideSince = since
                    if Date().timeIntervalSince(since) >= 0.35 { beginEditing() }
                } else {
                    insideSince = nil
                }
            } else {
                insideSince = nil
                if pressed && !wasPressed {
                    collapse() // clicking elsewhere dismisses immediately
                } else if let hold = holdUntil, Date() < hold {
                    awaySince = nil // a nudge holds itself open; its timer closes it
                } else {
                    let since = awaySince ?? Date()
                    awaySince = since
                    if Date().timeIntervalSince(since) >= 0.35 { collapse() }
                }
            }
        }
    }

    /// Collapsed, the island is a ghost to the mouse; expanded (or editing),
    /// it is a normal interactive surface.
    private func syncMouseAcceptance() {
        let ignore = state == .collapsed && !store.isEditing
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    // MARK: - Screen-space geometry

    /// Where the island currently is, in screen coordinates.
    private func islandRect() -> NSRect {
        guard metrics.size.width > 2 else { return notchRect() }
        let shift = state == .collapsed ? metrics.collapsedShift : 0
        return NSRect(
            x: panel.frame.midX + shift - metrics.size.width / 2,
            y: panel.frame.maxY - metrics.size.height,
            width: metrics.size.width,
            height: metrics.size.height)
    }

    private func notchRect() -> NSRect {
        NSRect(
            x: panel.frame.midX - notchSize.width / 2,
            y: panel.frame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height)
    }
}
