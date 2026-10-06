import SwiftUI
import TimerCore

@main
struct UnreasonableTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var controller = TimerController.shared
    @StateObject private var store = PresetStore.shared
    @StateObject private var updater = Updater.shared
    @AppStorage(AppSettings.showMenuBarItem) private var showMenuBarItem = true

    init() {
        AppSettings.registerDefaults()
        FontLoader.registerBundledFonts()
        Hotkeys.install(controller: TimerController.shared)
    }

    var body: some Scene {
        Window("Unreasonable Timer", id: "main") {
            RootView(controller: controller)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 780)
        .commands {
            TimerCommands(controller: controller, store: store, updater: updater)
        }

        MenuBarExtra(isInserted: $showMenuBarItem) {
            MenuBarView(controller: controller, store: store)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(controller: controller, updater: updater)
        }
    }
}

/// Switches between the setup form and the countdown, like the web page's two states.
struct RootView: View {
    @ObservedObject var controller: TimerController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            switch controller.screen {
            case .setup:
                SetupView(controller: controller, store: controller.store)
                    .transition(.opacity)
            case .countdown:
                CountdownView(controller: controller, clock: controller.clock)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controller.screen)
        .frame(minWidth: 480, minHeight: 360)
        // SwiftUI's standard controls pick up the accent too.
        .tint(AccentColor(config: controller.config).color)
        .background(WindowAccessor { controller.attach(window: $0) })
        .onOpenURL { controller.handle(url: $0) }
        .onAppear {
            controller.openMainWindow = { openWindow(id: "main") }
            // For scripted screenshots (scripts/ci-screenshots.sh).
            if UserDefaults.standard.bool(forKey: "UTOpenSettings") { openSettings() }
        }
    }
}
