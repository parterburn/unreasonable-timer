import AppKit
import SwiftUI
import TimerCore

/// The status item itself: an hourglass, plus the live time while a timer is loaded.
struct MenuBarLabel: View {
    @ObservedObject var controller: TimerController

    var body: some View {
        if let title = controller.menuTitle {
            HStack(spacing: 4) {
                Image(systemName: controller.isRunning ? "hourglass" : "pause.fill")
                Text(title).monospacedDigit()
            }
        } else {
            Image(systemName: "hourglass")
        }
    }
}

/// The menu under the status item: controls for the current timer, then saved and recent ones.
struct MenuBarView: View {
    @ObservedObject var controller: TimerController
    @ObservedObject var store: PresetStore
    @ObservedObject var updater: Updater

    @AppStorage(AppSettings.presentDisplay) private var presentDisplay = 0

    var body: some View {
        if controller.hasTimer {
            Button(controller.isRunning ? "Pause" : "Start") { controller.toggle() }
            Button("Add 15 Seconds") { controller.adjust(by: TimerEngine.adjustStep) }
            Button("Remove 15 Seconds") { controller.adjust(by: -TimerEngine.adjustStep) }
            Button(controller.resetTitle) { controller.reset() }
            Divider()
        }

        Button("Show Timer") { controller.showMainWindow() }
        if controller.hasTimer {
            Button("Present Fullscreen") { controller.togglePresentation() }
        }
        Picker("Present On", selection: $presentDisplay) {
            Text("Current Display").tag(0)
            ForEach(DisplayPresenter.displays) { display in
                Text(display.name).tag(display.id)
            }
        }

        if !store.presets.isEmpty {
            Divider()
            Section("Saved Timers") {
                ForEach(store.presets) { preset in
                    Button("\(preset.name) · \(preset.config.durationLabel)") {
                        controller.open(preset.config, autostart: true)
                    }
                }
            }
        }

        if !store.recent.isEmpty {
            Divider()
            Section("Recent") {
                ForEach(Array(store.recent.enumerated()), id: \.offset) { _, config in
                    Button(config.doneText.isEmpty ? config.durationLabel : "\(config.durationLabel) · \(config.doneText)") {
                        controller.open(config, autostart: true)
                    }
                }
            }
        }

        Divider()
        // Not SettingsLink: the menu bar doesn't bring the app forward, so Settings opened (or
        // was already open) behind whatever app is in front, and the click seemed to do nothing.
        Button("Settings…") { controller.showSettings() }
        if updater.isConfigured {
            Button("Check for Updates…") {
                NSApp.activate()
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
        Button("Quit Unreasonable Timer") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
