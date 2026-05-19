import AppKit
import Foundation

extension AppStateStore {
    func installBackgroundAgent() {
        guard canEdit else { return }
        do {
            try launchAgent.install(intervalMinutes: settings.scanIntervalMinutes)
            refreshHelperStatus()
            statusMessage = "Background scanner installed"
        } catch {
            refreshHelperStatus()
            statusMessage = "Could not install background scanner: \(error.localizedDescription)"
        }
    }

    func uninstallBackgroundAgent() {
        guard canEdit else { return }
        do {
            try launchAgent.uninstall()
            refreshHelperStatus()
            statusMessage = "Background scanner removed"
        } catch {
            refreshHelperStatus()
            statusMessage = "Could not remove background scanner: \(error.localizedDescription)"
        }
    }

    func refreshHelperStatus() {
        isHelperInstalled = launchAgent.isInstalled
    }
}
