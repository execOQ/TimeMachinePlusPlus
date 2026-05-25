import AppKit
import Foundation
import Observation
import SwiftUI
import UserNotifications

@main
enum TimeMachinePlusPlusMain {
    static func main() {
        if TimeMachinePlusPlusApp.isBackgroundScan {
            runBackgroundScan()
        } else {
            TimeMachinePlusPlusApp.main()
        }
    }

    private static func runBackgroundScan() {
        var isFinished = false

        Task { @MainActor in
            let store = AppStateStore()
            store.load()
            _ = store.beginBlockingOperation(title: "Background Scan")
            await store.scanNow()
            let scannedItemCount = store.matches.count
            let addedExclusionCount = await store.applySelectedMatches(refreshAfterApply: false)
            store.recordHelperScan(
                scannedItemCount: scannedItemCount,
                addedExclusionCount: addedExclusionCount
            )
            HelperNotifications.postScanDidFinish()
            store.finishBlockingOperation(status: store.statusMessage)
            isFinished = true
        }

        while !isFinished {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

struct TimeMachinePlusPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStateStore

    init() {
        let store = AppStateStore()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup("TimeMachine++", id: "main") {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
                .environment(store)
                .task {
                    store.load()
                    if !Self.isRunningUnitTests {
                        await store.refreshTimeMachineState()
                        store.checkForUpdatesAutomaticallyIfNeeded()
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

        MenuBarExtra("TimeMachine++", systemImage: store.updateMenuBarSystemImage) {
            MenuBarContentView()
                .environment(store)
        }
    }

    fileprivate static var isBackgroundScan: Bool {
        CommandLine.arguments.contains("--background-scan")
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if TimeMachinePlusPlusApp.isBackgroundScan {
            NSApp.setActivationPolicy(.accessory)
            return
        }

        UNUserNotificationCenter.current().delegate = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessRegistry.shared.terminateAll()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
