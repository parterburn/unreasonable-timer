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
    @AppStorage(AppSettings.chimeSound) private var chimeSound = ChimeSound.classic.rawValue
    @ObservedObject private var chimes = ChimePlayer.shared

    /// Toggled to make the "Open at login" row re-read `SMAppService`'s status.
    @State private var loginRefresh = false
    @State private var loginError: String?
    /// `-UTSettingsTab shortcuts` opens on that tab, for scripts/ci-screenshots.sh.
    @State private var tab = UserDefaults.standard.string(forKey: "UTSettingsTab") ?? "general"

    var body: some View {
        TabView(selection: $tab) {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            shortcuts
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag("shortcuts")
        }
        .frame(width: 500)
        .scenePadding()
        .tint((AccentColor(string: accentHex) ?? .teal).color)
    }

    /// The last line of each tab, under its final group.
    private var madeBy: some View {
        Text("Made by people + 🤖 from [Unreasonable](https://unreasonablegroup.com)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
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
                Picker("Sound", selection: $chimeSound) {
                    ForEach(ChimeSound.allCases) { sound in
                        Text(sound.title).tag(sound.rawValue)
                    }
                }
                .onChange(of: chimeSound) { chimes.stop() }
                chimeRow("Chime at 15 seconds left", isOn: $chimeAtWarning, moment: .warning)
                chimeRow("Chime at zero", isOn: $chimeAtZero, moment: .zero)
                Text(chimeFootnote)
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
        .formStyle(.grouped)
        .onDisappear { chimes.stop() }
    }

    /// "Version 1.2.0 (3)"
    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    private var chimeFootnote: String {
        let bowl = chimeSound == ChimeSound.singingBowl.rawValue
            ? "The singing bowl rings three times at zero, about ten seconds apart. " : ""
        return bowl + "A notification also appears at zero when the timer isn't in front."
    }

    /// A chime toggle with a play/stop button to hear it.
    private func chimeRow(_ title: String, isOn: Binding<Bool>, moment: ChimePlayer.Moment) -> some View {
        let playing = chimes.previewing == moment
        return Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Text(title)
                Button {
                    chimes.togglePreview(moment, sound: ChimeSound(rawValue: chimeSound) ?? .classic)
                } label: {
                    Image(systemName: playing ? "stop.circle.fill" : "play.circle")
                        .imageScale(.large)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(playing ? "Stop" : "Preview")
                .accessibilityLabel(playing ? "Stop preview" : "Preview \(title.lowercased())")
            }
        }
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
                Text("None are set until you record one. These work from any app; Start / pause begins your most recent timer when none is open.")
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
                shortcutRow("Back to the setup form", "⌘E")
                shortcutRow("Present on the selected display", "⇧⌘F")
                shortcutRow("Fill the form from a copied link", "⇧⌘V")
                shortcutRow("Start a saved timer", "⌘1", "…", "⌘9")
                shortcutRow("Settings", "⌘,")
            } header: {
                Text("Anywhere in the app")
            } footer: {
                madeBy
            }
        }
        .formStyle(.grouped)
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
