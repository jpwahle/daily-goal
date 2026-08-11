// Fullscreen gradient backdrop for marketing screenshots, matching the
// landing-page palette. The pill panel (window level 25) floats above it.
//
//   swift Scripts/ShotBackdrop.swift light|dark
//
// Runs until killed.
import AppKit

final class BackdropView: NSView {
    let dark: Bool
    init(frame: NSRect, dark: Bool) {
        self.dark = dark
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height

        let top: NSColor, bottom: NSColor, indigo: NSColor, violet: NSColor
        if dark {
            top = NSColor(srgbRed: 0.100, green: 0.094, blue: 0.118, alpha: 1)
            bottom = NSColor(srgbRed: 0.075, green: 0.071, blue: 0.090, alpha: 1)
            indigo = NSColor(srgbRed: 0.42, green: 0.40, blue: 0.95, alpha: 0.20)
            violet = NSColor(srgbRed: 0.62, green: 0.36, blue: 0.92, alpha: 0.16)
        } else {
            top = NSColor(srgbRed: 0.984, green: 0.980, blue: 0.992, alpha: 1)
            bottom = NSColor(srgbRed: 0.948, green: 0.940, blue: 0.972, alpha: 1)
            indigo = NSColor(srgbRed: 0.45, green: 0.42, blue: 0.98, alpha: 0.16)
            violet = NSColor(srgbRed: 0.66, green: 0.38, blue: 0.95, alpha: 0.13)
        }

        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)

        // Two soft color blobs, like the site's hero field.
        NSGradient(starting: indigo, ending: indigo.withAlphaComponent(0))?
            .draw(fromCenter: NSPoint(x: w * 0.30, y: h * 0.62), radius: 0,
                  toCenter: NSPoint(x: w * 0.30, y: h * 0.62), radius: w * 0.34, options: [])
        NSGradient(starting: violet, ending: violet.withAlphaComponent(0))?
            .draw(fromCenter: NSPoint(x: w * 0.72, y: h * 0.42), radius: 0,
                  toCenter: NSPoint(x: w * 0.72, y: h * 0.42), radius: w * 0.36, options: [])
    }
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "light"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.main else { exit(1) }
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                      backing: .buffered, defer: false)
window.level = NSWindow.Level(rawValue: 23) // above app windows, below the pill panel
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
window.contentView = BackdropView(frame: screen.frame, dark: mode == "dark")
window.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
window.orderFrontRegardless()

app.run()
