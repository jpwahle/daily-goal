import SwiftUI
import Foundation

// MARK: - The notch island

/// One continuous black shape that extends the physical notch. Collapsed, two
/// wings sit at exact notch height — the day-progress ring left of the camera,
/// the goal right of it. Expanded, the notch grows into a card with the full
/// goal, streak, week dots, and inline editing. On screens without a notch the
/// island hangs from the top edge as a single centered capsule.
struct NotchIslandView: View {
    @ObservedObject var store: GoalStore
    @ObservedObject var notch: NotchController

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var celebrationGlow = false
    @State private var collapsedShift: CGFloat = 0

    private var expanded: Bool { notch.state == .expanded }

    /// Layout constants for the collapsed left wing. The wing must have a
    /// constant width: the island's off-center shift is derived from it.
    private enum Wing {
        static let ring: CGFloat = 15
        static let leadingPad: CGFloat = 12
        static let trailingPad: CGFloat = 7
        static var left: CGFloat { leadingPad + ring + trailingPad }
    }

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .onChange(of: store.isEditing) { editing in
                if editing {
                    draft = store.goal
                    notch.makeKeyPanel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { fieldFocused = true }
                } else {
                    fieldFocused = false
                }
            }
            .onChange(of: fieldFocused) { focused in
                // Clicking away while editing commits the draft.
                if !focused && store.isEditing { commit() }
            }
            .onChange(of: store.celebrationTick) { _ in flashGlow() }
    }

    private var island: some View {
        ZStack(alignment: .top) {
            if expanded {
                expandedCard.transition(.opacity)
            } else {
                collapsedRow.transition(.opacity)
            }
        }
        .background {
            let shape = NotchShape(
                earRadius: expanded ? 16 : 5,
                cornerRadius: expanded ? 22 : 10
            )
            ZStack {
                // The real notch casts no shadow, so neither may the island's
                // menu-bar band — a smudge beside the housing reads as a
                // glitch. The drop shadow only exists below the band.
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(expanded ? 0.40 : 0.30),
                            radius: expanded ? 14 : 5, y: expanded ? 6 : 2)
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: notch.notchSize.height)
                            Color.white.frame(width: 1000, height: 500)
                        }
                    }
                shape.fill(Color.black)
            }
        }
        .compositingGroup()
        // Celebration and nudge glows: a tight rim so they read on dark
        // wallpapers, plus a wide bloom for light ones.
        .shadow(color: .green.opacity(celebrationGlow ? 0.80 : 0), radius: 6)
        .shadow(color: .green.opacity(celebrationGlow ? 0.45 : 0), radius: 22)
        .shadow(color: Color(red: 0.45, green: 0.40, blue: 1.0)
            .opacity(notch.nudging ? 0.85 : 0), radius: 6)
        .shadow(color: Color(red: 0.45, green: 0.40, blue: 1.0)
            .opacity(notch.nudging ? 0.50 : 0), radius: 22)
        .background(GeometryReader { geo in
            // Preferences don't reliably propagate out of NSHostingView, so
            // report size changes through plain onChange instead.
            Color.clear
                .onAppear { notch.metrics.size = geo.size }
                .onChange(of: geo.size) { notch.metrics.size = $0 }
        })
        .offset(x: expanded ? 0 : collapsedShift)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: expanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.80), value: store.goal)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: store.isCompleted)
        .animation(.spring(response: 0.40, dampingFraction: 0.80), value: store.streak)
        .animation(.easeInOut(duration: 0.2), value: store.isEditing)
        .animation(.easeInOut(duration: 0.45), value: notch.nudging)
    }

    // MARK: - Collapsed: wings around the camera

    private var collapsedRow: some View {
        Group {
            if notch.hasNotch {
                HStack(spacing: 0) {
                    CheckRing(store: store, diameter: Wing.ring, interactive: false)
                        .padding(.leading, Wing.leadingPad)
                        .padding(.trailing, Wing.trailingPad)
                    // The camera housing: keep it untouched black.
                    Color.clear.frame(width: notch.notchSize.width, height: 1)
                    wingLabel
                        .padding(.leading, 9)
                        .padding(.trailing, 14)
                }
            } else {
                HStack(spacing: 8) {
                    CheckRing(store: store, diameter: Wing.ring, interactive: false)
                    wingLabel
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(height: notch.notchSize.height)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { reportCollapsedWidth(geo.size.width) }
                .onChange(of: geo.size.width) { reportCollapsedWidth($0) }
        })
    }

    /// The wings differ in width, so centering the island would drag the
    /// camera gap off the actual camera. Shift the island so the gap stays
    /// exactly on the notch.
    private func reportCollapsedWidth(_ width: CGFloat) {
        let shift = notch.hasNotch
            ? width / 2 - Wing.left - notch.notchSize.width / 2
            : 0
        collapsedShift = shift
        notch.metrics.collapsedShift = shift
    }

    @ViewBuilder private var wingLabel: some View {
        if store.goal.isEmpty {
            // Gentle breathing invite until a goal exists.
            TimelineView(.animation(minimumInterval: 0.08)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Text("Set today's goal")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42 + 0.16 * sin(t * 1.5)))
            }
            .lineLimit(1)
        } else {
            HStack(spacing: 6) {
                Text(store.goal)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white.opacity(store.isCompleted ? 0.45 : 0.92))
                    .strikethrough(store.isCompleted, color: .white.opacity(0.45))
                    // The wing hugs the goal but never grows past the cap.
                    // SwiftUI's maxWidth would pin it *at* the cap, so measure
                    // the text and set the width outright.
                    .frame(width: min(wingTextWidth, 180), alignment: .leading)
                if store.streak >= 2 {
                    miniStreak
                }
            }
        }
    }

    /// Width of the goal in the wing's font, so the collapsed island can hug
    /// short goals instead of reserving the full cap.
    private var wingTextWidth: CGFloat {
        measuredWidth(store.goal, size: 12, weight: .semibold)
    }

    /// Single-line width of `text` in the island's rounded system font.
    /// SwiftUI's maxWidth would pin frames *at* the cap, so hug-with-cap
    /// layouts measure the text and set widths outright.
    private func measuredWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: size) } ?? base
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
    }

    private var miniStreak: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(store.streak)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .foregroundStyle(LinearGradient(
            colors: [.orange, Color(red: 1.0, green: 0.42, blue: 0.20)],
            startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Expanded: the card below the notch

    /// Card metrics. Vertical rhythm: content hugs the housing the way the
    /// iPhone's expanded island hugs its sensor band — a snug gap right under
    /// the notch, then room to breathe toward a slightly heavier bottom.
    /// Horizontally the card hugs its content: a short goal gets a snug card
    /// barely wider than the housing, a long one grows to the cap and wraps.
    private enum Card {
        static let hpad: CGFloat = 26
        static let ring: CGFloat = 24
        static let gap: CGFloat = 12
        static let textCap: CGFloat = 240
        static let max: CGFloat = 400
    }

    private var expandedWidth: CGFloat {
        // A stable width while typing, so the field doesn't chase every key.
        if store.isEditing { return 360 }
        let floor = notch.notchSize.width + 72 // clear the ears, hug the housing
        var content = Card.ring + Card.gap
        if store.goal.isEmpty {
            content += measuredWidth("What's your one thing today?", size: 15, weight: .medium)
        } else {
            content += min(measuredWidth(store.goal, size: 15, weight: .semibold), Card.textCap)
            if store.streak >= 2 {
                content += Card.gap + 36 + CGFloat(String(store.streak).count) * 7
            }
        }
        return min(Swift.max(content + Card.hpad * 2, floor), Card.max)
    }

    private var expandedCard: some View {
        VStack(spacing: 13) {
            HStack(spacing: Card.gap) {
                CheckRing(store: store, diameter: Card.ring, interactive: true)
                centerContent
                if store.streak >= 2 && !store.isEditing {
                    StreakChip(count: store.streak)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            footer
        }
        .padding(.top, notch.notchSize.height + 8)
        .padding(.horizontal, Card.hpad)
        .padding(.bottom, 16)
        .frame(width: expandedWidth)
        .overlay(alignment: .topLeading) {
            // Anchored at the check ring's center so confetti erupts from it.
            ConfettiBurst(tick: store.celebrationTick)
                .offset(x: Card.hpad + Card.ring / 2, y: notch.notchSize.height + 8 + Card.ring / 2)
        }
    }

    @ViewBuilder private var centerContent: some View {
        if store.isEditing {
            TextField("One thing for today…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onChange(of: draft) { value in
                    if value.count > 100 { draft = String(value.prefix(100)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.goal.isEmpty {
            Text("What's your one thing today?")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { notch.beginEditing() }
        } else {
            Text(store.goal)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white.opacity(store.isCompleted ? 0.50 : 0.95))
                .strikethrough(store.isCompleted, color: .white.opacity(0.50))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { notch.beginEditing() }
                .help("Click to edit")
        }
    }

    @ViewBuilder private var footer: some View {
        if store.isEditing {
            Text("return to save · esc to cancel")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 0) {
                    WeekDots(states: store.weekStates())
                    Spacer()
                    Text(caption(at: context.date))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(captionColor(at: context.date))
                }
            }
        }
    }

    private func caption(at date: Date) -> String {
        if store.goal.isEmpty { return "days end at 4 a.m." }
        if store.isCompleted { return "resets at 4 a.m." }
        let left = store.secondsLeft(at: date)
        if left < 3600 { return "\(max(1, Int(left / 60)))m left" }
        return "\(Int(left / 3600))h left"
    }

    private func captionColor(at date: Date) -> Color {
        guard !store.isCompleted, !store.goal.isEmpty else { return .white.opacity(0.40) }
        let left = store.secondsLeft(at: date)
        if left < 3600 { return .red.opacity(0.85) }
        if left < 3 * 3600 { return .orange.opacity(0.85) }
        return .white.opacity(0.40)
    }

    // MARK: - Editing

    private func commit() {
        store.setGoal(draft)
        store.isEditing = false
    }

    private func cancel() {
        store.isEditing = false
    }

    private func flashGlow() {
        withAnimation(.easeOut(duration: 0.25)) { celebrationGlow = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeInOut(duration: 0.9)) { celebrationGlow = false }
        }
    }
}

// MARK: - Last-7-days dots

private struct WeekDots: View {
    let states: [DayState]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                dot(for: state)
            }
        }
        .help("Last 7 days — today is the last dot")
    }

    @ViewBuilder private func dot(for state: DayState) -> some View {
        switch state {
        case .done:
            Circle().fill(Color(red: 0.25, green: 0.78, blue: 0.47))
                .frame(width: 5, height: 5)
        case .missed:
            Circle().fill(.white.opacity(0.22))
                .frame(width: 5, height: 5)
        case .pending:
            Circle().strokeBorder(Color(red: 0.40, green: 0.60, blue: 1.0), lineWidth: 1.2)
                .frame(width: 6, height: 6)
        case .empty:
            Circle().fill(.white.opacity(0.10))
                .frame(width: 5, height: 5)
        }
    }
}

// MARK: - Check ring: day-progress dial that becomes a green check

/// Used at two sizes: a small passive dial in the collapsed wing, and the
/// full interactive button in the expanded card. All strokes scale with the
/// diameter so both read identically.
struct CheckRing: View {
    @ObservedObject var store: GoalStore
    var diameter: CGFloat = 22
    var interactive = true

    private let accent = LinearGradient(
        colors: [Color(red: 0.33, green: 0.45, blue: 1.0), Color(red: 0.66, green: 0.35, blue: 0.99)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        if interactive {
            Button {
                store.toggleCompleted()
            } label: {
                ring
            }
            .buttonStyle(PressableStyle())
            .disabled(store.goal.isEmpty)
            .help(helpText)
        } else {
            ring
        }
    }

    private var ring: some View {
        let line = diameter * 0.11
        return ZStack {
            if store.isCompleted {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.22, green: 0.80, blue: 0.45), Color(red: 0.10, green: 0.65, blue: 0.52)],
                        startPoint: .top, endPoint: .bottom))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.48, weight: .heavy))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let progress = store.dayProgress(at: context.date)
                    let left = store.secondsLeft(at: context.date)
                    ZStack {
                        if store.goal.isEmpty {
                            Circle().strokeBorder(
                                .white.opacity(0.30),
                                style: StrokeStyle(lineWidth: line * 0.8,
                                                   dash: [diameter * 0.12, diameter * 0.14]))
                        } else {
                            Circle().strokeBorder(.white.opacity(0.16), lineWidth: line)
                        }
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(ringStyle(secondsLeft: left),
                                    style: StrokeStyle(lineWidth: line, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(line / 2) // align centered stroke with inset strokeBorder
                    }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }

    private func ringStyle(secondsLeft: TimeInterval) -> AnyShapeStyle {
        if secondsLeft < 3600 { return AnyShapeStyle(Color.red) }
        if secondsLeft < 3 * 3600 { return AnyShapeStyle(Color.orange) }
        return AnyShapeStyle(accent)
    }

    private var helpText: String {
        if store.goal.isEmpty { return "Set a goal first" }
        return store.isCompleted ? "Done — click to undo" : "Mark as done"
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - Streak chip

struct StreakChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
            Text("\(count)")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .foregroundStyle(LinearGradient(
            colors: [.orange, Color(red: 1.0, green: 0.42, blue: 0.20)],
            startPoint: .top, endPoint: .bottom))
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(Color.orange.opacity(0.18)))
        .help("\(count)-day streak — complete today to keep it alive")
    }
}

// MARK: - Confetti

struct ConfettiBurst: View {
    let tick: Int
    @State private var pieces: [Piece] = []
    @State private var flying = false

    struct Piece: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: Double
        let size: Double
        let spin: Double
        let color: Color
        let isRound: Bool
    }

    private static let palette: [Color] = [.green, .mint, .yellow, .orange, .pink, .purple, .blue]

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                shape(for: piece)
                    .frame(width: piece.size, height: piece.isRound ? piece.size : piece.size * 0.55)
                    .rotationEffect(.degrees(flying ? piece.spin : 0))
                    .offset(x: flying ? cos(piece.angle) * piece.distance : 0,
                            y: flying ? sin(piece.angle) * piece.distance + 14 : 0)
                    .scaleEffect(flying ? 0.4 : 1)
                    .opacity(flying ? 0 : 1)
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .onChange(of: tick) { value in
            guard value > 0 else { return }
            fire()
        }
    }

    @ViewBuilder private func shape(for piece: Piece) -> some View {
        if piece.isRound {
            Circle().fill(piece.color)
        } else {
            RoundedRectangle(cornerRadius: 1).fill(piece.color)
        }
    }

    private func fire() {
        pieces = (0..<18).map { _ in
            Piece(angle: Double.random(in: -Double.pi ... Double.pi),
                  distance: Double.random(in: 26...60),
                  size: Double.random(in: 4...7),
                  spin: Double.random(in: -260...260),
                  color: Self.palette.randomElement() ?? .green,
                  isRound: Bool.random())
        }
        flying = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.9)) { flying = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            pieces = []
            flying = false
        }
    }
}
