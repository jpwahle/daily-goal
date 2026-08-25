import AppKit

/// Borderless, non-activating panel pinned over the notch. It sits above the
/// menu bar on every Space (full-screen apps included), never moves, and can
/// become key (so the goal field is typeable) without activating the app or
/// stealing focus from whatever you're working in.
final class NotchPanel: NSPanel {
    var onReturnKey: (() -> Void)?
    var onSpaceKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Two above the status bar: over the menu bar and its item highlights,
        // still under pop-up menus, which rightly cover everything.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // SwiftUI draws the island's own shadow
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
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
