import Foundation

extension AppStateStore {
    func scanAndApplyExclusions() async {
        updateOperation(detail: "Preparing scan", progress: 0.05)
        await scanNow()
        guard !Task.isCancelled else { return }
        await applySelectedMatches()
        guard !Task.isCancelled else { return }
        updateOperation(detail: "Scan and exclusions finished", progress: 1.0, updateStatus: false)
    }

}
