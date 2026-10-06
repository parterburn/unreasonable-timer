import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Brings the timer forward from any app. No default: a global combo easily collides with
    /// another app's, so the user records their own in Settings.
    static let showTimer = Self("showTimer")
}

enum Hotkeys {
    /// Registers the global shortcut. It works while another app is frontmost.
    @MainActor
    static func install(controller: TimerController) {
        // Up to 1.3 there were also global Start / pause, Reset and ±15 seconds; forget any
        // recorded so they don't linger in UserDefaults.
        for retired in ["toggleTimer", "resetTimer", "addTime", "removeTime"] {
            UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(retired)")
        }

        KeyboardShortcuts.onKeyUp(for: .showTimer) {
            Task { @MainActor in
                NSApp.unhide(nil)
                controller.showMainWindow()
            }
        }
    }
}
