import AppKit
import Foundation

extension AppStateStore {
    func load() {
        var state = storage.load()
        var shouldSaveMigratedState = false

        // Migrate legacy manual exclusions into specific rules
        if !state.manualExclusions.isEmpty {
            let existing = Set(state.rules.filter { $0.kind == .specific }.map(\.pattern))
            let migrated = state.manualExclusions
                .filter { !existing.contains($0.path) }
                .map { manual in
                    let name = URL(fileURLWithPath: manual.path).lastPathComponent
                    return RegexRule(name: name, pattern: manual.path, kind: .specific, isEnabled: manual.isEnabled, includeFiles: true)
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
                    snapshotSizeCache: state.snapshotSizeCache,
                    lastHelperScanDate: state.lastHelperScanDate,
                    lastHelperScannedItemCount: state.lastHelperScannedItemCount,
                    lastHelperAddedExclusionCount: state.lastHelperAddedExclusionCount
                )
            )
        }

        rules = state.rules
        manualExclusions = state.manualExclusions
        appliedExclusions = state.appliedExclusions
        settings = state.settings
        snapshotSizeCache = state.snapshotSizeCache
        lastHelperScanDate = state.lastHelperScanDate
        lastHelperScannedItemCount = state.lastHelperScannedItemCount
        lastHelperAddedExclusionCount = state.lastHelperAddedExclusionCount
        refreshHelperStatus()
        refreshFullDiskAccessStatus()
    }

    func refreshTimeMachineState() async {
        refreshFullDiskAccessStatus()

        do {
            let destinationResult = try timeMachine.run(arguments: ["destinationinfo", "-X"], asAdministrator: false)
            let mountOutput = Self.commandOutput(executablePath: "/sbin/mount")
            timeMachineDestinations = TimeMachineStateParser.destinations(
                from: destinationResult,
                mountOutput: mountOutput,
                diskImageOutput: Self.commandOutput(executablePath: "/usr/bin/hdiutil", arguments: ["info"])
            )
            backupHistoriesByDestinationID = await loadBackupHistories(
                for: timeMachineDestinations,
                mountOutput: mountOutput
            )
        } catch {
            timeMachineDestinations = []
            backupHistoriesByDestinationID = [:]
        }

        do {
            let statusResult = try timeMachine.run(arguments: ["status"], asAdministrator: false)
            backupStatus = TimeMachineStateParser.backupStatus(from: statusResult)
        } catch {
            backupStatus = .unknown
        }
        syncBackupSleepPrevention()

        do {
            let snapshotResult = try timeMachine.run(arguments: ["listlocalsnapshotdates", "/"], asAdministrator: false)
            localSnapshotDates = TimeMachineStateParser.snapshotDates(from: snapshotResult)
        } catch {
            localSnapshotDates = []
        }
    }

    func refreshFullDiskAccessStatus() {
        fullDiskAccessStatus = FullDiskAccessSupport.status
    }

    func loadBackupHistories(for destinations: [TimeMachineDestination], mountOutput: String) async -> [String: TimeMachineBackupHistory] {
        await Task.detached(priority: .utility) { [timeMachine] in
            var histories: [String: TimeMachineBackupHistory] = [:]

            for destination in destinations {
                guard let mountPoint = destination.mountPoint else {
                    if let sparsebundlePath = destination.sparsebundlePath {
                        let backups = TimeMachineStateParser.sparsebundleSnapshots(
                            sparsebundlePath: sparsebundlePath
                        )
                        histories[destination.id] = TimeMachineBackupHistory(
                            destinationID: destination.id,
                            backups: backups,
                            machineDirectories: [],
                            message: backups.isEmpty
                                ? "Network sparsebundle is available, but no snapshot history was found."
                                : "Showing backup history from the network sparsebundle. Mount a snapshot before compare or restore.",
                            requiresFullDiskAccess: false,
                            noBackupsForCurrentHost: false
                        )
                        continue
                    }

                    histories[destination.id] = TimeMachineBackupHistory(
                        destinationID: destination.id,
                        backups: [],
                        machineDirectories: [],
                        message: "Destination is configured, but its backup volume is not mounted right now.",
                        requiresFullDiskAccess: false,
                        noBackupsForCurrentHost: false
                    )
                    continue
                }

                do {
                    let result = try timeMachine.run(arguments: ["listbackups", "-d", mountPoint], asAdministrator: false)
                    var history = TimeMachineStateParser.backupHistory(destinationID: destination.id, from: result)
                    if history.backups.isEmpty {
                        history.backups = TimeMachineStateParser.mountedBackupSnapshots(
                            destinationMountPoint: mountPoint,
                            mountOutput: mountOutput
                        )
                        if !history.backups.isEmpty {
                            history.message = nil
                            history.requiresFullDiskAccess = false
                            history.noBackupsForCurrentHost = false
                        }
                    }
                    if history.backups.isEmpty, let sparsebundlePath = destination.sparsebundlePath {
                        history.backups = TimeMachineStateParser.sparsebundleSnapshots(
                            sparsebundlePath: sparsebundlePath
                        )
                        if !history.backups.isEmpty {
                            history.message = "Showing backup history from the network sparsebundle. Mount a snapshot before compare or restore."
                            history.requiresFullDiskAccess = false
                            history.noBackupsForCurrentHost = false
                        }
                    }
                    if history.noBackupsForCurrentHost {
                        let machineResult = try? timeMachine.run(arguments: ["listbackups", "-m", "-d", mountPoint], asAdministrator: false)
                        history.machineDirectories = machineResult.map(TimeMachineStateParser.machineDirectories(from:)) ?? []
                    }
                    histories[destination.id] = history
                } catch {
                    histories[destination.id] = TimeMachineBackupHistory(
                        destinationID: destination.id,
                        backups: [],
                        machineDirectories: [],
                        message: error.localizedDescription,
                        requiresFullDiskAccess: false,
                        noBackupsForCurrentHost: false
                    )
                }
            }

            return histories
        }.value
    }

    static func commandOutput(executablePath: String, arguments: [String] = []) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    func save() {
        storage.save(
            PersistedState(
                rules: rules,
                manualExclusions: manualExclusions,
                appliedExclusions: appliedExclusions,
                settings: settings,
                snapshotSizeCache: snapshotSizeCache,
                lastHelperScanDate: lastHelperScanDate,
                lastHelperScannedItemCount: lastHelperScannedItemCount,
                lastHelperAddedExclusionCount: lastHelperAddedExclusionCount
            )
        )
    }

    func recordHelperScan(scannedItemCount: Int, addedExclusionCount: Int) {
        lastHelperScanDate = Date()
        lastHelperScannedItemCount = scannedItemCount
        lastHelperAddedExclusionCount = addedExclusionCount
        save()
    }

}
