import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            AppNavigationView()
            BlockingOperationOverlayHost()
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
