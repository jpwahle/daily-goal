import SwiftUI

/// The MacBook notch outline: straight across the screen edge, curving
/// *outward* at the top corners (the little "ears" where the housing meets
/// the menu bar) and *inward* at the bottom corners. Filled black and drawn
/// flush with the screen's top edge, it is indistinguishable from the
/// physical camera housing — which is exactly the point: the island should
/// look like the notch itself grew to hold your goal.
///
/// With `flare` raised, the shape becomes a hanging tray: a neck no wider
/// than `neckWidth` passes through the menu bar band (`neckHeight` deep) and
/// opens — through concave fillets, the notch's ear language upside down —
/// onto a rounded card whose top edge sits just below the bar. The card can
/// be any width because none of it lives in the bar, where every point
/// beside the notch may belong to someone's status item.
struct NotchShape: Shape {
    /// Radius of the concave top "ears".
    var earRadius: CGFloat
    /// Radius of the convex bottom corners.
    var cornerRadius: CGFloat
    /// 0 = one slab spanning the full width (the collapsed wings);
    /// 1 = neck through the bar, card hanging below it.
    var flare: CGFloat = 0
    var neckWidth: CGFloat = 0
    var neckHeight: CGFloat = 0

    /// The concave turn where the neck opens onto the card's top edge.
    static let filletRadius: CGFloat = 12
    /// The card's convex top corners.
    static let topCornerRadius: CGFloat = 18
    /// How far below the menu bar the card's top edge hangs — exactly the
    /// fillet's height. Content must stay below this line.
    static var cardTopDrop: CGFloat { filletRadius }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(earRadius, cornerRadius), AnimatablePair(flare, neckWidth)) }
        set {
            earRadius = newValue.first.first
            cornerRadius = newValue.first.second
            flare = newValue.second.first
            neckWidth = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // At flare 0 every expanded-only stop degenerates onto the slab's
        // straight sides, so one path serves both states and every frame
        // in between.
        let t = min(max(flare, 0), 1)
        let inset = t * max(0, (rect.width - neckWidth) / 2)
        let nxL = rect.minX + inset          // neck outer edges
        let nxR = rect.maxX - inset
        let x0L = nxL + earRadius            // neck walls, inside the ears
        let x0R = nxR - earRadius
        let f = t * Self.filletRadius
        let tc = t * Self.topCornerRadius
        let sideL = rect.minX + (1 - t) * earRadius // slab keeps its ear inset
        let sideR = rect.maxX - (1 - t) * earRadius
        let neckY = rect.minY + neckHeight
        let topY = neckY + f                 // the card's top edge

        var p = Path()
        p.move(to: CGPoint(x: nxL, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: x0L, y: rect.minY + earRadius),
            control: CGPoint(x: x0L, y: rect.minY))
        p.addLine(to: CGPoint(x: x0L, y: neckY))
        p.addQuadCurve( // concave fillet onto the top edge
            to: CGPoint(x: x0L - f, y: topY),
            control: CGPoint(x: x0L, y: topY))
        p.addLine(to: CGPoint(x: sideL + tc, y: topY))
        p.addQuadCurve( // convex top corner
            to: CGPoint(x: sideL, y: topY + tc),
            control: CGPoint(x: sideL, y: topY))
        p.addLine(to: CGPoint(x: sideL, y: rect.maxY - cornerRadius))
        p.addQuadCurve(
            to: CGPoint(x: sideL + cornerRadius, y: rect.maxY),
            control: CGPoint(x: sideL, y: rect.maxY))
        p.addLine(to: CGPoint(x: sideR - cornerRadius, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: sideR, y: rect.maxY - cornerRadius),
            control: CGPoint(x: sideR, y: rect.maxY))
        p.addLine(to: CGPoint(x: sideR, y: topY + tc))
        p.addQuadCurve(
            to: CGPoint(x: sideR - tc, y: topY),
            control: CGPoint(x: sideR, y: topY))
        p.addLine(to: CGPoint(x: x0R + f, y: topY))
        p.addQuadCurve(
            to: CGPoint(x: x0R, y: neckY),
            control: CGPoint(x: x0R, y: topY))
        p.addLine(to: CGPoint(x: x0R, y: rect.minY + earRadius))
        p.addQuadCurve(
            to: CGPoint(x: nxR, y: rect.minY),
            control: CGPoint(x: x0R, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
