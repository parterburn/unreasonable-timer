import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// App settings on one page: shown in the main window from the sidebar's gear, and in their own
/// window when ⌘, is pressed while a timer is on screen.
struct SettingsView: View {
    @ObservedObject var controller: TimerController
    @ObservedObject var updater: Updater

    @AppStorage(AppSettings.keepAwake) private var keepAwake = true
    @AppStorage(AppSettings.floatOnTop) private var floatOnTop = false
    @AppStorage(AppSettings.showMenuBarItem) private var showMenuBarItem = true
    @AppStorage(AppSettings.presentDisplay) private var presentDisplay = 0

    /// Toggled to make the "Open at login" row re-read `SMAppService`'s status.
    @State private var loginRefresh = false
    @State private var loginError: String?

    var body: some View {
        Form {
            general
            shortcuts
            updates
        }
        .formStyle(.grouped)
    }

    /// The last line of the page, under Updates.
    private var madeBy: some View {
        Text("Made by people + 🤖 from [Unreasonable](https://unreasonablegroup.com)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
    }

    // MARK: General

    @ViewBuilder
    private var general: some View {
        Section {
            Toggle("Keep the display awake while a timer runs", isOn: $keepAwake)
                .onChange(of: keepAwake) { controller.settingsChanged() }
            Toggle("Keep the timer above other windows", isOn: $floatOnTop)
                .onChange(of: floatOnTop) { controller.settingsChanged() }
            Picker("Present fullscreen on", selection: $presentDisplay) {
                Text("Current display").tag(0)
                ForEach(DisplayPresenter.displays) { display in
                    Text(display.name).tag(display.id)
                }
            }
        } header: {
            Text("Timer")
        } footer: {
            Text("Each timer has its own sound, accent color and theme; set them when you edit the timer.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Section("App") {
            Toggle("Show in the menu bar", isOn: $showMenuBarItem)
            Toggle("Open at login", isOn: launchAtLogin)
            if let loginError = loginError {
                Text(loginError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: Updates

    private var updates: some View {
        Section {
            if updater.isConfigured {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }
                ))
                HStack {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    Text(versionText).foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Version", value: versionText)
                Text("Updates aren't set up in this build. See the README to add a Sparkle key.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Updates")
        } footer: {
            madeBy
        }
    }

    /// "Version 1.2.0 (3)"
    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    /// Backed by the system's login-item state rather than a stored flag, so it stays right if
    /// the user changes it in System Settings.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: {
                _ = loginRefresh
                return SMAppService.mainApp.status == .enabled
            },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginError = nil
                } catch {
                    loginError = "Couldn't change the login item: \(error.localizedDescription)"
                }
                loginRefresh.toggle()
            }
        )
    }

    // MARK: Shortcuts

    @ViewBuilder
    private var shortcuts: some View {
        Section {
            KeyboardShortcuts.Recorder("Start / pause:", name: .toggleTimer)
            KeyboardShortcuts.Recorder("Reset:", name: .resetTimer)
            KeyboardShortcuts.Recorder("Add 15 seconds:", name: .addTime)
            KeyboardShortcuts.Recorder("Remove 15 seconds:", name: .removeTime)
            KeyboardShortcuts.Recorder("Show timer:", name: .showTimer)
        } header: {
            Text("Shortcuts from any app")
        } footer: {
            Text("None are set until you record one. These work from any app; Start / pause begins your most recent timer when none is open.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Section("In the timer") {
            shortcutRow("Start / pause", "Space", note: "or click")
            shortcutRow("Add / remove 15 seconds", "↑", "↓", note: "hold to repeat")
            shortcutRow("Reset", "R")
            shortcutRow("Fullscreen on the selected display", "F")
            shortcutRow("Leave fullscreen", "Esc")
            shortcutRow("Jump to a point", note: "click the progress bar")
            shortcutRow("Zoom in / out / actual size", "⌘+", "⌘−", "⌘0")
        }

        Section {
            shortcutRow("Reset", "⌘R")
            shortcutRow("Add / remove 15 seconds", "⌘↑", "⌘↓")
            shortcutRow("Edit the timer", "⌘E")
            shortcutRow("Present on the selected display", "⇧⌘F")
            shortcutRow("Fill the form from a copied link", "⇧⌘V")
            shortcutRow("Start a saved timer", "⌘1", "…", "⌘9")
            shortcutRow("Settings", "⌘,")
        } header: {
            Text("Anywhere in the app")
        }
    }

    /// A built-in shortcut, drawn as key caps.
    private func shortcutRow(_ title: String, _ keys: String..., note: String? = nil) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                if let note = note {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, keys.isEmpty ? 0 : 4)
                }
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    if key == "…" {
                        Text(key).foregroundStyle(.secondary)
                    } else {
                        Text(key)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 22)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.tertiary, lineWidth: 0.5))
                    }
                }
            }
        }
    }
}

/// The window SwiftUI makes for the Settings scene.
enum SettingsWindow {
    /// Raises Settings above other apps' windows once it exists (opening it is asynchronous).
    @MainActor
    static func bringToFront() {
        Task { @MainActor in
            for _ in 0..<10 {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}
