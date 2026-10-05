import AppKit
import UserNotifications

/// Notification and chime when a timer ends.
@MainActor
final class Notifier {
    enum Chime: String {
        case warning = "Tink"
        case done = "Glass"
    }

    private var requestedAuthorization = false

    /// Asks for permission the first time a timer starts, so the prompt arrives with context.
    func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func notifyDone(_ title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Your timer has finished."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func play(_ chime: Chime) {
        NSSound(named: NSSound.Name(chime.rawValue))?.play()
    }
}
