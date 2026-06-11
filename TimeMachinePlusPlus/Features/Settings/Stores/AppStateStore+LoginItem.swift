import Foundation

extension AppStateStore {
    func refreshLoginItemStatus() {
        isLoginItemEnabled = loginItem.isEnabled
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try loginItem.setEnabled(isEnabled)
            refreshLoginItemStatus()
            statusMessage = isEnabled ? "TimeMachine++ will open at login" : "TimeMachine++ will not open at login"
        } catch {
            refreshLoginItemStatus()
            statusMessage = "Could not update login item: \(error.localizedDescription)"
        }
    }
}
