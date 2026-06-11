import Foundation

extension AppStateStore {
    func load() {
        var state = storage.load()
        var shouldSaveMigratedState = false

        // Migrate legacy manual exclusions into path rules.
        if !state.manualExclusions.isEmpty {
            let existing = Set(state.rules.filter { $0.kind == .path }.map(\.pattern))
            let migrated = state.manualExclusions
                .filter { !existing.contains($0.path) }
                .map { manual in
                    let name = URL(fileURLWithPath: manual.path).lastPathComponent
                    return RegexRule(name: name, pattern: manual.path, kind: .path, isEnabled: manual.isEnabled, includeFiles: true)
            }
            state.rules.append(contentsOf: migrated)
            state.manualExclusions = []
            shouldSaveMigratedState = true
        }

        if state.settings.scanIntervalMinutes == 30 {
            state.settings.scanIntervalMinutes = AppSettings.dailyScanIntervalMinutes
            shouldSaveMigratedState = true
        }

        if shouldSaveMigratedState {
            storage.save(
                PersistedState(
                    rules: state.rules,
                    manualExclusions: [],
                    appliedExclusions: state.appliedExclusions,
                    settings: state.settings,
                    lastHelperScanDate: state.lastHelperScanDate,
                    lastHelperScannedItemCount: state.lastHelperScannedItemCount,
                    lastHelperAddedExclusionCount: state.lastHelperAddedExclusionCount,
                    lastUpdateCheckDate: state.lastUpdateCheckDate,
                    lastNotifiedUpdateVersion: state.lastNotifiedUpdateVersion
                )
            )
        }

        rules = state.rules
        manualExclusions = state.manualExclusions
        appliedExclusions = state.appliedExclusions
        settings = state.settings
        lastHelperScanDate = state.lastHelperScanDate
        lastHelperScannedItemCount = state.lastHelperScannedItemCount
        lastHelperAddedExclusionCount = state.lastHelperAddedExclusionCount
        lastUpdateCheckDate = state.lastUpdateCheckDate
        lastNotifiedUpdateVersion = state.lastNotifiedUpdateVersion
        refreshHelperStatus()
        refreshFullDiskAccessStatus()
        refreshLoginItemStatus()
    }

    func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = FullDiskAccessSupport.status
    }

    func save() {
        storage.save(persistedStateSnapshot)
    }

    func saveInBackground() {
        let state = persistedStateSnapshot
        let storage = storage
        Task.detached(priority: .utility) {
            storage.save(state)
        }
    }

    func recordHelperScan(scannedItemCount: Int, addedExclusionCount: Int) {
        lastHelperScanDate = Date()
        lastHelperScannedItemCount = scannedItemCount
        lastHelperAddedExclusionCount = addedExclusionCount
        save()
    }

}

private extension AppStateStore {
    var persistedStateSnapshot: PersistedState {
        PersistedState(
            rules: rules,
            manualExclusions: manualExclusions,
            appliedExclusions: appliedExclusions,
            settings: settings,
            lastHelperScanDate: lastHelperScanDate,
            lastHelperScannedItemCount: lastHelperScannedItemCount,
            lastHelperAddedExclusionCount: lastHelperAddedExclusionCount,
            lastUpdateCheckDate: lastUpdateCheckDate,
            lastNotifiedUpdateVersion: lastNotifiedUpdateVersion
        )
    }
}
