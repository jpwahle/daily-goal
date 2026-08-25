import SwiftUI

/// The MacBook notch outline: straight across the screen edge, curving
/// *outward* at the top corners (the little "ears" where the housing meets
/// the menu bar) and *inward* at the bottom corners. Filled black and drawn
/// flush with the screen's top edge, it is indistinguishable from the
/// physical camera housing — which is exactly the point: the island should
/// look like the notch itself grew to hold your goal.
struct NotchShape: Shape {
    /// Radius of the concave top "ears".
    var earRadius: CGFloat
    /// Radius of the convex bottom corners.
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, cornerRadius) }
        set {
            earRadius = newValue.first
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + earRadius, y: rect.minY + earRadius),
            control: CGPoint(x: rect.minX + earRadius, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + earRadius, y: rect.maxY - cornerRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + earRadius + cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + earRadius, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - earRadius - cornerRadius, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - earRadius, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.maxX - earRadius, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - earRadius, y: rect.minY + earRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - earRadius, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
