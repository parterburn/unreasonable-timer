import AppKit
import SwiftUI
import TimerCore

/// The high-frequency half of the timer state. Only the countdown view observes this, so the
/// menus and commands (which observe `TimerController`) aren't rebuilt five times a second.
@MainActor
final class ClockModel: ObservableObject {
    @Published private(set) var snapshot: TimerEngine.Snapshot
    /// Bumped on each event so views can replay one-shot animations.
    @Published private(set) var tickToken = 0

    init(snapshot: TimerEngine.Snapshot) {
        self.snapshot = snapshot
    }

    func update(_ new: TimerEngine.Snapshot) {
        if new != snapshot { snapshot = new }
    }

    func record(_ events: [TimerEvent]) {
        for event in events {
            switch event {
            case .finalTick: tickToken += 1
            case .zeroReached, .warningEntered: break
            }
        }
    }
}

/// Owns the one active timer and everything that reacts to it: the ticker, the menu bar title,
/// the Dock tile, the display-awake assertion, chimes and notifications.
@MainActor
final class TimerController: ObservableObject {
    static let shared = TimerController()

    enum Screen: Equatable {
        case setup
        case countdown
    }

    @Published private(set) var screen: Screen = .setup
    /// The timer on screen, or the last one used (it pre-fills the setup form).
    @Published private(set) var config: TimerConfig
    /// Live time for the menu bar while a timer is loaded; nil otherwise.
    @Published private(set) var menuTitle: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isFullscreen = false
    /// A config the setup form should load (from a pasted link or "Load into Form").
    @Published var formPrefill: TimerConfig?
    /// The setup screen shows app settings instead of the timer form.
    @Published var showSettingsPane = false
    /// The last timer opened from a shared link that carried a name, so "Save as Timer…" can
    /// suggest it.
    private(set) var sharedTimer: (config: TimerConfig, name: String)?

    let store: PresetStore
    let clock: ClockModel

    /// Set by the root view so non-view code (hotkeys, intents, URLs) can reopen the window.
    var openMainWindow: (() -> Void)?
    /// Set by the root view: opens the Settings scene's own window.
    var openSettingsWindow: (() -> Void)?
    private(set) weak var mainWindow: NSWindow?

    private var engine: TimerEngine
    private var tickTask: Task<Void, Never>?
    private let keepAwake = KeepAwake()
    private let dockTile = DockTile()
    private let notifier = Notifier()
    private let chimes = ChimePlayer.shared
    private var windowObservers: [NSObjectProtocol] = []

    private init() {
        let initial = TimerConfig(seconds: TimerConfig.defaultSeconds)
        let engine = TimerEngine(config: initial)
        self.engine = engine
        self.clock = ClockModel(snapshot: engine.snapshot(now: Date()))
        self.store = PresetStore.shared
        self.config = PresetStore.shared.recent.first ?? initial
    }

    /// A timer is on the countdown screen (running, paused or finished).
    var hasTimer: Bool { screen == .countdown }

    // MARK: Opening timers

    /// Shows `newConfig` in the countdown view. The setup form opens timers paused, like the web
    /// page; quick entry points (menu bar, hotkeys, Shortcuts, links) pass `autostart`.
    func open(_ newConfig: TimerConfig, autostart: Bool) {
        stopTicking()
        showSettingsPane = false
        engine.load(newConfig)
        config = newConfig
        store.remember(newConfig)
        screen = .countdown
        showMainWindow()
        apply([])
        if autostart { start() }
    }

    func handle(url: URL) {
        let link = url.absoluteString
        switch url.scheme?.lowercased() {
        case "https", "http":
            // A shared Eco link (https://unreasonable.eco/timer?…), opened here instead of in the
            // browser: like the web page, it opens the countdown paused, or the form with edit=1.
            guard let linked = TimerConfig(link: link) else { return showMainWindow() }
            rememberSharedName(of: linked, in: link)
            if TimerConfig.parameter("edit", inLink: link) != nil {
                prefillForm(with: linked)
            } else {
                open(linked, autostart: false)
            }
        case "untimer":
            let host = url.host?.lowercased()
            guard let linked = TimerConfig(link: link) else {
                if host == "edit" { edit() }
                showMainWindow()
                return
            }
            rememberSharedName(of: linked, in: link)
            switch host {
            case "edit": prefillForm(with: linked)   // untimer://edit?… opens the setup form filled in
            case "open": open(linked, autostart: false)
            default: open(linked, autostart: true)
            }
        default:
            return
        }
    }

    private func rememberSharedName(of config: TimerConfig, in link: String) {
        if let name = TimerConfig.parameter("name", inLink: link), !name.isEmpty {
            sharedTimer = (config, name)
        }
    }

    /// The name to suggest when saving `config`: its saved name, or the name it was shared under.
    func suggestedName(for config: TimerConfig?) -> String? {
        guard let config = config else { return nil }
        if let preset = store.presets.first(where: { $0.config == config }) { return preset.name }
        if let shared = sharedTimer, shared.config == config { return shared.name }
        return nil
    }

    // MARK: Sharing

    /// A link anyone can open: in the Mac app where it's installed, on the Eco web page otherwise.
    func shareLink(for config: TimerConfig, name: String? = nil) -> URL {
        URL(string: config.shareLink(name: name ?? suggestedName(for: config)))!
    }

    func copyLink(for config: TimerConfig, name: String? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shareLink(for: config, name: name).absoluteString, forType: .string)
    }

    /// Fills the setup form from a copied `/timer` or `untimer://` link.
    @discardableResult
    func fillFormFromPasteboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string),
              let linked = TimerConfig(link: text) else { return false }
        prefillForm(with: linked)
        return true
    }

    func prefillForm(with newConfig: TimerConfig) {
        if screen == .countdown { edit() }
        formPrefill = newConfig
        showMainWindow()
    }

    /// Back to the setup form. Whatever was running stops, like leaving the web page.
    func edit() {
        stopTicking()
        engine.pause()
        if isFullscreen { mainWindow?.toggleFullScreen(nil) }
        screen = .setup
        apply([])
    }

    // MARK: Controls

    func start() {
        guard screen == .countdown else { return }
        notifier.requestAuthorizationIfNeeded()
        apply(engine.start(now: Date()))
        ensureTicking()
    }

    func toggle() {
        guard screen == .countdown else { return }
        if !engine.isRunning && !engine.isExpired { notifier.requestAuthorizationIfNeeded() }
        apply(engine.toggle(now: Date()))
        ensureTicking()
    }

    func reset() {
        guard screen == .countdown else { return }
        apply(engine.reset())
    }

    func adjust(by delta: Int) {
        guard screen == .countdown else { return }
        apply(engine.adjust(by: delta, now: Date()))
        ensureTicking()
    }

    /// Jumps to the point on the progress bar at `fraction` (0 = its left end, 1 = the full time).
    func seek(toFraction fraction: Double) {
        guard screen == .countdown else { return }
        apply(engine.seek(toFraction: fraction, now: Date()))
        ensureTicking()
    }

    /// The time a click at `fraction` of the progress bar would jump to.
    func secondsLeft(atFraction fraction: Double) -> Int {
        engine.seconds(atFraction: fraction)
    }

    /// For Shortcuts.app: toggles the current timer, or starts the most
    /// recent one when nothing is loaded.
    func toggleOrStartLast() {
        if screen == .countdown {
            toggle()
        } else if let last = store.recent.first {
            open(last, autostart: true)
        } else {
            showMainWindow()
        }
    }

    // MARK: Window

    /// ⌘, and the menu bar: settings in the main window's setup screen, or in their own window
    /// while a timer is on screen (leaving the countdown for the setup screen would stop it).
    func showSettings() {
        if screen == .setup {
            showSettingsPane = true
            showMainWindow()
        } else {
            NSApp.activate()
            openSettingsWindow?()
            SettingsWindow.bringToFront()
        }
    }

    func showMainWindow() {
        NSApp.activate()
        if let window = mainWindow, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    func attach(window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenPrimary)
        // For scripted screenshots (scripts/ci-screenshots.sh): `-UTWindowFrame "{{x,y},{w,h}}"`.
        // Applied after SwiftUI has finished placing the window, or it overrides the frame.
        if let frame = UserDefaults.standard.string(forKey: "UTWindowFrame") {
            Task { @MainActor [weak window] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                window?.setFrame(NSRectFromString(frame), display: true)
            }
        }
        applyWindowSettings()

        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.isFullscreen = true }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.isFullscreen = false }
            },
        ]
        isFullscreen = window.styleMask.contains(.fullScreen)
    }

    /// Re-reads the preferences that affect the window and the power assertion.
    func settingsChanged() {
        applyWindowSettings()
        refresh()
    }

    private func applyWindowSettings() {
        mainWindow?.level = UserDefaults.standard.bool(forKey: AppSettings.floatOnTop) ? .floating : .normal
    }

    /// Fades the traffic-light buttons, so an idle countdown is edge-to-edge timer like the web
    /// page in fullscreen. They come back on any mouse movement.
    func setWindowChromeVisible(_ visible: Bool) {
        guard let titlebar = mainWindow?.standardWindowButton(.closeButton)?.superview else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            titlebar.animator().alphaValue = visible ? 1 : 0
        }
    }

    /// Fullscreen on the remembered display (see Settings ▸ Present on).
    func togglePresentation() {
        guard screen == .countdown else { return }
        guard let window = mainWindow else {
            showMainWindow()
            return
        }
        DisplayPresenter.toggleFullscreen(of: window, displayID: UserDefaults.standard.integer(forKey: AppSettings.presentDisplay))
    }

    // MARK: Ticking

    private func ensureTicking() {
        guard tickTask == nil, engine.isRunning else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self = self, !Task.isCancelled else { return }
                if !self.tick() { return }
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Returns whether the timer is still running.
    private func tick() -> Bool {
        apply(engine.tick(now: Date()))
        if !engine.isRunning {
            tickTask = nil
            return false
        }
        return true
    }

    // MARK: Reacting

    private func apply(_ events: [TimerEvent]) {
        clock.record(events)

        for event in events {
            switch event {
            case .warningEntered:
                if engine.config.chimeAtWarning { chimes.play(.warning, sound: engine.config.sound) }
            case .zeroReached:
                chimes.play(.zero, sound: engine.config.sound)
                if !isTimerInFront { notifier.notifyDone(engine.config.doneText) }
            case .finalTick:
                break
            }
        }
        refresh()
    }

    private var isTimerInFront: Bool {
        guard NSApp.isActive, let window = mainWindow else { return false }
        return window.isVisible && !window.isMiniaturized
    }

    private func refresh() {
        let snapshot = engine.snapshot(now: Date())
        clock.update(snapshot)

        let running = engine.isRunning
        if isRunning != running { isRunning = running }

        let title: String? = screen == .countdown ? snapshot.compactText : nil
        if menuTitle != title { menuTitle = title }

        keepAwake.setHeld(running && UserDefaults.standard.bool(forKey: AppSettings.keepAwake))

        // A bowl still ringing from zero fades out once the timer is reset, replaced or left.
        if screen != .countdown || !snapshot.isExpired { chimes.timerNoLongerExpired() }

        dockTile.update(title.map { text in
            DockTile.State(
                text: text,
                progress: snapshot.progress,
                expired: snapshot.isExpired,
                overtime: snapshot.isOvertime,
                accent: AccentColor(config: engine.config)
            )
        })
    }
}
