import SwiftUI
import TimerCore

/// What the countdown shows in the middle of the window: the digits (or the text for zero),
/// the overtime label, the room's cost line and the lead or warning text, sized by the web
/// page's clamp() rules for `size`. The countdown screen draws it live; the setup screen's
/// preview draws it for a chosen moment, scaled down.
struct CountdownStage: View {
    let snap: TimerEngine.Snapshot
    let config: TimerConfig
    let palette: Palette
    /// The window the stage is laid out for.
    let size: CGSize
    /// ⌘+/⌘- zoom, already held to what fits.
    var scale: CGFloat = 1
    /// Bumped each second of the last ten, to replay the beat.
    var tickToken = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The lead text gives way to the warning text from 15 seconds on, and stays gone.
    private var showsWarning: Bool { snap.isWarning || snap.isExpired }

    // Type sizes from the web page's clamp() rules, before zoom.

    /// Digit size steps down once expired, and again in overtime, so a count-up can't be
    /// mistaken for a countdown that is still running.
    private func baseDigitSize(width: CGFloat) -> CGFloat {
        if snap.isOvertime { return .clamp(width * 0.052, min: 31.2, max: 72.8) }
        if snap.isExpired { return .clamp(width * 0.0845, min: 54.08, max: 121.76) }
        return .clamp(width * 0.1521, min: 81.12, max: 216.32)
    }

    static func messageSize(_ width: CGFloat) -> CGFloat { .clamp(width * 0.0507, min: 33.76, max: 74.4) }
    static func costSize(_ width: CGFloat) -> CGFloat { .clamp(width * 0.0254, min: 20.32, max: 40.64) }
    static func overtimeLabelSize(_ width: CGFloat) -> CGFloat { .clamp(width * 0.072, min: 44.8, max: 114.4) }

    /// Whether the lead/warning line is showing anything. It only takes up room when it is, so
    /// digits on their own sit in the middle of the window.
    private var messageVisible: Bool {
        showsWarning ? !config.warningText.isEmpty : config.leadText != nil
    }

    /// The largest zoom at which the stage's current contents fit 88% of `size`'s height.
    func fitZoom() -> CGFloat {
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

    var body: some View {
        let width = size.width
        let digitSize = baseDigitSize(width: width) * scale

        return VStack(spacing: 0) {
            if snap.isOvertime {
                overtimeLabel(size: Self.overtimeLabelSize(width) * scale)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            digits(size: digitSize, maxWidth: width * 0.94)

            if let cost = snap.costText {
                Text(cost)
                    .font(.inter(Self.costSize(width) * scale))
                    .foregroundStyle(palette.accentSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16 * scale)
                    .transition(.opacity)
            }

            messages(size: Self.messageSize(width) * scale, gap: snap.costText == nil ? digitSize * 0.7 : 26 * scale)
        }
        // When the warning appears below digits that were alone, they glide up to make room.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: messageVisible)
        // At zero the digits ease into the smaller overtime (or "done") style and the label
        // fades in, rather than everything switching at once.
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: snap.isExpired)
    }

    /// The text for zero ("Time is up!"), big and in the accent gradient, while counting
    /// overtime. Shown as typed: whoever wants capitals types them.
    private func overtimeLabel(size: CGFloat) -> some View {
        Wave(period: 2.8, active: true) { pulse in
            Text(config.doneText)
                .font(.inter(size, .semibold))
                .tracking(size * 0.005)
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
                    // Each second of the last ten: the digits swell a little and flash the
                    // accent, then settle straight back to white, like a heartbeat.
                    .keyframeAnimator(initialValue: 0.0, trigger: tickToken) { content, beat in
                        let t = (isFinal && !reduce) ? beat : 0
                        content
                            .foregroundStyle(palette.digitColor(flash: flash, beat: t))
                            .scaleEffect(1 + 0.045 * t)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.0, duration: 0.14)
                            CubicKeyframe(0.0, duration: 0.5)
                        }
                    }
            }
        }
        .opacity(snap.isPaused ? 0.55 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: snap.isPaused)
        .accessibilityLabel(snap.displayText)
    }

    /// The digits themselves, as one text whose size, weight and colour ease into the expired
    /// style at zero. While counting down the colour comes from the animator in `digits`
    /// (`.foreground` defers to it); once expired they carry the gradient or a muted colour.
    private func digitsText(size: CGFloat, isDoneText: Bool, pulse: Double) -> some View {
        let weight: Font.Weight = snap.isOvertime ? .light : (isDoneText ? .medium : .regular)
        let tracking: CGFloat = snap.isOvertime ? size * 0.04 : (isDoneText ? -size * 0.02 : -size * 0.03)
        let style: AnyShapeStyle = snap.isOvertime
            ? AnyShapeStyle(palette.textMuted)
            : (isDoneText ? AnyShapeStyle(palette.accentText) : AnyShapeStyle(ForegroundStyle()))
        return Text(snap.displayText)
            .font(.inter(size, weight))
            .monospacedDigit()
            .tracking(tracking)
            .foregroundStyle(style)
            .contentTransition(.interpolate)
            .shadow(color: isDoneText ? palette.accent(0.45) : .clear, radius: isDoneText ? 8 + snap.heat * 40 : 0)
            .scaleEffect(isDoneText ? 1 + 0.04 * pulse : 1)
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
}

/// Accent glow from the edges of the window, behind the stage.
struct HeatGlow: View {
    let palette: Palette
    /// 0...1
    let heat: Double
    /// Breathes once the timer has expired.
    let expired: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Accent glow from the screen edges; the centre stays clear so the digits keep their contrast
    /// on a projector. Builds with `heat`, and breathes once the timer has expired.
    var body: some View {
        Wave(period: 3, active: expired) { phase in
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
            .opacity(heat * (expired ? 0.6 + 0.4 * phase : 1))
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1), value: heat)
    }
}
