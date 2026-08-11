// Prints "x y w h" of the on-screen Daily Goal pill window (top-left origin,
// points — the same space `screencapture -R` uses). Exits 1 when not found.
import CoreGraphics
import Foundation

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for info in list {
    guard let owner = info[kCGWindowOwnerName as String] as? String,
          owner == "DailyGoal" || owner == "Daily Goal",
          let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
          let x = bounds["X"], let y = bounds["Y"],
          let w = bounds["Width"], let h = bounds["Height"],
          w > 200 // the status-bar item is a small window; the pill is wide
    else { continue }
    print("\(Int(x)) \(Int(y)) \(Int(w)) \(Int(h))")
    exit(0)
}
exit(1)
