import Foundation

/// UserDefaults keys behind the Settings window. Views bind to these with `@AppStorage`;
/// the controller reads them with `UserDefaults`.
enum AppSettings {
    static let keepAwake = "keepDisplayAwake"
    static let floatOnTop = "floatOnTop"
    static let showMenuBarItem = "showMenuBarItem"
    static let chimeAtWarning = "chimeAtWarning"
    static let chimeAtZero = "chimeAtZero"
    /// `CGDirectDisplayID` of the display to present on, or 0 for "wherever the window is".
    static let presentDisplay = "presentDisplayID"
    /// "#RRGGBB"; every accent shade in the interface derives from it (see `AccentColor`).
    static let accentColor = "accentColor"
    /// A `ChimeSound` raw value.
    static let chimeSound = "chimeSound"
    /// The countdown's ⌘+/⌘- zoom (1 = the web page's sizes).
    static let countdownZoom = "countdownZoom"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            keepAwake: true,
            floatOnTop: false,
            showMenuBarItem: true,
            chimeAtWarning: false,
            chimeAtZero: true,
            presentDisplay: 0,
            accentColor: "#41B8C2",
            chimeSound: ChimeSound.classic.rawValue,
            countdownZoom: 1.0,
        ])
    }
}

/// ⌘+ / ⌘- / ⌘0 on the countdown, in a browser's zoom steps.
enum CountdownZoom {
    static let levels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static var current: Double { UserDefaults.standard.double(forKey: AppSettings.countdownZoom) }

    static func zoomIn() { set(levels.first { $0 > current + 0.001 } ?? levels[levels.count - 1]) }
    static func zoomOut() { set(levels.last { $0 < current - 0.001 } ?? levels[0]) }
    static func reset() { set(1) }

    private static func set(_ value: Double) {
        UserDefaults.standard.set(value, forKey: AppSettings.countdownZoom)
    }
}
