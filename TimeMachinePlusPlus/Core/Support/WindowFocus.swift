import AppKit

enum WindowFocus {
    static func focusMainWindow() -> Bool {
        guard let window = NSApp.windows.first(where: isMainAppWindow) else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private static func isMainAppWindow(_ window: NSWindow) -> Bool {
        window.title == "TimeMachine++" && window.canBecomeMain
    }
}
