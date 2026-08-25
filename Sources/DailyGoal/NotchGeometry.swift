import AppKit

extension NSScreen {
    /// The built-in display when present, else whatever is main. The island
    /// lives on this screen: on MacBooks it hugs the physical notch; on
    /// external-only setups it hangs from the top edge as a virtual island.
    static var islandScreen: NSScreen? {
        screens.first(where: { $0.isBuiltinDisplay }) ?? main ?? screens.first
    }

    var isBuiltinDisplay: Bool {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }

    /// Size of the physical camera housing, measured from the system so it is
    /// exact on every notched Mac. Screens without a notch get a virtual one
    /// sized like the real thing (capped near the menu bar height).
    var notchArea: CGSize {
        if hasNotch,
           let left = auxiliaryTopLeftArea?.width,
           let right = auxiliaryTopRightArea?.width,
           left > 0, right > 0 {
            return CGSize(width: frame.width - left - right, height: safeAreaInsets.top)
        }
        let menuBar = frame.maxY - visibleFrame.maxY
        return CGSize(width: 190, height: min(max(menuBar, 26), 34))
    }
}
