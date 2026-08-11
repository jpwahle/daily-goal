import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar app: no Dock icon, no main menu

// DG_APPEARANCE=light|dark pins the appearance regardless of the system
// theme — used by Scripts/make-shots.sh to capture both screenshot variants.
if let forced = ProcessInfo.processInfo.environment["DG_APPEARANCE"] {
    app.appearance = NSAppearance(named: forced == "dark" ? .darkAqua : .aqua)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
