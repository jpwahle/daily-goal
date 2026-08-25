// Moves the cursor to the bottom-center of the main screen so it can't
// hover-expand the notch island while screenshots are being staged.
import AppKit
import CoreGraphics

guard let screen = NSScreen.main else { exit(1) }
CGWarpMouseCursorPosition(CGPoint(x: screen.frame.midX, y: screen.frame.height - 8))
