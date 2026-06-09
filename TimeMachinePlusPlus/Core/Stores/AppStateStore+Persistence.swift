import AppKit
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
                    snapshotSizeCache: state.snapshotSizeCache,
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
        snapshotSizeCache = state.snapshotSizeCache
        lastHelperScanDate = state.lastHelperScanDate
        lastHelperScannedItemCount = state.lastHelperScannedItemCount
        lastHelperAddedExclusionCount = state.lastHelperAddedExclusionCount
        lastUpdateCheckDate = state.lastUpdateCheckDate
        lastNotifiedUpdateVersion = state.lastNotifiedUpdateVersion
        refreshHelperStatus()
        refreshFullDiskAccessStatus()
        refreshLoginItemStatus()
    }

    func refreshTimeMachineState() async {
        refreshFullDiskAccessStatus()

        do {
            let destinationResult = try timeMachine.run(arguments: ["destinationinfo", "-X"], asAdministrator: false)
            let mountOutput = Self.commandOutput(executablePath: "/sbin/mount")
            let diskImageOutput = Self.commandOutput(executablePath: "/usr/bin/hdiutil", arguments: ["info"])
            timeMachineDestinations = TimeMachineStateParser.destinations(
                from: destinationResult,
                mountOutput: mountOutput,
                diskImageOutput: diskImageOutput
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
                                : "Showing backup history from the network sparsebundle. Mount a snapshot before compare.",
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
                    let mountedSnapshots = TimeMachineStateParser.mountedBackupSnapshots(
                        destinationMountPoint: mountPoint,
                        mountOutput: mountOutput
                    )
                    if history.backups.isEmpty {
                        history.backups = mountedSnapshots
                        if !history.backups.isEmpty {
                            history.message = nil
                            history.requiresFullDiskAccess = false
                            history.noBackupsForCurrentHost = false
                        }
                    } else {
                        let mountedBackups = TimeMachineStateParser.mountedBackupSnapshotPaths(
                            destinationMountPoint: mountPoint,
                            backupPaths: history.backups
                        )
                        let resolvedBackups = mountedSnapshots.isEmpty
                            ? mountedBackups
                            : Self.mergedBackupPaths(primary: mountedSnapshots, secondary: mountedBackups)
                        if resolvedBackups != history.backups {
                            history.backups = resolvedBackups
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
                            history.message = "Showing backup history from the network sparsebundle. Mount a snapshot before compare."
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

    nonisolated static func commandOutput(executablePath: String, arguments: [String] = []) -> String {
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

    func mountNetworkShare(for destination: TimeMachineDestination) {
        guard let urlString = destination.url else { return }
        attemptedNetworkShareMounts.remove(destination.id)
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            guard beginBlockingOperation(title: "Mount Network Share") else {
                activeTask = nil
                return
            }
            statusMessage = "Connecting \(destination.name)..."
            await Self.openNetworkShare(urlString)
            attemptedNetworkShareMounts.insert(destination.id)
            await refreshTimeMachineState()
            finishBlockingOperation(status: "Network share refresh finished")
            activeTask = nil
        }
    }

    func mountNetworkShareIfNeeded(for destination: TimeMachineDestination) async {
        guard destination.isNetworkShareMissing,
              let urlString = destination.url,
              !attemptedNetworkShareMounts.contains(destination.id) else {
            return
        }

        attemptedNetworkShareMounts.insert(destination.id)
        statusMessage = "Connecting \(destination.name)..."
        await Self.openNetworkShare(urlString)
        await refreshTimeMachineState()
    }

    nonisolated private static func mergedBackupPaths(primary: [String], secondary: [String]) -> [String] {
        (primary + secondary)
            .reduce(into: (paths: [String](), identities: Set<String>())) { result, path in
                let identity = backupSnapshotIdentity(path)
                if !result.identities.contains(identity) {
                    result.paths.append(path)
                    result.identities.insert(identity)
                }
            }
            .paths
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    nonisolated private static func backupSnapshotIdentity(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents.reversed()
        if let backupComponent = components.first(where: { $0.lowercased().hasSuffix(".backup") }) {
            return String(backupComponent.dropLast(".backup".count))
        }

        if let dateComponent = components.first(where: { component in
            component.range(
                of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#,
                options: .regularExpression
            ) != nil
        }) {
            return dateComponent
        }

        return path
    }

    static func openNetworkShare(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)

        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
        }
    }

    static func attachBackupImage(at path: String) async -> CommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", "-readonly", "-nobrowse", path]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            ProcessRegistry.shared.register(process)

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                ProcessRegistry.shared.deregister(process)
                return CommandResult(exitCode: -1, output: "", errorOutput: error.localizedDescription)
            }
            ProcessRegistry.shared.deregister(process)

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return CommandResult(exitCode: process.terminationStatus, output: output, errorOutput: errorOutput)
        }.value
    }

    nonisolated static func backupImageAttachStatus(for path: String) -> String {
        let devices = attachedDevices(forBackupImageAt: path)
        let processOutput = commandOutput(
            executablePath: "/bin/ps",
            arguments: ["-axo", "pid,etime,comm,args"]
        )
        let lines = processOutput.components(separatedBy: .newlines)

        if let fsckLine = lines.first(where: { line in
            line.localizedCaseInsensitiveContains("fsck_apfs")
                && devices.contains { line.contains($0) }
        }) {
            let elapsed = fsckLine
                .split(separator: " ", omittingEmptySubsequences: true)
                .dropFirst()
                .first
                .map(String.init) ?? ""
            return elapsed.isEmpty
                ? "Checking APFS filesystem before mounting..."
                : "Checking APFS filesystem before mounting (\(elapsed))..."
        }

        if lines.contains(where: { $0.localizedCaseInsensitiveContains("hdiutil attach") && $0.contains(path) }) {
            return "Opening sparsebundle image over the network..."
        }

        if !devices.isEmpty {
            return "Image device is attached; waiting for macOS to publish a mounted snapshot volume..."
        }

        return "Starting disk image attach..."
    }

    nonisolated static func detachBackupImageIfAttached(at path: String) {
        let devices = attachedDevices(forBackupImageAt: path)
        guard let device = devices.first else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", "-force", device]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    nonisolated private static func attachedDevices(forBackupImageAt path: String) -> [String] {
        let info = commandOutput(executablePath: "/usr/bin/hdiutil", arguments: ["info"])
        let blocks = info.components(separatedBy: "================================================")
        guard let block = blocks.first(where: { $0.contains("image-path") && $0.contains(path) }) else {
            return []
        }

        return block.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { line -> String? in
                guard line.hasPrefix("/dev/disk") else { return nil }
                return line.components(separatedBy: .whitespaces).first
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
                lastHelperAddedExclusionCount: lastHelperAddedExclusionCount,
                lastUpdateCheckDate: lastUpdateCheckDate,
                lastNotifiedUpdateVersion: lastNotifiedUpdateVersion
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
