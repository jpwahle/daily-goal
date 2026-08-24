import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = GoalStore()
    private(set) var interaction: PillInteractionController!
    private var panel: FloatingPanel!
    private var bridge: PanelBridge!
    private var statusBar: StatusBarController!
    private var reminders: ReminderCenter!
    private var rolloverTimer: Timer?
    private var reminderResets = Set<AnyCancellable>()
    private var userIsDragging = false
    private var snapPoll: Timer?
    /// Where the pill belongs: the window's (midX, maxY). Deliberate moves
    /// (drags, snaps, Reset Position) update it; content resizes restore it.
    private var pillAnchor = NSPoint.zero
    private var reanchoring = false
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel()
        bridge = PanelBridge(panel: panel)
        interaction = PillInteractionController(panel: panel, store: store)

        panel.onReturnKey = { [weak self] in
            guard let self, !self.store.isEditing else { return }
            self.beginEditing()
        }
        panel.onSpaceKey = { [weak self] in
            guard let self, !self.store.isEditing else { return }
            self.store.toggleCompleted()
        }

        let host = NSHostingView(rootView: GoalView(store: store, bridge: bridge, interaction: interaction))
        panel.contentView = host
        panel.delegate = self

        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 10 || size.height < 10 {
            size = CGSize(width: 420, height: 104)
        }
        let frame = restoredFrame(for: size)
        pillAnchor = NSPoint(x: frame.midX, y: frame.maxY)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        statusBar = StatusBarController(store: store, app: self)
        reminders = ReminderCenter(store: store, app: self)
        UpdateChecker.shared.start()

        // Touching the goal restarts the reminder countdown, so a nudge never
        // fires right after the user just dealt with the pill.
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
            showPanel() // a new day deserves a visible pill, even if it was hidden
        }
    }

    @objc private func systemWoke() {
        dayTick()
    }

    // MARK: - Panel control (used by the status bar menu)

    func beginEditing() {
        showPanel()
        store.isEditing = true
        interaction.refresh() // accept mouse events now, not a poll-tick later
    }

    func showPanel() {
        panel.orderFrontRegardless()
    }

    /// Attention nudge: surface the pill and let the view bounce it.
    func nudgePill() {
        showPanel()
        store.nudgeTick += 1
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.3
            sound.play()
        }
    }

    func hidePanel() {
        panel.orderOut(nil)
    }

    var panelVisible: Bool { panel.isVisible }

    func resetPosition() {
        panel.setFrame(defaultFrame(for: panel.frame.size), display: true, animate: true)
    }

    // MARK: - Frame persistence

    func windowDidMove(_ notification: Notification) {
        defaults.set(Double(panel.frame.origin.x), forKey: "panelX")
        defaults.set(Double(panel.frame.origin.y), forKey: "panelY")
        if !reanchoring {
            pillAnchor = NSPoint(x: panel.frame.midX, y: panel.frame.maxY)
        }
        if userIsDragging { armSnapOnRelease() }
    }

    /// Whenever the pill changes width (entering or leaving edit mode, streak
    /// chip appearing…) the resize keeps the window origin, so the pill would
    /// slide sideways. Put it back on its anchor so it grows and shrinks
    /// around its center instead.
    func windowDidResize(_ notification: Notification) {
        guard pillAnchor != .zero else { return } // still launching
        var origin = NSPoint(x: pillAnchor.x - panel.frame.width / 2,
                             y: pillAnchor.y - panel.frame.height)
        // A pill parked at a screen edge could grow past it — keep the
        // visible part at the usual 10 pt edge padding (without moving the
        // anchor, so it returns to its spot once the pill shrinks back).
        if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame {
            let inset = 10 - Layout.margin
            let minX = vf.minX + inset
            let maxX = vf.maxX - inset - panel.frame.width
            if minX <= maxX { origin.x = min(max(origin.x, minX), maxX) }
        }
        guard origin != panel.frame.origin else { return }
        reanchoring = true
        panel.setFrameOrigin(origin)
        reanchoring = false
    }

    // MARK: - Magnetic snapping

    /// windowWillMove only fires for user drags, never for programmatic
    /// setFrame calls, so this cleanly separates the two.
    func windowWillMove(_ notification: Notification) {
        userIsDragging = NSEvent.pressedMouseButtons & 1 == 1
    }

    /// The system drag loop owns the window position until the mouse goes up,
    /// so snapping mid-drag would just fight it — poll for release instead.
    private func armSnapOnRelease() {
        guard snapPoll == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
            self.snapPoll?.invalidate()
            self.snapPoll = nil
            self.userIsDragging = false
            self.snapToMagnet()
        }
        RunLoop.main.add(timer, forMode: .common)
        snapPoll = timer
    }

    private func snapToMagnet() {
        guard let target = magnetFrame(for: panel.frame), target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// Magnets sit at left/center/right × top/middle/bottom of the screen's
    /// visible area; each axis attracts independently, so the pill also snaps
    /// onto grid lines (e.g. exact horizontal center) while sliding freely
    /// along the other axis.
    private func magnetFrame(for frame: NSRect) -> NSRect? {
        let pill = frame.insetBy(dx: Layout.margin, dy: Layout.margin)
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.frame.contains(NSPoint(x: pill.midX, y: pill.midY)) })
                ?? screens.first(where: { $0.visibleFrame.intersects(pill) })
        else { return nil }

        let vf = screen.visibleFrame
        let pad: CGFloat = 10   // pill edge distance from the screen edge, as in defaultFrame
        let pull: CGFloat = 32  // magnet strength, in points

        let xMagnets = [vf.minX + pad + pill.width / 2, vf.midX, vf.maxX - pad - pill.width / 2]
        let yMagnets = [vf.minY + pad + pill.height / 2, vf.midY, vf.maxY - pad - pill.height / 2]

        var center = NSPoint(x: pill.midX, y: pill.midY)
        var pulled = false
        if let x = xMagnets.min(by: { abs($0 - center.x) < abs($1 - center.x) }),
           abs(x - center.x) <= pull {
            center.x = x
            pulled = true
        }
        if let y = yMagnets.min(by: { abs($0 - center.y) < abs($1 - center.y) }),
           abs(y - center.y) <= pull {
            center.y = y
            pulled = true
        }
        guard pulled else { return nil }
        return NSRect(x: center.x - frame.width / 2, y: center.y - frame.height / 2,
                      width: frame.width, height: frame.height)
    }

    private func restoredFrame(for size: CGSize) -> NSRect {
        if let x = defaults.object(forKey: "panelX") as? Double,
           let y = defaults.object(forKey: "panelY") as? Double {
            let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            let pillRect = frame.insetBy(dx: Layout.margin, dy: Layout.margin)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(pillRect) }) {
                return frame
            }
        }
        return defaultFrame(for: size)
    }

    private func defaultFrame(for size: CGSize) -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 200, y: 200, width: size.width, height: size.height)
        }
        let vf = screen.visibleFrame
        // Top-center, pill edge ~10 pt below the menu bar.
        return NSRect(x: vf.midX - size.width / 2,
                      y: vf.maxY - size.height + Layout.margin - 10,
                      width: size.width,
                      height: size.height)
    }
}
