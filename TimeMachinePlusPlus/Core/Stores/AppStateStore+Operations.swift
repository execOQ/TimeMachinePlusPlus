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

    func cancelOperation() {
        guard isWorking, canCancelCurrentOperation else { return }
        activeTask?.cancel()
        statusMessage = "Cancelling..."
        rulesStatusMessage = statusMessage
    }

    func startOperation(title: String, _ operation: @escaping @MainActor (AppStateStore) async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        canCancelCurrentOperation = true
        operationTitle = title
        operationDetail = nil
        operationProgress = nil
        rulesStatusMessage = title
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

}
