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

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            keepAwake: true,
            floatOnTop: false,
            showMenuBarItem: true,
            chimeAtWarning: false,
            chimeAtZero: true,
            presentDisplay: 0,
        ])
    }
}
