import AppKit
import TimerCore

/// Closing the window leaves the app (and a running timer) alive in the Dock and menu bar, and
/// supplies the Dock icon's right-click menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let controller = TimerController.shared
        let menu = NSMenu()

        if controller.hasTimer {
            menu.addItem(menuItem(controller.isRunning ? "Pause" : "Start", #selector(toggleTimer)))
            menu.addItem(menuItem("Reset", #selector(resetTimer)))
            menu.addItem(.separator())
        }

        let presets = controller.store.presets
        if !presets.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: "Saved Timers"))
            for preset in presets {
                let entry = menuItem("\(preset.name) · \(preset.config.durationLabel)", #selector(startPreset(_:)))
                entry.representedObject = preset.id.uuidString
                menu.addItem(entry)
            }
            menu.addItem(.separator())
        }

        menu.addItem(menuItem("Show Timer", #selector(showTimer)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleTimer() { TimerController.shared.toggle() }
    @objc private func resetTimer() { TimerController.shared.reset() }
    @objc private func showTimer() { TimerController.shared.showMainWindow() }

    @objc private func startPreset(_ sender: NSMenuItem) {
        let controller = TimerController.shared
        guard let id = sender.representedObject as? String, let preset = controller.store.preset(withID: id) else { return }
        controller.open(preset.config, autostart: true)
    }
}
