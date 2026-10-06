import AppKit
import SwiftUI
import TimerCore

/// The countdown screen: a port of the web timer's `.timer` page (see timer.html.erb).
struct CountdownView: View {
    @ObservedObject var controller: TimerController
    @ObservedObject var clock: ClockModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var hasFocus: Bool
    @State private var isIdle = false
    @State private var idleTask: Task<Void, Never>?
    @State private var viewSize: CGSize = .zero
    @State private var zoomLabel: String?
    @State private var zoomLabelTask: Task<Void, Never>?
    /// Where the pointer is along the progress bar, while it is over it.
    @State private var barHoverX: CGFloat?
    /// An action that is easy to trigger by accident (a stray click, a presenter remote) and
    /// costly to undo waits for a second press: reset after time is up, and Esc while counting.
    @State private var armed: ArmedAction?
    @State private var armTask: Task<Void, Never>?
    @AppStorage(AppSettings.countdownZoom) private var zoom = 1.0

    private var snap: TimerEngine.Snapshot { clock.snapshot }
    private var config: TimerConfig { controller.config }
    private var palette: Palette { Palette.make(config.theme, accent: AccentColor(config: config)) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimerBackground(palette: palette)
                HeatGlow(palette: palette, heat: snap.heat, expired: snap.isExpired)
                stage(in: geo.size)
                progressBar(size: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size, initial: true) { _, size in viewSize = size }
        }
        .overlay(alignment: .top) { zoomBadge.animation(.easeInOut(duration: 0.2), value: zoomLabel) }
        .overlay(alignment: .bottom) { armedPrompt.animation(.easeInOut(duration: 0.2), value: armed) }
        .onChange(of: snap.isExpired) { _, expired in
            if !expired && armed == .reset { disarm() }
        }
        .onChange(of: snap.isRunning) { _, running in
            if !running && armed == .edit { disarm() }
        }
        .onChange(of: zoom) { zoomChanged() }
        // Edge to edge: the glow, vignette and flash cover the title bar area too.
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { primaryAction() }
        .contextMenu { contextMenuItems }
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
        .onContinuousHover { phase in
            if case .active = phase { wake() }
        }
        .onAppear {
            hasFocus = true
            wake()
        }
        .onDisappear {
            idleTask?.cancel()
            controller.setWindowChromeVisible(true)
        }
        // The timer's theme applies to its own drawing only. preferredColorScheme would set the
        // whole window's appearance, and it sticks after going back to the setup screen.
        .environment(\.colorScheme, config.theme == .light ? .light : .dark)
    }

    // MARK: Keys

    /// Space, ↑/↓, R, F, as on the web page, plus Esc to leave fullscreen. Holding ↑/↓ keeps
    /// adjusting at the system key-repeat rate; the other keys act once per press.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // The View menu's Zoom In is ⌘+, which takes Shift on most keyboards; browsers also
        // accept ⌘=, so this does too.
        if press.modifiers == .command && press.phase == .down && press.characters == "=" {
            CountdownZoom.zoomIn()
            return .handled
        }
        if !press.modifiers.intersection([.command, .control, .option]).isEmpty { return .ignored }

        switch press.key {
        case .upArrow:
            controller.adjust(by: TimerEngine.adjustStep)
            return .handled
        case .downArrow:
            // Holding ↓ stops at the last step above zero, so trimming time can't run into
            // "time is up" in front of the room; a fresh press goes the rest of the way.
            if press.phase == .repeat && snap.remaining <= TimerEngine.adjustStep { return .handled }
            controller.adjust(by: -TimerEngine.adjustStep)
            return .handled
        default:
            break
        }

        if press.phase == .repeat { return .handled }

        switch press.key {
        case .space:
            primaryAction()
            return .handled
        case .escape:
            // Fullscreen first, as everywhere on the Mac; then back to editing the timer.
            if controller.isFullscreen {
                controller.togglePresentation()
            } else {
                requestEdit()
            }
            return .handled
        default:
            break
        }

        switch press.characters.lowercased() {
        case "r":
            controller.reset()
            return .handled
        case "f":
            controller.togglePresentation()
            return .handled
        default:
            return .ignored
        }
    }

    /// Shows the cursor and window buttons on mouse movement; hides both after 2.5
    /// seconds of stillness, so a presented timer is just the timer.
    private func wake() {
        if isIdle { controller.setWindowChromeVisible(true) }
        isIdle = false
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            isIdle = true
            NSCursor.setHiddenUntilMouseMoves(true)
            controller.setWindowChromeVisible(false)
        }
    }

    // MARK: Start, pause, reset

    /// Click or Space: start or pause; once time is up, reset, but only on the second press.
    private func primaryAction() {
        guard snap.isExpired else {
            controller.toggle()
            return
        }
        if armed == .reset {
            disarm()
            controller.toggle()   // resets an expired timer
        } else {
            arm(.reset)
        }
    }

    /// Esc: back to editing the timer. While it is counting (down or up), only on the second press.
    private func requestEdit() {
        if !snap.isRunning || armed == .edit {
            disarm()
            controller.edit()
        } else {
            arm(.edit)
        }
    }

    private func arm(_ action: ArmedAction) {
        armed = action
        armTask?.cancel()
        armTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            armed = nil
        }
    }

    private func disarm() {
        armTask?.cancel()
        armed = nil
    }

    @ViewBuilder
    private var armedPrompt: some View {
        if let action = armed {
            Text(action.prompt)
                .font(.inter(15, .semibold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(palette.background.opacity(0.85)))
                .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
                .padding(.bottom, 56)
                .transition(.opacity.combined(with: .offset(y: 8)))
                .allowsHitTesting(false)
        }
    }

    /// Right-click: everything the keys do, with each key shown beside its item. The shortcuts
    /// on these items are for display (and for the open menu); the keys themselves are handled
    /// in `handleKey`, which adds the second-press safety for reset and Esc.
    @ViewBuilder
    private var contextMenuItems: some View {
        if snap.isExpired {
            Button("Reset") { controller.reset() }
                .keyboardShortcut("r", modifiers: [])
        } else {
            Button(snap.isRunning ? "Pause" : "Start") { controller.toggle() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Reset") { controller.reset() }
                .keyboardShortcut("r", modifiers: [])
        }
        Divider()
        Button("Add 15 Seconds") { controller.adjust(by: TimerEngine.adjustStep) }
            .keyboardShortcut(.upArrow, modifiers: [])
        Button("Remove 15 Seconds") { controller.adjust(by: -TimerEngine.adjustStep) }
            .keyboardShortcut(.downArrow, modifiers: [])
        Divider()
        Button("Zoom In") { CountdownZoom.zoomIn() }
            .keyboardShortcut("+", modifiers: .command)
        Button("Zoom Out") { CountdownZoom.zoomOut() }
            .keyboardShortcut("-", modifiers: .command)
        Button("Actual Size") { CountdownZoom.reset() }
            .keyboardShortcut("0", modifiers: .command)
        Divider()
        Button(controller.isFullscreen ? "Exit Fullscreen" : "Present Fullscreen") { controller.togglePresentation() }
            .keyboardShortcut("f", modifiers: [])
        Button("Edit Timer") { controller.edit() }
            .keyboardShortcut(.escape, modifiers: [])
        Divider()
        Button("Copy Link") { controller.copyLink(for: config) }
        ShareLink("Share…", item: controller.shareLink(for: config))
    }

    // MARK: Progress bar

    /// Height of the strip along the bottom that responds to the pointer; the bar itself is
    /// only a few points tall.
    private static let barHitHeight: CGFloat = 28

    /// The progress bar. Click or drag along it to jump to that point in the countdown; while
    /// the pointer is over it the bar thickens and shows the time it would jump to.
    private func progressBar(size: CGSize) -> some View {
        let thickness = max(2, size.height * 0.008)
        let seekable = !snap.isExpired
        let hovering = barHoverX != nil && seekable
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottomLeading) {
                Color.clear
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.accent(hovering ? 0.16 : 0.08))
                    Rectangle()
                        .fill(palette.progressGradient)
                        .shadow(color: palette.accent(0.35), radius: 18)
                        .brightness(snap.isWarning ? 0.08 : 0)
                        .saturation(snap.isWarning ? 1.2 : 1)
                        .scaleEffect(x: max(snap.progress, 0.0001), y: 1, anchor: .leading)
                        .animation(reduceMotion ? nil : .linear(duration: 0.25), value: snap.progress)
                }
                .frame(height: hovering ? max(thickness * 2.2, 8) : thickness)
                .opacity(snap.isExpired ? 0 : (snap.isPaused && !hovering ? 0.4 : 1))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: snap.isExpired)
                .animation(.easeOut(duration: 0.15), value: hovering)
            }
            .frame(height: Self.barHitHeight)
            .contentShape(Rectangle())
            .overlay {
                if let x = barHoverX, seekable {
                    seekLabel(at: x, width: size.width)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { controller.seek(toFraction: Double($0.location.x / max(size.width, 1))) }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if barHoverX == nil { NSCursor.pointingHand.push() }
                    barHoverX = location.x
                    wake()
                case .ended:
                    if barHoverX != nil { NSCursor.pop() }
                    barHoverX = nil
                }
            }
            .onDisappear {
                if barHoverX != nil { NSCursor.pop() }
                barHoverX = nil
            }
            .allowsHitTesting(seekable)
        }
    }

    /// The time a click would jump to, floating just above the pointer.
    private func seekLabel(at x: CGFloat, width: CGFloat) -> some View {
        let text = TimerFormat.clock(controller.secondsLeft(atFraction: Double(x / max(width, 1))))
        // Roughly half the label's width (13 pt digits plus padding), to keep it inside the window.
        let halfWidth = CGFloat(text.count) * 4.2 + 14
        return Text(text)
            .font(.inter(13, .semibold))
            .monospacedDigit()
            .foregroundStyle(palette.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(palette.background.opacity(0.85)))
            .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
            .fixedSize()
            // `position` is relative to the 28 pt strip: centred on the pointer, 16 pt above it.
            .position(x: min(max(x, halfWidth + 6), width - halfWidth - 6), y: -16)
            .allowsHitTesting(false)
    }

    // MARK: Zoom

    /// ⌘+/⌘- scale everything on the stage. Zooming in stops once the stage would no longer fit
    /// the window's height (see `CountdownStage.fittedZoom`).
    private func effectiveZoom(in size: CGSize) -> CGFloat {
        CountdownStage(snap: snap, config: config, palette: palette, size: size).fittedZoom(requested: CGFloat(zoom))
    }

    /// The largest zoom at which the stage's current contents fit the window's height.
    private func fitZoom(in size: CGSize) -> CGFloat {
        CountdownStage(snap: snap, config: config, palette: palette, size: size).fitZoom()
    }

    /// Shows the new zoom for a moment, and pulls a zoom-in that can't fit back to the largest
    /// step that does, so the next ⌘- has an effect straight away.
    private func zoomChanged() {
        let fit = max(1, fitZoom(in: viewSize))
        if zoom > 1, CGFloat(zoom) > fit + 0.001 {
            let largest = CountdownZoom.levels.last { CGFloat($0) <= fit } ?? 1
            if largest != zoom {
                zoom = largest
                return   // runs again for the new value
            }
        }
        let atMax = zoom > 1 && CountdownZoom.levels.first(where: { $0 > zoom + 0.001 }).map { CGFloat($0) > fit } ?? true
        zoomLabel = "\(Int((zoom * 100).rounded()))%" + (atMax ? " · largest that fits" : "")
        zoomLabelTask?.cancel()
        zoomLabelTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            zoomLabel = nil
        }
    }

    @ViewBuilder
    private var zoomBadge: some View {
        if let label = zoomLabel {
            Text(label)
                .font(.inter(14, .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(palette.background.opacity(0.85)))
                .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
                .padding(.top, 40)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: Stage

    private func stage(in size: CGSize) -> some View {
        CountdownStage(
            snap: snap,
            config: config,
            palette: palette,
            size: size,
            scale: effectiveZoom(in: size),
            tickToken: clock.tickToken
        )
    }
}

/// See `CountdownView.armed`.
private enum ArmedAction {
    case reset, edit

    var prompt: String {
        switch self {
        case .reset: return "Click or press Space again to reset the timer"
        case .edit: return "Press Esc again to stop the timer and edit it"
        }
    }
}
