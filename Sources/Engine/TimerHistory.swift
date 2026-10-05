import Foundation

/// The "previous timers" list: most recent first, no repeats, capped.
public enum TimerHistory {
    public static let limit = 5

    /// Records a run. A timer already in the list moves to the front instead of repeating.
    public static func remembering(_ config: TimerConfig, in list: [TimerConfig], limit: Int = TimerHistory.limit) -> [TimerConfig] {
        var result = list.filter { $0 != config }
        result.insert(config, at: 0)
        return Array(result.prefix(limit))
    }
}
