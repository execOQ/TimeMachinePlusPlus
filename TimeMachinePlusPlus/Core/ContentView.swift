import AppKit
import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(AppStateStore.self) private var store
    @Binding var isShowingSettings: Bool
    @State private var helperObserver = HelperNotificationObserver()

    var body: some View {
        RulesView()
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification),
                perform: onAppDidBecomeActive
            )
    }
}

extension ContentView {
    // MARK: - Lifecycle

    private func onAppear() {
        store.refreshHelperStatus()
        helperObserver.start {
            store.refreshHelperStatus()
        }
    }

    private func onDisappear() {
        helperObserver.stop()
    }

    // MARK: - Actions

    private func onAppDidBecomeActive(_ notification: Notification) {
        store.refreshHelperStatus()
    }
}
