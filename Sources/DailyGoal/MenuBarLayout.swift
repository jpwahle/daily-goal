import AppKit

/// Free room in the menu bar on either side of the notch, in points.
struct BarGaps: Equatable {
    var left: CGFloat = 10_000
    var right: CGFloat = 10_000
}

/// Where the menu bar's status items currently sit. The island must never
/// cover one — neither the system's nor those a manager like Bartender or
/// Hidden Bar shuffles in and out — so before the wings take any space, this
/// measures how much of the bar beside the notch is actually free.
enum MenuBarLayout {
    struct Scan {
        var gaps = BarGaps()
        /// An item sits inside the notch rect itself. Only meaningful on
        /// no-notch screens, where nothing reserves the virtual island's
        /// spot; under a physical notch there are no pixels and no items.
        var notchIntruded = false
    }

    /// Status items are ordinary windows at the status-bar level, so their
    /// frames are readable without any permission — third-party ones
    /// included. Managers hide items by parking them far off screen, which
    /// the on-screen-only listing naturally skips: the scan sees exactly
    /// what the user sees, and catches a reveal on the next pass.
    static func scan(around notch: NSRect, on screen: NSScreen, physicalNotch: Bool) -> Scan {
        var result = Scan()
        result.gaps = BarGaps(
            left: notch.minX - screen.frame.minX,
            right: screen.frame.maxX - notch.maxX)

        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return result }

        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let barDepth = max(notch.height, screen.frame.maxY - screen.visibleFrame.maxY) + 2
        let band = NSRect(
            x: screen.frame.minX, y: screen.frame.maxY - barDepth,
            width: screen.frame.width, height: barDepth)

        for window in windows {
            guard window[kCGWindowLayer as String] as? Int == statusLevel,
                  (window[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0.05,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"]
            else { continue }
            // CG frames hang from the top-left of the primary screen;
            // AppKit measures from its bottom-left.
            let item = NSRect(x: x, y: primary.frame.maxY - y - h, width: w, height: h)
            guard item.width < screen.frame.width / 2, item.intersects(band) else { continue }

            if item.maxX <= notch.minX {
                result.gaps.left = min(result.gaps.left, notch.minX - item.maxX)
            } else if item.minX >= notch.maxX {
                result.gaps.right = min(result.gaps.right, item.minX - notch.maxX)
            } else {
                // Poking out from under the notch: the sliver beside the
                // housing is visible, so that side of the bar is taken.
                if item.minX < notch.minX { result.gaps.left = 0 }
                if item.maxX > notch.maxX { result.gaps.right = 0 }
                if !physicalNotch { result.notchIntruded = true }
            }
        }
        result.gaps.left = max(0, floor(result.gaps.left))
        result.gaps.right = max(0, floor(result.gaps.right))
        return result
    }
}
