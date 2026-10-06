import Foundation

/// One-shot moments the UI reacts to (animations, chimes, notifications).
public enum TimerEvent: Equatable, Sendable {
    /// A running countdown just crossed into the last 15 seconds.
    case warningEntered
    /// A new second began inside the last 10 seconds of a running countdown.
    case finalTick
    /// A running countdown just reached zero.
    case zeroReached
}

/// Pure countdown state machine, ported from the web timer's script. Time is injected (`now`)
/// so it is deterministic under test, and every mutating call returns the events it caused.
public struct TimerEngine {
    public static let warningThreshold = 15
    public static let finalThreshold = 10
    public static let adjustStep = 15
    /// Overtime heat keeps building for this long, then holds.
    public static let overtimeHeatSeconds = 120.0

    public private(set) var config: TimerConfig
    /// Whole seconds left, rounded up (so the display never shows 0:00 early). 0 once expired.
    public private(set) var remaining: Int
    public private(set) var overtimeSeconds = 0
    /// Non-nil exactly while running (counting down or counting over).
    public private(set) var endsAt: Date?

    // What `observe()` compared against last time, to detect transitions.
    private var lastRemaining: Int
    private var wasExpired = false

    public init(config: TimerConfig) {
        self.config = config
        self.remaining = config.seconds
        self.lastRemaining = config.seconds
    }

    public var isRunning: Bool { endsAt != nil }
    public var isExpired: Bool { remaining <= 0 }

    // MARK: Controls

    /// Replaces the timer with a fresh, paused one.
    public mutating func load(_ config: TimerConfig) {
        self = TimerEngine(config: config)
    }

    @discardableResult
    public mutating func start(now: Date) -> [TimerEvent] {
        guard !isRunning, remaining > 0 else { return [] }
        endsAt = now.addingTimeInterval(TimeInterval(remaining))
        return observe()
    }

    @discardableResult
    public mutating func pause() -> [TimerEvent] {
        endsAt = nil
        return observe()
    }

    /// Start/pause. After the timer has expired, toggling resets it instead.
    @discardableResult
    public mutating func toggle(now: Date) -> [TimerEvent] {
        if remaining <= 0 { return reset() }
        return isRunning ? pause() : start(now: now)
    }

    @discardableResult
    public mutating func reset() -> [TimerEvent] {
        endsAt = nil
        remaining = config.seconds
        overtimeSeconds = 0
        return observe()
    }

    /// Adds or removes time (the ↑/↓ keys use ±15). Never goes below zero. Adjusting an
    /// expired timer upward puts it back into a countdown.
    @discardableResult
    public mutating func adjust(by delta: Int, now: Date) -> [TimerEvent] {
        remaining = max(0, remaining + delta)
        if isRunning { endsAt = now.addingTimeInterval(TimeInterval(remaining)) }
        overtimeSeconds = 0
        var events = observe()
        if remaining <= 0 && !(config.countOver && isRunning) {
            events += pause()
        }
        return events
    }

    /// Where a click on the progress bar lands: `fraction` of the full time (the bar's width),
    /// in whole seconds. Never zero, so a click can't end the timer.
    public func seconds(atFraction fraction: Double) -> Int {
        let target = Int((min(max(fraction, 0), 1) * Double(config.seconds)).rounded())
        return min(max(target, 1), config.seconds)
    }

    /// Jumps to `fraction` of the full time left, as clicking the progress bar does.
    @discardableResult
    public mutating func seek(toFraction fraction: Double, now: Date) -> [TimerEvent] {
        adjust(by: seconds(atFraction: fraction) - remaining, now: now)
    }

    /// Advances the countdown to `now`. Call a few times a second while `isRunning`.
    @discardableResult
    public mutating func tick(now: Date) -> [TimerEvent] {
        guard let endsAt = endsAt else { return [] }
        // Whole milliseconds, like the JS `Date.now()` arithmetic: avoids floating-point
        // error right on a second boundary.
        let ms = Int((endsAt.timeIntervalSince(now) * 1000).rounded())
        remaining = ms > 0 ? (ms + 999) / 1000 : 0
        overtimeSeconds = remaining <= 0 ? (-ms) / 1000 : 0
        var events = observe()
        if remaining <= 0 && !config.countOver {
            events += pause()
        }
        return events
    }

    private mutating func observe() -> [TimerEvent] {
        var events: [TimerEvent] = []
        let expired = remaining <= 0
        if isRunning && !expired {
            if remaining <= TimerEngine.warningThreshold && lastRemaining > TimerEngine.warningThreshold {
                events.append(.warningEntered)
            }
            if remaining <= TimerEngine.finalThreshold && remaining != lastRemaining {
                events.append(.finalTick)
            }
        }
        if isRunning && expired && !wasExpired {
            events.append(.zeroReached)
        }
        lastRemaining = remaining
        wasExpired = expired
        return events
    }

    // MARK: Derived state

    /// Everything a view needs to draw the timer at `now`.
    public struct Snapshot: Equatable, Sendable {
        /// The big text: time left, `+m:ss` in overtime, or the "done" text once expired.
        public let displayText: String
        /// Short form for the menu bar and Dock: always a time (`4:32`, `+0:12`).
        public let compactText: String
        public let isRunning: Bool
        public let isExpired: Bool
        /// Expired and still counting up.
        public let isOvertime: Bool
        public let isWarning: Bool
        public let isFinal: Bool
        public let isPaused: Bool
        /// 0...1 intensity of the edge glow.
        public let heat: Double
        /// 1 = full time left, 0 = none. Never above 1, even after adding time.
        public let progress: Double
        /// "N people waiting · …", only while counting overtime with a room size set.
        public let costText: String?
        public let remaining: Int
        public let overtimeSeconds: Int
    }

    public func snapshot(now: Date) -> Snapshot {
        let expired = remaining <= 0
        let overtime = expired && config.countOver && isRunning

        var secondsLeft = Double(remaining)
        if let endsAt = endsAt, !expired {
            secondsLeft = max(0, endsAt.timeIntervalSince(now))
        }

        let display: String
        let compact: String
        if overtime {
            display = "+" + TimerFormat.clock(overtimeSeconds)
            compact = display
        } else {
            display = expired ? config.doneText : TimerFormat.clock(remaining)
            compact = TimerFormat.clock(remaining)
        }

        var cost: String?
        if overtime, let people = config.people {
            let waiting = "\(people) \(people == 1 ? "person" : "people") waiting"
            cost = "\(waiting) · \(TimerFormat.humanize(people * overtimeSeconds)) of the room’s time"
        }

        return Snapshot(
            displayText: display,
            compactText: compact,
            isRunning: isRunning,
            isExpired: expired,
            isOvertime: overtime,
            isWarning: !expired && remaining <= TimerEngine.warningThreshold,
            isFinal: !expired && remaining <= TimerEngine.finalThreshold,
            isPaused: !isRunning && !expired,
            heat: heat(secondsLeft: secondsLeft, overtimeRunning: overtime),
            progress: min(1, secondsLeft / Double(config.seconds)),
            costText: cost,
            remaining: remaining,
            overtimeSeconds: overtimeSeconds
        )
    }

    /// Ramps up over the last 15 seconds, jumps at zero, then keeps building for two minutes
    /// of overtime.
    func heat(secondsLeft: Double, overtimeRunning: Bool) -> Double {
        if overtimeRunning {
            return 0.35 + 0.65 * min(1, Double(overtimeSeconds) / TimerEngine.overtimeHeatSeconds)
        }
        if remaining <= 0 { return 0.5 }
        if remaining <= TimerEngine.warningThreshold {
            let window = Double(TimerEngine.warningThreshold)
            return 0.3 * (window - secondsLeft) / window
        }
        return 0
    }
}

// MARK: - Formatting

public enum TimerFormat {
    /// `m:ss`, or `h:mm:ss` from one hour up.
    public static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        let ss = pad(s)
        return h > 0 ? "\(h):\(pad(m)):\(ss)" : "\(m):\(ss)"
    }

    /// "45 sec", "12 min", "2hr 5min": the room's combined wasted time.
    public static func humanize(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 1 { return "\(seconds) sec" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)hr \(minutes % 60)min"
    }

    /// "1hr 5min 30sec", omitting zero parts.
    public static func durationLabel(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)hr") }
        if m > 0 { parts.append("\(m)min") }
        if s > 0 { parts.append("\(s)sec") }
        return parts.joined(separator: " ")
    }

    /// Ruby's `String#to_i`: optional sign and leading digits, anything else ignored, else 0.
    public static func rubyToI(_ text: String) -> Int {
        let chars = Array(text.trimmingCharacters(in: .whitespaces))
        var index = 0
        var negative = false
        if index < chars.count, chars[index] == "-" || chars[index] == "+" {
            negative = chars[index] == "-"
            index += 1
        }
        var value = 0
        while index < chars.count, let digit = chars[index].wholeNumberValue, chars[index].isASCII {
            let (product, overflow) = value.multipliedReportingOverflow(by: 10)
            let (sum, overflow2) = product.addingReportingOverflow(digit)
            if overflow || overflow2 { return negative ? Int.min : Int.max }
            value = sum
            index += 1
        }
        return negative ? -value : value
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
