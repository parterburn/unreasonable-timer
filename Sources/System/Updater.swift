import Foundation
import Sparkle

/// Thin wrapper around Sparkle. The updater only starts once a real `SUPublicEDKey` is in the
/// Info.plist, so a development build never shows an "updater failed to start" alert.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    let isConfigured: Bool
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let configured = !key.isEmpty && !key.hasPrefix("REPLACE_")
        isConfigured = configured
        controller = SPUStandardUpdaterController(startingUpdater: configured, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
    }

    /// Checks once a day (`SUScheduledCheckInterval`).
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Downloads what a check finds in the background and installs it when the app quits, so
    /// a running countdown is never interrupted. Only possible while `automaticallyChecks` is on.
    var automaticallyInstalls: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
