import Foundation
import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppStateStore.self) private var store
    @State private var helperObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            AppNavigationView()
            BlockingOperationOverlayHost()
        }
        .onAppear {
            store.refreshHelperStatus()
            guard helperObserver == nil else { return }
            helperObserver = DistributedNotificationCenter.default().addObserver(
                forName: HelperNotifications.scanDidFinish,
                object: nil,
                queue: .main
            ) { _ in
                store.refreshHelperStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshHelperStatus()
        }
        .onDisappear {
            if let helperObserver {
                DistributedNotificationCenter.default().removeObserver(helperObserver)
                self.helperObserver = nil
            }
        }
    }
}

private struct AppNavigationView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailRouterView()
                .safeAreaInset(edge: .bottom) {
                    StatusBarView()
                }
        }
    }
}

private struct BlockingOperationOverlayHost: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        if store.isWorking {
            BlockingOperationOverlay(
                title: store.operationTitle ?? "Working",
                detail: store.operationDetail,
                progress: store.operationProgress,
                canCancel: store.canCancelCurrentOperation,
                onCancel: { store.cancelOperation() }
            )
        }
    }
}
