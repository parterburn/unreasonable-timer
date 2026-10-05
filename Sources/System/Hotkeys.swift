import KeyboardShortcuts
import TimerCore

extension KeyboardShortcuts.Name {
    // No default key combos: global shortcuts are easy to collide with other apps, so the user
    // picks their own in Settings ▸ Shortcuts.
    static let toggleTimer = Self("toggleTimer")
    static let resetTimer = Self("resetTimer")
    static let addTime = Self("addTime")
    static let removeTime = Self("removeTime")
    static let showTimer = Self("showTimer")
}

enum Hotkeys {
    /// Registers the global shortcuts. They work while another app is frontmost.
    @MainActor
    static func install(controller: TimerController) {
        KeyboardShortcuts.onKeyUp(for: .toggleTimer) {
            Task { @MainActor in controller.toggleOrStartLast() }
        }
        KeyboardShortcuts.onKeyUp(for: .resetTimer) {
            Task { @MainActor in controller.reset() }
        }
        KeyboardShortcuts.onKeyUp(for: .addTime) {
            Task { @MainActor in controller.adjust(by: TimerEngine.adjustStep) }
        }
        KeyboardShortcuts.onKeyUp(for: .removeTime) {
            Task { @MainActor in controller.adjust(by: -TimerEngine.adjustStep) }
        }
        KeyboardShortcuts.onKeyUp(for: .showTimer) {
            Task { @MainActor in controller.showMainWindow() }
        }
    }
}
