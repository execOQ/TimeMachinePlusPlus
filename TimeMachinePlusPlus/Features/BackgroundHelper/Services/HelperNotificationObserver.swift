import Foundation

final class HelperNotificationObserver {
    private var token: NSObjectProtocol?

    func start(onScanDidFinish: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = DistributedNotificationCenter.default().addObserver(
            forName: HelperNotifications.scanDidFinish,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onScanDidFinish()
            }
        }
    }

    func stop() {
        guard let token else { return }
        DistributedNotificationCenter.default().removeObserver(token)
        self.token = nil
    }

    deinit {
        stop()
    }
}
