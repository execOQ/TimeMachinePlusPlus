import AppKit
import Foundation

extension AppStateStore {
    func scanAndStartBackup() async {
        updateOperation(detail: "Preparing scan", progress: 0.05)
        await scanNow()
        guard !Task.isCancelled else { return }
        await applySelectedMatches()
        guard !Task.isCancelled else { return }

        do {
            didStartBackupDuringActiveTask = true
            updateOperation(detail: "Starting Time Machine backup", progress: 0.94)
            let result = try timeMachine.startBackup()
            if result.isSuccess {
                updateOperation(detail: "Confirming backup status", progress: 0.97)
                backupStatus = await confirmedBackupStatusAfterStart()
                syncBackupSleepPrevention()
                statusMessage = backupStatus.isRunning
                    ? "Backup started after applying exclusions"
                    : "Backup request sent, but Time Machine is not running"
            } else {
                statusMessage = "Exclusions applied, but backup did not start"
            }
            updateOperation(
                detail: result.isSuccess && backupStatus.isRunning ? "Backup started" : "Backup did not start",
                progress: 1.0,
                updateStatus: false
            )
        } catch {
            statusMessage = "Exclusions applied, but backup did not start: \(error.localizedDescription)"
            updateOperation(detail: "Backup did not start", progress: 1.0, updateStatus: false)
        }
    }

    func scanAndApplyExclusions() async {
        updateOperation(detail: "Preparing scan", progress: 0.05)
        await scanNow()
        guard !Task.isCancelled else { return }
        await applySelectedMatches()
        guard !Task.isCancelled else { return }
        updateOperation(detail: "Scan and exclusions finished", progress: 1.0, updateStatus: false)
    }

}
