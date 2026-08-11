import SwiftUI
import Foundation

// MARK: - The floating goal pill

struct GoalView: View {
    @ObservedObject var store: GoalStore
    let bridge: PanelBridge

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    @State private var hovering = false
    @StateObject private var idle = IdleDimmer()
    @State private var shownOpacity: Double = 1
    @State private var glow = false
    @State private var nudgeOffset: CGFloat = 0
    @State private var nudgeGlow = false

    var body: some View {
        pill
            .padding(Layout.margin)
            .background(GeometryReader { geo in
                Color.clear.preference(key: PillSizeKey.self, value: geo.size)
            })
            .onPreferenceChange(PillSizeKey.self) { bridge.contentSizeChanged($0) }
            .onHover { over in
                hovering = over
                idle.poke()
                updateOpacity()
            }
            .onAppear { updateOpacity() }
            .onChange(of: idle.dimmed) { _ in updateOpacity() }
            .onChange(of: store.isEditing) { editing in
                if editing {
                    draft = store.goal
                    bridge.makeKeyPanel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { fieldFocused = true }
                } else {
                    fieldFocused = false
                }
                idle.poke()
                updateOpacity()
            }
            .onChange(of: fieldFocused) { focused in
                // Clicking away while editing commits the draft.
                if !focused && store.isEditing { commit() }
            }
            .onChange(of: store.goal) { _ in idle.poke(); updateOpacity() }
            .onChange(of: store.isCompleted) { _ in idle.poke(); updateOpacity() }
            .onChange(of: store.celebrationTick) { _ in flashGlow() }
            .onChange(of: store.nudgeTick) { _ in nudge() }
    }

    private var pill: some View {
        HStack(spacing: 10) {
            CheckRing(store: store)
            centerContent
            if store.streak >= 2 {
                StreakChip(count: store.streak)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 15)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(strokeTint, lineWidth: 1))
        .overlay(alignment: .leading) {
            // Anchored at the check ring's center so confetti erupts from it.
            ConfettiBurst(tick: store.celebrationTick)
                .offset(x: 13 + 11)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.20), radius: 14, y: 6)
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        .shadow(color: .green.opacity(glow ? 0.55 : 0), radius: 18)
        .shadow(color: Color(red: 0.45, green: 0.40, blue: 1.0).opacity(nudgeGlow ? 0.65 : 0), radius: 20)
        .opacity(shownOpacity)
        .offset(y: nudgeOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: store.isCompleted)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.streak)
        .animation(.easeInOut(duration: 0.2), value: store.isEditing)
        .fixedSize()
        .gesture(
            TapGesture().onEnded {
                if store.goal.isEmpty && !store.isEditing { store.isEditing = true }
            },
            including: store.goal.isEmpty && !store.isEditing ? .all : .subviews
        )
    }

    @ViewBuilder private var centerContent: some View {
        if store.isEditing {
            TextField("One thing for today…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 250)
                .focused($fieldFocused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onChange(of: draft) { value in
                    if value.count > 100 { draft = String(value.prefix(100)) }
                }
        } else if store.goal.isEmpty {
            // Gentle breathing invite until a goal exists.
            TimelineView(.animation(minimumInterval: 0.08)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Text("What's your one thing today?")
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(0.66 + 0.28 * sin(t * 1.5))
            }
        } else {
            GoalLabel(text: store.goal, done: store.isCompleted)
                .contentShape(Rectangle())
                .onTapGesture { store.isEditing = true }
                .help("Click to edit")
        }
    }

    private var strokeTint: AnyShapeStyle {
        store.isEditing
            ? AnyShapeStyle(Color.accentColor.opacity(0.5))
            : AnyShapeStyle(Color.primary.opacity(0.10))
    }

    // MARK: - Idle dimming (quick to brighten, slow to fade)

    private var targetOpacity: Double {
        if store.isEditing || hovering || store.goal.isEmpty { return 1 }
        guard idle.dimmed else { return 1 }
        return store.isCompleted ? 0.30 : 0.55
    }

    private func updateOpacity() {
        let target = targetOpacity
        guard abs(target - shownOpacity) > 0.001 else { return }
        withAnimation(target > shownOpacity
                      ? .easeOut(duration: 0.18)
                      : .easeInOut(duration: 1.2)) {
            shownOpacity = target
        }
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
        withAnimation(.easeOut(duration: 0.25)) { glow = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeInOut(duration: 0.9)) { glow = false }
        }
    }

    // MARK: - Reminder nudge: wake, glow violet, and hop twice

    private func nudge() {
        idle.poke()
        updateOpacity()
        withAnimation(.easeOut(duration: 0.2)) { nudgeGlow = true }

        let hop = Animation.spring(response: 0.18, dampingFraction: 0.55)
        let land = Animation.spring(response: 0.26, dampingFraction: 0.5)
        withAnimation(hop) { nudgeOffset = -16 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(land) { nudgeOffset = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(hop) { nudgeOffset = -9 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            withAnimation(land) { nudgeOffset = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.9)) { nudgeGlow = false }
        }
    }
}

struct PillSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Goal text with animated strikethrough

private struct GoalLabel: View {
    let text: String
    let done: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(maxWidth: 340, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(.secondary)
                        .frame(width: done ? geo.size.width : 0, height: 1.5)
                        .offset(y: geo.size.height / 2 - 0.75)
                }
                .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.35).delay(done ? 0.1 : 0), value: done)
    }
}

// MARK: - Check ring: day-progress dial that becomes a green check

private struct CheckRing: View {
    @ObservedObject var store: GoalStore

    private let accent = LinearGradient(
        colors: [Color(red: 0.33, green: 0.45, blue: 1.0), Color(red: 0.66, green: 0.35, blue: 0.99)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        Button {
            store.toggleCompleted()
        } label: {
            ZStack {
                if store.isCompleted {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.22, green: 0.80, blue: 0.45), Color(red: 0.10, green: 0.65, blue: 0.52)],
                            startPoint: .top, endPoint: .bottom))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let progress = store.dayProgress(at: context.date)
                        let left = store.secondsLeft(at: context.date)
                        ZStack {
                            if store.goal.isEmpty {
                                Circle().strokeBorder(
                                    Color.primary.opacity(0.22),
                                    style: StrokeStyle(lineWidth: 2, dash: [2.5, 3]))
                            } else {
                                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 2.5)
                            }
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(ringStyle(secondsLeft: left),
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .padding(1.25) // align centered stroke with inset strokeBorder
                        }
                    }
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(store.goal.isEmpty)
        .help(helpText)
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

private struct StreakChip: View {
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
        .background(Capsule().fill(Color.orange.opacity(0.15)))
        .help("\(count)-day streak — complete today to keep it alive")
    }
}

// MARK: - Confetti

private struct ConfettiBurst: View {
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

// MARK: - Idle dimmer

final class IdleDimmer: ObservableObject {
    @Published var dimmed = false
    private var lastActivity = Date()
    private var timer: Timer?
    private let delay: TimeInterval = 8

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let shouldDim = Date().timeIntervalSince(self.lastActivity) > self.delay
            if shouldDim != self.dimmed { self.dimmed = shouldDim }
        }
        timer?.tolerance = 0.3
    }

    func poke() {
        lastActivity = Date()
        if dimmed { dimmed = false }
    }

    deinit {
        timer?.invalidate()
    }
}
