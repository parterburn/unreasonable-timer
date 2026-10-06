import AppKit
import SwiftUI
import TimerCore

/// The countdown screen: a port of the web timer's `.timer` page (see timer.html.erb).
struct CountdownView: View {
    @ObservedObject var controller: TimerController
    @ObservedObject var clock: ClockModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var hasFocus: Bool
    @State private var hoveringStage = false
    @State private var hoveringHint = false
    @State private var isIdle = false
    @State private var idleTask: Task<Void, Never>?
    @State private var viewSize: CGSize = .zero
    @State private var zoomLabel: String?
    @State private var zoomLabelTask: Task<Void, Never>?
    /// Where the pointer is along the progress bar, while it is over it.
    @State private var barHoverX: CGFloat?
    @AppStorage(AppSettings.accentColor) private var accentHex = AccentColor.teal.string
    @AppStorage(AppSettings.countdownZoom) private var zoom = 1.0

    private var snap: TimerEngine.Snapshot { clock.snapshot }
    private var config: TimerConfig { controller.config }
    private var palette: Palette { Palette.make(config.theme, accent: AccentColor(string: accentHex) ?? .teal) }
    /// The lead text gives way to the warning text from 15 seconds on, and stays gone.
    private var showsWarning: Bool { snap.isWarning || snap.isExpired }
    private var hintVisible: Bool { (hoveringStage || hoveringHint) && !isIdle }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimerBackground(palette: palette)
                heatLayer
                flashLayer
                stage(in: geo.size)
                progressBar(size: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size, initial: true) { _, size in viewSize = size }
        }
        .overlay(alignment: .top) { zoomBadge.animation(.easeInOut(duration: 0.2), value: zoomLabel) }
        .onChange(of: zoom) { zoomChanged() }
        // Edge to edge: the glow, vignette and flash cover the title bar area too.
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { controller.toggle() }
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
        .preferredColorScheme(config.theme == .light ? .light : .dark)
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
            controller.toggle()
            return .handled
        case .escape:
            if controller.isFullscreen {
                controller.togglePresentation()
                return .handled
            }
            return .ignored
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

    /// Shows the hint, cursor and window buttons on mouse movement; hides all three after 2.5
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

    // MARK: Atmosphere

    /// Accent glow from the screen edges; the centre stays clear so the digits keep their contrast
    /// on a projector. Builds with `heat`, and breathes once the timer has expired.
    private var heatLayer: some View {
        Wave(period: 3, active: snap.isExpired) { phase in
            EllipticalGradient(
                stops: [
                    .init(color: palette.accent(0), location: 0),
                    .init(color: palette.accent(0), location: 0.4),
                    .init(color: palette.accent(0.18), location: 0.7),
                    .init(color: palette.accent(0.5), location: 1),
                ],
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.7071
            )
            .opacity(snap.heat * (snap.isExpired ? 0.6 + 0.4 * phase : 1))
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1), value: snap.heat)
    }

    /// A brief wash of the accent at zero.
    private var flashLayer: some View {
        // Plain values, not `self`, because the animator's closure isn't main-actor isolated.
        let reduce = reduceMotion
        return EllipticalGradient(
            colors: [palette.flashInner, palette.flashOuter],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.7071
        )
        .keyframeAnimator(initialValue: 0.0, trigger: clock.zeroToken) { content, value in
            content.opacity(reduce ? 0 : value)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.35, duration: 0.01)
                CubicKeyframe(0.0, duration: 1.79)
            }
        }
        .allowsHitTesting(false)
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

    /// ⌘+/⌘- scale everything on the stage. Zooming out always applies; zooming in stops once
    /// the stage would no longer fit the window's height.
    private func effectiveZoom(in size: CGSize) -> CGFloat {
        let requested = CGFloat(zoom)
        guard requested > 1 else { return max(requested, 0.25) }
        return min(requested, max(1, fitZoom(in: size)))
    }

    /// The largest zoom at which the stage's current contents fit 88% of the window's height.
    private func fitZoom(in size: CGSize) -> CGFloat {
        let width = size.width
        let line: CGFloat = 1.21   // Inter's line height
        let digit = baseDigitSize(width: width)
        var height = digit * line
        if snap.isOvertime {
            height += Self.overtimeLabelSize(width) * (line + 0.4)
        }
        if snap.costText != nil {
            height += Self.costSize(width) * line + 16
        }
        if messageVisible {
            height += (snap.costText == nil ? digit * 0.7 : 26) + Self.messageSize(width) * line
        }
        return size.height * 0.88 / max(height, 1)
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

    // Type sizes from the web page's clamp() rules, before zoom.

    /// Digit size steps down once expired, and again in overtime, so a count-up can't be
    /// mistaken for a countdown that is still running.
    private func baseDigitSize(width: CGFloat) -> CGFloat {
        if snap.isOvertime { return .clamp(width * 0.052, min: 31.2, max: 72.8) }
        if snap.isExpired { return .clamp(width * 0.0845, min: 54.08, max: 121.76) }
        return .clamp(width * 0.1521, min: 81.12, max: 216.32)
    }

    private static func messageSize(_ width: CGFloat) -> CGFloat { .clamp(width * 0.0507, min: 33.76, max: 74.4) }
    private static func costSize(_ width: CGFloat) -> CGFloat { .clamp(width * 0.0254, min: 20.32, max: 40.64) }
    private static func overtimeLabelSize(_ width: CGFloat) -> CGFloat { .clamp(width * 0.072, min: 44.8, max: 114.4) }

    /// Whether the lead/warning line is showing anything. It only takes up room when it is, so
    /// digits on their own sit in the middle of the window.
    private var messageVisible: Bool {
        showsWarning ? !config.warningText.isEmpty : config.leadText != nil
    }

    private func stage(in size: CGSize) -> some View {
        let width = size.width
        let scale = effectiveZoom(in: size)
        let digitSize = baseDigitSize(width: width) * scale

        return VStack(spacing: 0) {
            if snap.isOvertime {
                overtimeLabel(size: Self.overtimeLabelSize(width) * scale)
            }

            digits(size: digitSize, maxWidth: width * 0.94)

            if let cost = snap.costText {
                Text(cost)
                    .font(.inter(Self.costSize(width) * scale))
                    .foregroundStyle(palette.accentSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16 * scale)
            }

            messages(size: Self.messageSize(width) * scale, gap: snap.costText == nil ? digitSize * 0.7 : 26 * scale)
        }
        // When the warning appears below digits that were alone, they glide up to make room.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: messageVisible)
        .overlay(alignment: .bottom) {
            // Hangs just below the stage, like the web hint anchored to `top: 100%`.
            hint.alignmentGuide(.bottom) { $0[.top] }
        }
        .onHover { hoveringStage = $0 }
    }

    /// "TIME IS UP!" in big gradient capitals while counting overtime.
    private func overtimeLabel(size: CGFloat) -> some View {
        Wave(period: 2.8, active: true) { pulse in
            Text(config.doneText.uppercased())
                .font(.inter(size, .semibold))
                .tracking(size * 0.08)
                .foregroundStyle(palette.accentText)
                .shadow(color: palette.accent(0.45), radius: 8 + snap.heat * 40)
                .scaleEffect(1 + 0.04 * pulse)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .padding(.bottom, size * 0.4)
    }

    private func digits(size: CGFloat, maxWidth: CGFloat) -> some View {
        let isDoneText = snap.isExpired && !snap.isOvertime
        // Plain values, not `self`, because the animator's closure isn't main-actor isolated.
        let isFinal = snap.isFinal
        let reduce = reduceMotion
        let palette = self.palette
        return Wave(period: 1.5, active: snap.isWarning && !snap.isFinal) { flash in
            Wave(period: 2.8, active: isDoneText) { pulse in
                digitsText(size: size, isDoneText: isDoneText, pulse: pulse)
                    .multilineTextAlignment(.center)
                    .lineLimit(isDoneText ? 4 : 1)
                    .minimumScaleFactor(isDoneText ? 0.5 : 0.4)
                    .frame(maxWidth: maxWidth)
                    .foregroundStyle(palette.digitColor(flash: flash))
                    // Each second of the last ten: the digits swell slightly and settle back,
                    // like a heartbeat. No colour change, so they read the same throughout.
                    .keyframeAnimator(initialValue: 0.0, trigger: clock.tickToken) { content, beat in
                        content.scaleEffect(1 + 0.045 * ((isFinal && !reduce) ? beat : 0))
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.0, duration: 0.16)
                            CubicKeyframe(0.0, duration: 0.6)
                        }
                    }
            }
        }
        .opacity(snap.isPaused ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: snap.isPaused)
        .accessibilityLabel(snap.displayText)
    }

    /// The digits themselves. While counting down the colour comes from the animator in
    /// `digits`; once expired they carry their own gradient or muted colour.
    @ViewBuilder
    private func digitsText(size: CGFloat, isDoneText: Bool, pulse: Double) -> some View {
        let weight: Font.Weight = snap.isOvertime ? .light : (isDoneText ? .medium : .regular)
        let tracking: CGFloat = snap.isOvertime ? size * 0.04 : (isDoneText ? -size * 0.02 : -size * 0.03)
        let base = Text(snap.displayText)
            .font(.inter(size, weight))
            .monospacedDigit()
            .tracking(tracking)

        if snap.isOvertime {
            base.foregroundStyle(palette.textMuted)
        } else if snap.isExpired {
            base
                .foregroundStyle(palette.accentText)
                .shadow(color: palette.accent(0.45), radius: 8 + snap.heat * 40)
                .scaleEffect(1 + 0.04 * pulse)
        } else {
            base
        }
    }

    /// Lead and warning text share one cell and cross-fade at 15 seconds, so swapping one for
    /// the other never shifts the digits. With nothing to show, the cell isn't there at all.
    @ViewBuilder
    private func messages(size: CGFloat, gap: CGFloat) -> some View {
        let lead = config.leadText
        let warning = config.warningText
        if messageVisible {
            ZStack {
                if let lead = lead {
                    Text(lead)
                        .font(.inter(size * 0.75, .medium))
                        .foregroundStyle(palette.textSoft)
                        .opacity(showsWarning ? 0 : 1)
                        .offset(y: showsWarning ? -12 : 0)
                }
                if !warning.isEmpty {
                    Text(warning)
                        .font(.inter(size, .semibold))
                        .tracking(-size * 0.01)
                        .foregroundStyle(palette.text)
                        .opacity(showsWarning ? 1 : 0)
                        .offset(y: showsWarning ? 0 : 12)
                }
            }
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 41.6)
            .padding(.top, gap)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: showsWarning)
            .transition(.opacity.combined(with: .offset(y: 12)))
        }
    }

    private var hint: some View {
        HStack(spacing: 0) {
            Text("Click or Space to start/pause · ↑/↓ ±15s · R to reset · F for fullscreen · ")
            Button {
                controller.edit()
            } label: {
                Text("Edit").underline()
            }
            .buttonStyle(.plain)
            .disabled(!hintVisible)
        }
        .font(.inter(13.6))
        .foregroundStyle(palette.accentSoft)
        .lineLimit(1)
        .fixedSize()
        .padding(.top, 20)
        .contentShape(Rectangle())
        .onTapGesture { controller.toggle() }
        .onHover { hoveringHint = $0 }
        .opacity(hintVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: hintVisible)
    }
}
