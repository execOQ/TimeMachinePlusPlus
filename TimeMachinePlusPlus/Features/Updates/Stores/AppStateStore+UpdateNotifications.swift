import Foundation
import UserNotifications

extension AppStateStore {
    func requestUpdateNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyUpdateReadyIfNeeded(version: String, name: String) {
        guard AppUpdateNotificationPolicy.shouldNotify(version: version, lastNotifiedVersion: lastNotifiedUpdateVersion) else { return }
        lastNotifiedUpdateVersion = version
        save()

        requestUpdateNotificationPermission()

        let content = UNMutableNotificationContent()
        content.title = "New TimeMachine++ update is available"
        content.body = "\(name) is downloaded and ready to install."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "timemachineplusplus-update-\(version)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
