import AppKit
import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(AppStateStore.self) private var store
    @Binding var isShowingSettings: Bool
    @State private var helperObserver: NSObjectProtocol?

    var body: some View {
        RulesView()
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .environment(store)
                    .frame(minWidth: 640, minHeight: 620)
            }
            .onAppear(perform: onAppear)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.refreshHelperStatus()
            }
            .onDisappear(perform: onDisappear)
    }
}

extension ContentView {
    private func onAppear() {
        store.refreshHelperStatus()
        guard helperObserver == nil else { return }
        helperObserver = DistributedNotificationCenter.default().addObserver(
            forName: HelperNotifications.scanDidFinish,
            object: nil,
            queue: .main
        ) { _ in
            Task { await store.refreshHelperStatus() }
        }
    }

    private func onDisappear() {
        if let helperObserver {
            DistributedNotificationCenter.default().removeObserver(helperObserver)
            self.helperObserver = nil
        }
    }
}
