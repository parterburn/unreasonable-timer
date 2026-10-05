import AppKit

/// Sends the timer fullscreen on a chosen display, such as a projector.
@MainActor
enum DisplayPresenter {
    struct Display: Identifiable, Hashable {
        let id: Int
        let name: String
    }

    static var displays: [Display] {
        NSScreen.screens.map { Display(id: displayID(of: $0), name: $0.localizedName) }
    }

    static func displayID(of screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    static func screen(withID id: Int) -> NSScreen? {
        guard id != 0 else { return nil }
        return NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// Toggles native fullscreen. When entering, first moves the window onto the remembered
    /// display (if it is still connected), because fullscreen opens on whichever screen the
    /// window is on.
    static func toggleFullscreen(of window: NSWindow, displayID: Int) {
        if !window.styleMask.contains(.fullScreen), let target = screen(withID: displayID) {
            window.setFrame(target.visibleFrame.insetBy(dx: 60, dy: 60), display: true)
        }
        window.toggleFullScreen(nil)
    }
}
