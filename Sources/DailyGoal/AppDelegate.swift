import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = GoalStore()
    private var panel: FloatingPanel!
    private var bridge: PanelBridge!
    private var statusBar: StatusBarController!
    private var rolloverTimer: Timer?
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel()
        bridge = PanelBridge(panel: panel)

        panel.onReturnKey = { [weak self] in
            guard let self, !self.store.isEditing else { return }
            self.beginEditing()
        }
        panel.onSpaceKey = { [weak self] in
            guard let self, !self.store.isEditing else { return }
            self.store.toggleCompleted()
        }

        let host = NSHostingView(rootView: GoalView(store: store, bridge: bridge))
        panel.contentView = host
        panel.delegate = self

        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 10 || size.height < 10 {
            size = CGSize(width: 420, height: 104)
        }
        panel.setFrame(restoredFrame(for: size), display: true)
        panel.orderFrontRegardless()

        statusBar = StatusBarController(store: store, app: self)

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
    }

    func showPanel() {
        panel.orderFrontRegardless()
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
