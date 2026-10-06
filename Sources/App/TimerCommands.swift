import SwiftUI
import TimerCore

/// The Timer menu. Space, R, F, ↑/↓ and Esc are handled by the countdown view itself, as on the
/// web page, so they don't fire while typing in the setup form; the menu adds ⌘ variants.
struct TimerCommands: Commands {
    @ObservedObject var controller: TimerController
    @ObservedObject var store: PresetStore
    @ObservedObject var updater: Updater

    var body: some Commands {
        // One window only: there is no "New Window".
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }

        // Zoom applies to the countdown, like zooming the web page in a browser. The countdown
        // view also takes ⌘= for Zoom In.
        CommandGroup(before: .toolbar) {
            Button("Actual Size") { CountdownZoom.reset() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!controller.hasTimer)
            Button("Zoom In") { CountdownZoom.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!controller.hasTimer)
            Button("Zoom Out") { CountdownZoom.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!controller.hasTimer)
            Divider()
        }

        CommandMenu("Timer") {
            Button(controller.isRunning ? "Pause" : "Start") { controller.toggle() }
                .disabled(!controller.hasTimer)
            Button("Reset") { controller.reset() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!controller.hasTimer)
            Button("Add 15 Seconds") { controller.adjust(by: TimerEngine.adjustStep) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!controller.hasTimer)
            Button("Remove 15 Seconds") { controller.adjust(by: -TimerEngine.adjustStep) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!controller.hasTimer)

            Divider()

            Button("Edit Timer") { controller.edit() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!controller.hasTimer)
            Button("Present on Selected Display") { controller.togglePresentation() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!controller.hasTimer)
            Button("Fill Form from Copied Link") { _ = controller.fillFormFromPasteboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])

            if !store.presets.isEmpty {
                Divider()
                ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                    let start = Button("\(preset.name) (\(preset.config.durationLabel))") {
                        controller.open(preset.config, autostart: true)
                    }
                    // ⌘1 to ⌘9 for the first nine.
                    if index < 9 {
                        start.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    } else {
                        start
                    }
                }
            }
        }
    }
}
