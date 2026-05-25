import AppKit
import Foundation

enum HelperNotifications {
    static let scanDidFinish = Notification.Name("consequential.timemachineplusplus.helper.scanDidFinish")

    static func postScanDidFinish() {
        DistributedNotificationCenter.default().postNotificationName(
            scanDidFinish,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

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
        let snapshot = launchAgent.snapshot()
        isHelperInstalled = snapshot.isInstalled
        isHelperLoaded = snapshot.isLoaded
        isHelperRunning = snapshot.isRunning
        helperRunCount = snapshot.runCount
        helperLastExitCode = snapshot.lastExitCode

        let state = storage.load()
        lastHelperScanDate = state.lastHelperScanDate
        lastHelperScannedItemCount = state.lastHelperScannedItemCount
        lastHelperAddedExclusionCount = state.lastHelperAddedExclusionCount
    }

    #if DEBUG
    func runDebugHelperScanNow() {
        guard canEdit else { return }
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            guard beginBlockingOperation(title: "Debug Helper Scan") else {
                activeTask = nil
                return
            }
            updateOperation(detail: "Starting helper process", progress: nil)

            do {
                let result = try await launchAgent.runBackgroundScanProcess()
                load()
                finishBlockingOperation(
                    status: result.isSuccess ? "Debug helper scan finished" : "Debug helper scan failed"
                )
            } catch {
                finishBlockingOperation(status: "Debug helper scan failed: \(error.localizedDescription)")
            }

            activeTask = nil
        }
    }

    func clearDebugHelperScanInfo() {
        lastHelperScanDate = nil
        lastHelperScannedItemCount = 0
        lastHelperAddedExclusionCount = 0
        statusMessage = "Cleared helper scan info"
        save()
    }
    #endif
}
