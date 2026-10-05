import SwiftUI

/// Drives the web timer's looping CSS animations (`infinite` keyframes). `content` receives a
/// 0...1 phase that eases back and forth once per `period`; it is a constant 0 while inactive or
/// when Reduce Motion is on.
///
/// The `TimelineView` stays in the hierarchy whether or not it is active (it just pauses), so
/// views inside keep their identity and any `keyframeAnimator` state survives.
struct Wave<Content: View>: View {
    let period: Double
    let active: Bool
    let content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(period: Double, active: Bool, @ViewBuilder content: @escaping (Double) -> Content) {
        self.period = period
        self.active = active
        self.content = content
    }

    var body: some View {
        let running = active && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running)) { context in
            content(running ? 0.5 - 0.5 * cos(2 * Double.pi * context.date.timeIntervalSinceReferenceDate / period) : 0)
        }
    }
}

extension CGFloat {
    /// CSS `clamp(min, preferred, max)`.
    static func clamp(_ preferred: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(preferred, lo), hi)
    }
}
