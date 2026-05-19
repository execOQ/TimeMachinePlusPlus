import AppKit
import Observation
import SwiftUI

@main
struct TimeMachinePlusPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var store: AppStateStore

    init() {
        let store = AppStateStore()
        _store = State(initialValue: store)

        if Self.isBackgroundScan {
            Task { @MainActor in
                store.load()
                _ = store.beginBlockingOperation(title: "Background Scan")
                await store.scanNow()
                await store.applySelectedMatches()
                store.finishBlockingOperation(status: store.statusMessage)
                NSApp.terminate(nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup("TimeMachine++", id: "main") {
            if Self.isBackgroundScan {
                BackgroundScanPlaceholder()
            } else {
                ContentView()
                    .frame(minWidth: 980, minHeight: 640)
                    .environment(store)
                    .task {
                        store.load()
                        if !Self.isRunningUnitTests {
                            await store.refreshTimeMachineState()
                        }
                    }
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button(store.startActionTitle) {
                    store.startConfiguredStartAction()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("TimeMachine++", systemImage: "clock.arrow.circlepath") {
            if Self.isBackgroundScan {
                EmptyView()
            } else {
                MenuBarContentView()
                    .environment(store)
            }
        }
    }

    fileprivate static var isBackgroundScan: Bool {
        CommandLine.arguments.contains("--background-scan")
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private struct BackgroundScanPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task {
                NSApp.hide(nil)
                NSApp.windows.forEach { $0.close() }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if TimeMachinePlusPlusApp.isBackgroundScan {
            NSApp.setActivationPolicy(.accessory)
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessRegistry.shared.terminateAll()
    }
}
