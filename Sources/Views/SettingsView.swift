import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// App settings on one page: shown in the main window from the sidebar's gear, and in their own
/// window when ⌘, is pressed while a timer is on screen. The only global shortcut is the one
/// that shows the timer; every other key works while the app is in front (see `keys`).
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
        FormPage {
            general
            keys
            updates
        }
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
        FormSection("Timer") {
            FormToggle("Keep the display awake while a timer runs", isOn: $keepAwake)
                .onChange(of: keepAwake) { controller.settingsChanged() }
            FormToggle("Keep the timer above other windows", isOn: $floatOnTop)
                .onChange(of: floatOnTop) { controller.settingsChanged() }
            FormRow("Present fullscreen on") {
                Picker("Present fullscreen on", selection: $presentDisplay) {
                    Text("Current display").tag(0)
                    ForEach(DisplayPresenter.displays) { display in
                        Text(display.name).tag(display.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        } footer: {
            Text("Each timer has its own sound, accent color and theme; set them when you edit the timer.")
        }

        FormSection("App") {
            FormToggle("Show in the menu bar", isOn: $showMenuBarItem)
            FormToggle("Open at login", isOn: launchAtLogin)
            if let loginError = loginError {
                FormRow {
                    EmptyView()
                } label: {
                    Text(loginError).font(.footnote).foregroundStyle(.red)
                }
            }
            FormRow("Shortcut to show the timer") {
                KeyboardShortcuts.Recorder(for: .showTimer)
            }
        } footer: {
            Text("Click the box and press the keys you want, such as ⌃⌥⌘T. Then press them in any app to bring the timer forward.")
        }
    }

    // MARK: Updates

    private var updates: some View {
        FormSection("Updates") {
            if updater.isConfigured {
                FormToggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }
                ))
                FormRow {
                    Text(versionText).foregroundStyle(.secondary)
                } label: {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } else {
                FormRow("Version") {
                    Text(versionText).foregroundStyle(.secondary)
                }
                FormRow {
                    EmptyView()
                } label: {
                    Text("Updates aren't set up in this build. See the README to add a Sparkle key.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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

    // MARK: Keys

    /// The built-in keys, for reference.
    @ViewBuilder
    private var keys: some View {
        FormSection("In the timer") {
            shortcutRow("Start / pause", "Space", note: "or click")
            shortcutRow("Add / remove 15 seconds", "↑", "↓", note: "hold to repeat")
            shortcutRow("Reset", "R")
            shortcutRow("Fullscreen on the selected display", "F")
            shortcutRow("Leave fullscreen, or go back to editing", "Esc")
            shortcutRow("Jump to a point", note: "click the progress bar")
            shortcutRow("Zoom in / out / actual size", "⌘+", "⌘−", "⌘0")
        } footer: {
            Text("Right-click the timer for a menu of all of these.")
        }

        FormSection("Anywhere in the app") {
            shortcutRow("Reset", "⌘R")
            shortcutRow("Add / remove 15 seconds", "⌘↑", "⌘↓")
            shortcutRow("Edit the timer", "⌘E")
            shortcutRow("Present on the selected display", "⇧⌘F")
            shortcutRow("Fill the form from a copied link", "⇧⌘V")
            shortcutRow("Start a saved timer", "⌘1", "…", "⌘9")
            shortcutRow("Settings", "⌘,")
        }
    }

    /// A built-in shortcut, drawn as key caps.
    private func shortcutRow(_ title: String, _ keys: String..., note: String? = nil) -> some View {
        FormRow(title) {
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
