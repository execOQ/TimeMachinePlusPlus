import AppKit
import SwiftUI

enum FloatingPanel {
    static func present<V: View>(_ rootView: V, title: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()

        let hosting = NSHostingController(rootView: rootView)
        panel.contentViewController = hosting

        // Show the panel. If the app is inactive, make it key without activating the app.
        if NSApp.isActive {
            panel.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: false)
            panel.orderFrontRegardless()
        }
    }
}
