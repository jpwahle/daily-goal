import AppKit
import SwiftUI

/// One island on one screen: owns its notch window and decides when it grows
/// and shrinks. On the MacBook display it hugs the physical notch; on any
/// other screen it hangs from the top edge as a virtual island.
///
/// The island is pure display while collapsed: the panel ignores the mouse,
/// so clicks land on whatever is underneath. A pointer resting on the notch
/// (or a click on it) expands the island into the interactive card; moving
/// away collapses it. All of it is driven by a lightweight poll of the global
/// mouse state — a mouse-ignoring window receives no tracking events at all,
/// and polling needs no permissions. The poll itself lives in
/// `NotchController`, which ticks every island from one timer.
final class NotchIsland: ObservableObject {
    enum IslandState {
        case collapsed // hugging the notch, mouse passes through
        case expanded  // the card is open and interactive
    }

    @Published private(set) var state: IslandState = .collapsed
    /// True while a reminder wants attention: the island glows violet.
    @Published private(set) var nudging = false
    @Published private(set) var hasNotch = true
    @Published private(set) var notchSize = CGSize(width: 190, height: 32)
    /// Free menu bar beside the notch. Every point past these gaps belongs
    /// to someone's status item, and the island keeps its hands off it.
    @Published private(set) var barGaps = BarGaps()
    /// No-notch screens only: a status item slid under the virtual island's
    /// spot, so the collapsed island conceals itself and stops hover-opening.
    @Published private(set) var virtualBlocked = false
    /// Whether the goal editor belongs to *this* island — the goal state is
    /// shared, but only one screen's card holds the text field.
    @Published private(set) var isEditingHost = false

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
    let screen: NSScreen
    private let store: GoalStore
    private var lastGapScan = Date.distantPast
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

    /// Editing is per-island: the shared flag only rules *this* island while
    /// it hosts the editor.
    private var editingHere: Bool { store.isEditing && isEditingHost }

    init(store: GoalStore, screen: NSScreen) {
        self.store = store
        self.screen = screen
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
        syncMouseAcceptance()

        switch pinnedState {
        case "expanded":
            expand()
        case "editing":
            // Only the primary island takes the field; the rest just open.
            if screen == NSScreen.islandScreen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.beginEditing() }
            } else {
                expand()
            }
        default: break
        }
    }

    /// Screens changed: this island's display is gone (or moved), so the
    /// panel retires. Dropping the content view breaks the panel↔island
    /// retain loop through the hosting view.
    func dismantle() {
        autoCollapse?.cancel()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: - Window placement

    /// Centers the window on the notch (or where a notch would be). Sizes are
    /// measured from the system, so this is exact on every notched Mac and
    /// falls back to a virtual island on plain displays.
    private func layout() {
        hasNotch = screen.hasNotch
        notchSize = screen.notchArea
        let frame = NSRect(
            x: screen.frame.midX - Self.windowSize.width / 2,
            y: screen.frame.maxY - Self.windowSize.height,
            width: Self.windowSize.width,
            height: Self.windowSize.height)
        panel.setFrame(frame, display: true)
        rescanBarGaps()
    }

    // MARK: - Menu bar items

    /// Items come and go at any time — a manager like Hidden Bar or
    /// Bartender reveals a whole batch at once, always with the pointer up
    /// at the bar. Scan briskly while the pointer is near the bar, lazily
    /// otherwise, so the wings retract before a freshly revealed item could
    /// even be aimed at.
    private func rescanBarGapsIfDue(mouse: NSPoint) {
        let nearBar = mouse.y > panel.frame.maxY - 60 && screen.frame.contains(mouse)
        let staleAfter: TimeInterval = nearBar ? 0.25 : 2.0
        guard Date().timeIntervalSince(lastGapScan) >= staleAfter else { return }
        rescanBarGaps()
    }

    private func rescanBarGaps() {
        lastGapScan = Date()
        let scan = MenuBarLayout.scan(around: notchRect(), on: screen, physicalNotch: hasNotch)
        if scan.gaps != barGaps { barGaps = scan.gaps }
        if scan.notchIntruded != virtualBlocked { virtualBlocked = scan.notchIntruded }
    }

    // MARK: - API (driven by NotchController)

    var isPanelVisible: Bool { panel.isVisible }

    func showPanel() {
        panel.orderFrontRegardless()
    }

    func hidePanel() {
        collapse()
        panel.orderOut(nil)
    }

    func beginEditing() {
        showPanel()
        expand()
        isEditingHost = true
        store.isEditing = true
        makeKeyPanel()
    }

    /// Editing ended (anywhere): this island no longer hosts the field.
    func endEditingHost() {
        if isEditingHost { isEditingHost = false }
    }

    /// The view calls this when the goal field needs keyboard focus.
    func makeKeyPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    /// Reminder nudge: open up, glow violet, and retreat unless engaged.
    func nudge() {
        guard !virtualBlocked else { return } // never open on top of an item
        showPanel()
        expand()
        nudging = true
        holdUntil = Date().addingTimeInterval(2.8)
        scheduleAutoCollapse(after: 2.8) { [weak self] in self?.nudging = false }
    }

    /// A fresh day: open with the empty-goal invite, then retreat quietly.
    func promptNewDay() {
        guard !virtualBlocked else { return } // never open on top of an item
        showPanel()
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
        guard !editingHere else { return }
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
            let engaged = self.editingHere
                || self.islandRect().insetBy(dx: -26, dy: -26).contains(NSEvent.mouseLocation)
            if !engaged { self.collapse() }
        }
        autoCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func tick() {
        guard pinnedState == nil else { return }
        guard panel.isVisible else {
            hoverSince = nil
            awaySince = nil
            return
        }
        let pressed = NSEvent.pressedMouseButtons & 1 == 1
        defer { wasPressed = pressed }
        let mouse = NSEvent.mouseLocation
        rescanBarGapsIfDue(mouse: mouse)
        let island = islandRect()

        switch state {
        case .collapsed:
            // A blocked virtual island is invisible; opening it on hover
            // would drop black over the very item standing in its place.
            guard !virtualBlocked else {
                hoverSince = nil
                return
            }
            // The whole notch counts, padded a little, so aiming is forgiving.
            var hot = island.union(notchRect())
            hot.origin.x -= 10
            hot.size.width += 20
            hot.origin.y -= 6
            hot.size.height += 6
            // But the forgiveness must never reach over a neighbouring menu
            // bar item — a pointer there is aiming at the item, not at us.
            let notch = notchRect()
            let lo = max(hot.minX, notch.minX - max(0, barGaps.left - 2))
            let hi = min(hot.maxX, notch.maxX + max(0, barGaps.right - 2))
            hot.origin.x = lo
            hot.size.width = max(hi - lo, 0)
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
            if editingHere {
                awaySince = nil
                return
            }
            if island.insetBy(dx: -26, dy: -26).contains(mouse) {
                awaySince = nil
                // A pointer *resting* inside an empty island means "type
                // here" — focus the field. Resting, not passing: hover-expand
                // already fired once, so require a beat of stillness. Only
                // below the bar: the card's bounding box corners up in the
                // bar belong to the menu bar, not to us.
                // Never on a day off, though: nothing is due, so opening a
                // field under the pointer would be the nagging we removed.
                let belowBar = mouse.y < panel.frame.maxY - notchSize.height
                if store.goal.isEmpty && !store.isResting && !store.isEditing
                    && island.contains(mouse) && belowBar {
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

    /// Collapsed, the island is a ghost to the mouse; expanded (or editing
    /// here), it is a normal interactive surface.
    private func syncMouseAcceptance() {
        let ignore = state == .collapsed && !editingHere
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
