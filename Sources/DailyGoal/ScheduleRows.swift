import AppKit

/// The schedule, laid into the menu itself rather than hidden behind a
/// disclosure arrow: the week as seven dots you click, the hours as two clock
/// fields. Seeing which days are on *is* the setting, so a submenu would hide
/// the only thing worth showing.
///
/// Menu item views own their drawing and their mouse handling, which is what
/// lets a click land on a dot instead of dismissing the menu. Keyboard input
/// belongs to the menu's own tracking loop, so both rows are built to be
/// worked entirely with the mouse.
enum ScheduleRow {
    /// Wide enough that these rows set the menu's width, so their controls
    /// line up with its right edge.
    static let width: CGFloat = 272
    /// Where a menu item's title sits, so these rows share its text column.
    static let leading: CGFloat = 22
    static let trailing: CGFloat = 15
    static let height: CGFloat = 30

    static func label(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
    }
}

// MARK: - Days

/// "Days  Ⓜ Ⓣ Ⓦ Ⓣ Ⓕ Ⓢ Ⓢ" — filled where the day carries a goal. The week
/// starts where this locale starts it, lettered the way it letters it.
final class DayDotsView: NSView {
    private let store: GoalStore
    private let onChange: () -> Void
    private let order: [Int]        // weekday numbers, in locale order
    private let letters: [String]
    private var hovered = -1

    private let dot: CGFloat = 22
    private let gap: CGFloat = 5

    init(store: GoalStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        let calendar = Calendar.current
        order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let symbols = calendar.veryShortWeekdaySymbols
        letters = order.map { symbols[$0 - 1] }
        super.init(frame: NSRect(x: 0, y: 0, width: ScheduleRow.width, height: ScheduleRow.height))
        toolTip = "The days that carry a goal — click one to turn it on or off"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var stripWidth: CGFloat {
        CGFloat(order.count) * dot + CGFloat(order.count - 1) * gap
    }

    private func dotRect(_ index: Int) -> NSRect {
        NSRect(
            x: bounds.maxX - ScheduleRow.trailing - stripWidth + CGFloat(index) * (dot + gap),
            y: (bounds.height - dot) / 2,
            width: dot, height: dot)
    }

    override func draw(_ dirtyRect: NSRect) {
        let label = ScheduleRow.label("Days")
        label.draw(at: NSPoint(x: ScheduleRow.leading,
                               y: (bounds.height - label.size().height) / 2))

        let letterFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        for (index, weekday) in order.enumerated() {
            let on = store.schedule.isActive(weekday: weekday)
            let rect = dotRect(index)
            let fill: NSColor = on
                ? .controlAccentColor
                : NSColor.tertiaryLabelColor.withAlphaComponent(hovered == index ? 0.32 : 0.18)
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            // A ring on hover, so the dots read as buttons before they're tried.
            if hovered == index {
                NSColor.labelColor.withAlphaComponent(0.35).setStroke()
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5))
                ring.lineWidth = 1.5
                ring.stroke()
            }
            let letter = NSAttributedString(string: letters[index], attributes: [
                .font: letterFont,
                .foregroundColor: on
                    ? NSColor.alternateSelectedControlTextColor
                    : NSColor.secondaryLabelColor,
            ])
            let size = letter.size()
            letter.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    // Handling the click here is what keeps the menu open: no menu item is
    // chosen, so nothing dismisses, and the whole week can be set in one go.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = (0..<order.count).first(where: {
            dotRect($0).insetBy(dx: -2, dy: -2).contains(point)
        }) else { return }
        store.toggleActiveDay(order[index])
        needsDisplay = true
        onChange()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { trackHover(event) }
    override func mouseMoved(with event: NSEvent) { trackHover(event) }

    override func mouseExited(with event: NSEvent) {
        if hovered != -1 { hovered = -1; needsDisplay = true }
    }

    private func trackHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = (0..<order.count).first { dotRect($0).insetBy(dx: -2, dy: -2).contains(point) } ?? -1
        if index != hovered { hovered = index; needsDisplay = true }
    }
}

// MARK: - Hours

/// "Between  09:00 – 18:00" — the stretch of an active day the goal is live
/// for. Both ends equal means the whole day, which is where it starts: the
/// app's own 4 a.m. → 4 a.m.
final class ActiveHoursView: NSView {
    private let store: GoalStore
    private let onChange: () -> Void
    private let from = NSDatePicker()
    private let to = NSDatePicker()
    private let dash = NSTextField(labelWithString: "–")

    init(store: GoalStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: ScheduleRow.width, height: ScheduleRow.height))

        dash.font = NSFont.menuFont(ofSize: 0)
        dash.textColor = .secondaryLabelColor
        dash.sizeToFit()
        addSubview(dash)

        for picker in [from, to] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.calendar = Calendar.current
            picker.locale = .current
            picker.target = self
            picker.action = #selector(timeChanged)
            picker.sizeToFit()
            addSubview(picker)
        }

        layOut()
        refresh()
        toolTip = "The hours an active day's goal is live — the ring fills across"
            + " them. Leave it at 4:00 – 4:00 for the whole day."
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let label = ScheduleRow.label("Between")
        label.draw(at: NSPoint(x: ScheduleRow.leading,
                               y: (bounds.height - label.size().height) / 2))
    }

    private func layOut() {
        let mid = bounds.midY
        func place(_ view: NSView, right: CGFloat) {
            view.setFrameOrigin(NSPoint(x: right - view.frame.width, y: mid - view.frame.height / 2))
        }
        place(to, right: bounds.maxX - ScheduleRow.trailing)
        place(dash, right: to.frame.minX - 6)
        place(from, right: dash.frame.minX - 6)
    }

    /// Pulls the fields back in line with the store.
    func refresh() {
        from.dateValue = Self.date(minutes: store.schedule.startMinutes)
        to.dateValue = Self.date(minutes: store.schedule.endMinutes)
    }

    @objc private func timeChanged() {
        store.setActiveHours(start: Self.minutes(of: from), end: Self.minutes(of: to))
        onChange()
    }

    private static func date(minutes: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2001
        parts.month = 1
        parts.day = 1
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return Calendar.current.date(from: parts) ?? Date()
    }

    private static func minutes(of picker: NSDatePicker) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
