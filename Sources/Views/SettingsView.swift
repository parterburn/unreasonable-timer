import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: TimerController
    @ObservedObject var updater: Updater

    @AppStorage(AppSettings.keepAwake) private var keepAwake = true
    @AppStorage(AppSettings.floatOnTop) private var floatOnTop = false
    @AppStorage(AppSettings.showMenuBarItem) private var showMenuBarItem = true
    @AppStorage(AppSettings.chimeAtWarning) private var chimeAtWarning = false
    @AppStorage(AppSettings.chimeAtZero) private var chimeAtZero = true
    @AppStorage(AppSettings.presentDisplay) private var presentDisplay = 0
    @AppStorage(AppSettings.accentColor) private var accentHex = AccentColor.teal.string

    /// Toggled to make the "Open at login" row re-read `SMAppService`'s status.
    @State private var loginRefresh = false
    @State private var loginError: String?

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            shortcuts
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 500)
        .scenePadding()
        .tint((AccentColor(string: accentHex) ?? .teal).color)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Accent color") {
                    AccentPicker(hex: $accentHex, swatchSize: 15)
                }
                .onChange(of: accentHex) { controller.settingsChanged() }
            }

            Section("Timer") {
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
            }

            Section("Sounds") {
                Toggle("Chime at 15 seconds left", isOn: $chimeAtWarning)
                Toggle("Chime at zero", isOn: $chimeAtZero)
                Text("A notification also appears at zero when the timer isn't in front.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                Toggle("Show in the menu bar", isOn: $showMenuBarItem)
                Toggle("Open at login", isOn: launchAtLogin)
                if let loginError = loginError {
                    Text(loginError).font(.footnote).foregroundStyle(.red)
                }
            }

            Section("Updates") {
                if updater.isConfigured {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.automaticallyChecks = $0 }
                    ))
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                } else {
                    Text("Updates aren't set up in this build. See the README to add a Sparkle key.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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

    private var shortcuts: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Start / pause:", name: .toggleTimer)
                KeyboardShortcuts.Recorder("Reset:", name: .resetTimer)
                KeyboardShortcuts.Recorder("Add 15 seconds:", name: .addTime)
                KeyboardShortcuts.Recorder("Remove 15 seconds:", name: .removeTime)
                KeyboardShortcuts.Recorder("Show timer:", name: .showTimer)
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("These work from any app. Start / pause begins your most recent timer when none is open.")
            }
        }
        .formStyle(.grouped)
    }
}
