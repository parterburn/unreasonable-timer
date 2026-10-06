import AppKit
import UserNotifications

/// The notification when a timer ends while the app isn't in front. Chimes are `ChimePlayer`.
@MainActor
final class Notifier {
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
}
