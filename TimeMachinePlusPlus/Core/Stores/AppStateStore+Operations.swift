import AppKit
import Foundation

extension AppStateStore {
    func startScanNow() {
        startOperation(title: "Scanning") { store in
            await store.scanNow()
        }
    }

    func startApplySelectedMatches() {
        startOperation(title: "Applying Exclusions") { store in
            await store.applySelectedMatches()
        }
    }

    func startConfiguredStartAction() {
        startScanAndApplyExclusions()
    }

    func startScanAndApplyExclusions() {
        startOperation(title: "Scan + Apply") { store in
            await store.scanAndApplyExclusions()
        }
    }

    func startScanAndBackup() {
        startOperation(title: "Scan + Backup") { store in
            await store.scanAndStartBackup()
        }
    }

    func cancelOperation() {
        guard isWorking, canCancelCurrentOperation else { return }
        activeTask?.cancel()

        if didStartBackupDuringActiveTask {
            statusMessage = "Cancelling backup..."
            rulesStatusMessage = statusMessage
            _ = try? timeMachine.stopBackup()
        } else {
            statusMessage = "Cancelling..."
            rulesStatusMessage = statusMessage
        }
    }

    func startOperation(title: String, _ operation: @escaping @MainActor (AppStateStore) async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        canCancelCurrentOperation = true
        operationTitle = title
        operationDetail = nil
        operationProgress = nil
        rulesStatusMessage = title
        didStartBackupDuringActiveTask = false
        beginSleepPrevention(reason: title)

        activeTask = Task { [weak self] in
            guard let self else { return }
            await operation(self)
            if self.isWorking {
                self.finishOperation(status: Task.isCancelled ? "Cancelled" : nil)
            }
        }
    }

    func finishOperation(status: String? = nil) {
        if let status {
            statusMessage = status
            rulesStatusMessage = status
        }
        isWorking = false
        canCancelCurrentOperation = true
        operationTitle = nil
        operationDetail = nil
        operationProgress = nil
        didStartBackupDuringActiveTask = false
        activeTask = nil
        endSleepPrevention()
    }

    func beginBlockingOperation(title: String) -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        canCancelCurrentOperation = false
        operationTitle = title
        operationDetail = nil
        operationProgress = nil
        statusMessage = title
        rulesStatusMessage = title
        beginSleepPrevention(reason: title)
        return true
    }

    func finishBlockingOperation(status: String) {
        statusMessage = status
        rulesStatusMessage = status
        isWorking = false
        canCancelCurrentOperation = true
        operationTitle = nil
        operationDetail = nil
        operationProgress = nil
        endSleepPrevention()
    }

    func updateOperation(detail: String, progress: Double?, updateStatus: Bool = true) {
        if isWorking {
            operationDetail = detail
            operationProgress = progress
        }
        if updateStatus {
            statusMessage = detail
            rulesStatusMessage = detail
        }
    }

    func beginSleepPrevention(reason: String) {
        endSleepPrevention()
        operationActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    func endSleepPrevention() {
        guard let operationActivityToken else { return }
        ProcessInfo.processInfo.endActivity(operationActivityToken)
        self.operationActivityToken = nil
    }

    func syncBackupSleepPrevention() {
        if backupStatus.isRunning {
            beginBackupSleepPrevention()
            startBackupSleepMonitor()
        } else {
            endBackupSleepPrevention()
        }
    }

    func beginBackupSleepPrevention() {
        guard backupActivityToken == nil else { return }
        backupActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Time Machine backup"
        )
    }

    func endBackupSleepPrevention() {
        backupActivityTask?.cancel()
        backupActivityTask = nil
        guard let backupActivityToken else { return }
        ProcessInfo.processInfo.endActivity(backupActivityToken)
        self.backupActivityToken = nil
    }

    func startBackupSleepMonitor() {
        guard backupActivityTask == nil else { return }
        backupActivityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshBackupStatusForSleepPrevention()
            }
        }
    }

    func refreshBackupStatusForSleepPrevention() async {
        let nextStatus = await Task.detached(priority: .utility) { [timeMachine] in
            do {
                let result = try timeMachine.run(arguments: ["status"], asAdministrator: false)
                return TimeMachineStateParser.backupStatus(from: result)
            } catch {
                return .unknown
            }
        }.value
        backupStatus = nextStatus
        syncBackupSleepPrevention()
    }

    func confirmedBackupStatusAfterStart() async -> TimeMachineBackupStatus {
        for attempt in 0..<5 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return backupStatus }

            let nextStatus = await Task.detached(priority: .utility) { [timeMachine] in
                do {
                    let result = try timeMachine.run(arguments: ["status"], asAdministrator: false)
                    return TimeMachineStateParser.backupStatus(from: result)
                } catch {
                    return .unknown
                }
            }.value

            if nextStatus.isRunning {
                return nextStatus
            }
            backupStatus = nextStatus
        }

        return backupStatus
    }

}
