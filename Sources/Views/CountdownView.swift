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

    private var snap: TimerEngine.Snapshot { clock.snapshot }
    private var config: TimerConfig { controller.config }
    private var palette: Palette { Palette.forMode(config.theme) }
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
                progressBar(height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.toggle() }
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleKey($0) }
        .onContinuousHover { phase in
            if case .active = phase { wake() }
        }
        .onAppear {
            hasFocus = true
            wake()
        }
        .onDisappear { idleTask?.cancel() }
        .preferredColorScheme(config.theme == .light ? .light : .dark)
    }

    // MARK: Keys

    /// Space, ↑/↓, R, F, as on the web page, plus Esc to leave fullscreen.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if !press.modifiers.intersection([.command, .control, .option]).isEmpty { return .ignored }

        switch press.key {
        case .space:
            controller.toggle()
            return .handled
        case .upArrow:
            controller.adjust(by: TimerEngine.adjustStep)
            return .handled
        case .downArrow:
            controller.adjust(by: -TimerEngine.adjustStep)
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

    /// Shows the hint and cursor on mouse movement; hides both after 2.5 seconds of stillness.
    private func wake() {
        isIdle = false
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            isIdle = true
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    // MARK: Atmosphere

    /// Teal glow from the screen edges; the centre stays clear so the digits keep their contrast
    /// on a projector. Builds with `heat`, and breathes once the timer has expired.
    private var heatLayer: some View {
        Wave(period: 3, active: snap.isExpired) { phase in
            EllipticalGradient(
                stops: [
                    .init(color: palette.teal(0), location: 0),
                    .init(color: palette.teal(0), location: 0.4),
                    .init(color: palette.teal(0.18), location: 0.7),
                    .init(color: palette.teal(0.5), location: 1),
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

    /// A brief wash of teal at zero.
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

    private func progressBar(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.teal(0.08))
                Rectangle()
                    .fill(Palette.progressGradient)
                    .shadow(color: palette.teal(0.35), radius: 18)
                    .brightness(snap.isWarning ? 0.08 : 0)
                    .saturation(snap.isWarning ? 1.2 : 1)
                    .scaleEffect(x: max(snap.progress, 0.0001), y: 1, anchor: .leading)
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: snap.progress)
            }
            .frame(height: max(2, height * 0.008))
            .opacity(snap.isExpired ? 0 : (snap.isPaused ? 0.4 : 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: snap.isExpired)
        }
        .allowsHitTesting(false)
    }

    // MARK: Stage

    private func stage(in size: CGSize) -> some View {
        let width = size.width

        // Digit size steps down once expired, and again in overtime, so a count-up can't be
        // mistaken for a countdown that is still running.
        let digitSize: CGFloat
        if snap.isOvertime {
            digitSize = .clamp(width * 0.052, min: 31.2, max: 72.8)
        } else if snap.isExpired {
            digitSize = .clamp(width * 0.0845, min: 54.08, max: 121.76)
        } else {
            digitSize = .clamp(width * 0.1521, min: 81.12, max: 216.32)
        }
        let messageSize = CGFloat.clamp(width * 0.0507, min: 33.76, max: 74.4)
        let costSize = CGFloat.clamp(width * 0.0254, min: 20.32, max: 40.64)

        return VStack(spacing: 0) {
            if snap.isOvertime {
                overtimeLabel(width: width)
            }

            digits(size: digitSize, maxWidth: width * 0.94)

            if let cost = snap.costText {
                Text(cost)
                    .font(.inter(costSize))
                    .foregroundStyle(palette.tealSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }

            messages(size: messageSize, gap: snap.costText == nil ? digitSize * 0.7 : 26)
        }
        .overlay(alignment: .bottom) {
            // Hangs just below the stage, like the web hint anchored to `top: 100%`.
            hint.alignmentGuide(.bottom) { $0[.top] }
        }
        .onHover { hoveringStage = $0 }
    }

    /// "TIME IS UP!" in big gradient capitals while counting overtime.
    private func overtimeLabel(width: CGFloat) -> some View {
        let size = CGFloat.clamp(width * 0.072, min: 44.8, max: 114.4)
        return Wave(period: 2.8, active: true) { pulse in
            Text(config.doneText.uppercased())
                .font(.inter(size, .semibold))
                .tracking(size * 0.08)
                .foregroundStyle(palette.tealText)
                .shadow(color: palette.teal(0.45), radius: 8 + snap.heat * 40)
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
                    // Each second of the last ten: a small pop from bright teal back to white.
                    .keyframeAnimator(initialValue: 0.0, trigger: clock.tickToken) { content, tick in
                        let t = (isFinal && !reduce) ? tick : 0
                        content
                            .foregroundStyle(palette.digitColor(isFinal: isFinal, flash: flash, tick: t))
                            .scaleEffect(1 + 0.05 * t)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(1.0, duration: 0.01)
                            CubicKeyframe(0.0, duration: 0.99)
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
                .foregroundStyle(palette.tealText)
                .shadow(color: palette.teal(0.45), radius: 8 + snap.heat * 40)
                .scaleEffect(1 + 0.04 * pulse)
        } else {
            base
        }
    }

    /// Lead and warning text share one cell and cross-fade at 15 seconds, so the swap never
    /// shifts the digits.
    @ViewBuilder
    private func messages(size: CGFloat, gap: CGFloat) -> some View {
        let lead = config.leadText
        let warning = config.warningText
        if lead != nil || !warning.isEmpty {
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
            .padding(.horizontal, 41.6)
            .padding(.top, gap)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: showsWarning)
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
        .foregroundStyle(palette.tealSoft)
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
