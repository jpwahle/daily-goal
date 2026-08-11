import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar app: no Dock icon, no main menu
let delegate = AppDelegate()
app.delegate = delegate
app.run()
