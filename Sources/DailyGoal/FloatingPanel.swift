import AppKit

enum Layout {
    /// Transparent halo around the pill so the drop shadow and confetti can
    /// render outside the capsule.
    static let margin: CGFloat = 30
}

/// Borderless, non-activating panel that floats above every window and space.
/// It can become key (so the goal text field is typeable) without ever
/// activating the app or stealing focus from whatever you're working in.
final class FloatingPanel: NSPanel {
    var onReturnKey: (() -> Void)?
    var onSpaceKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 104),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // SwiftUI draws a softer capsule shadow
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // While the panel happens to be key (right after editing), keep keystrokes
    // useful instead of beeping: Return edits, Space toggles done, ⌘Q quits.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return
        }
        switch event.keyCode {
        case 36, 76: onReturnKey?() // return / keypad enter
        case 49: onSpaceKey?()      // space
        default: break              // swallow silently — no system beep
        }
    }
}

/// Thin bridge the SwiftUI view uses to talk to its hosting panel.
final class PanelBridge {
    weak var panel: NSPanel?

    init(panel: NSPanel) {
        self.panel = panel
    }

    func makeKeyPanel() {
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Resize the window to fit the pill. Only the size is set here — the
    /// delegate's windowDidResize puts the frame back on the pill's anchor.
    func contentSizeChanged(_ size: CGSize) {
        guard let panel, size.width > 1, size.height > 1 else { return }
        var frame = panel.frame
        guard abs(frame.width - size.width) > 0.5 || abs(frame.height - size.height) > 0.5 else { return }
        frame.size = size
        panel.setFrame(frame, display: true)
    }
}
