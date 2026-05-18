import AppKit
import Foundation

@MainActor
final class AppStateStore: ObservableObject {
    @Published var rules: [RegexRule] = []
    @Published var manualExclusions: [ManualExclusion] = []
    @Published var appliedExclusions: [AppliedExclusion] = []
    @Published var settings: AppSettings = .defaults
    @Published var snapshotSizeCache: [String: Int64] = [:]
    @Published var matches: [ScanMatch] = []
    @Published var selectedSelection: AppSidebarSelection? = .section(.exclusionRules)
    @Published var statusMessage = "Ready"
    @Published var lastScanDate: Date?
    @Published var isWorking = false
    @Published var canCancelCurrentOperation = true
    @Published var operationTitle: String?
    @Published var operationDetail: String?
    @Published var operationProgress: Double?
    @Published var isHelperInstalled = false
    @Published var timeMachineDestinations: [TimeMachineDestination] = []
    @Published var backupHistoriesByDestinationID: [String: TimeMachineBackupHistory] = [:]
    @Published var backupStatus: TimeMachineBackupStatus = .unknown
    @Published var localSnapshotDates: [String] = []
    @Published var fullDiskAccessStatus: FullDiskAccessStatus = .missing
    @Published var isMeasuringSizes = false

    private let storage = StateStorage()
    private let scanner = FileSystemScanner()
    private let timeMachine: TimeMachineClient
    private let launchAgent = LaunchAgentService()
    private var activeTask: Task<Void, Never>?
    private var didStartBackupDuringActiveTask = false
    private var operationActivityToken: NSObjectProtocol?
    private var backupActivityToken: NSObjectProtocol?
    private var backupActivityTask: Task<Void, Never>?

    var canEdit: Bool { !isWorking }

    init(timeMachine: TimeMachineClient = LiveTimeMachineClient()) {
        self.timeMachine = timeMachine
    }

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
                    snapshotSizeCache: state.snapshotSizeCache
                )
            )
        }

        rules = state.rules
        manualExclusions = state.manualExclusions
        appliedExclusions = state.appliedExclusions
        settings = state.settings
        snapshotSizeCache = state.snapshotSizeCache
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

    private func loadBackupHistories(for destinations: [TimeMachineDestination], mountOutput: String) async -> [String: TimeMachineBackupHistory] {
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

    private static func commandOutput(executablePath: String, arguments: [String] = []) -> String {
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
                snapshotSizeCache: snapshotSizeCache
            )
        )
    }

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
            _ = try? timeMachine.stopBackup()
        } else {
            statusMessage = "Cancelling..."
        }
    }

    private func startOperation(title: String, _ operation: @escaping @MainActor (AppStateStore) async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        canCancelCurrentOperation = true
        operationTitle = title
        operationDetail = nil
        operationProgress = nil
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

    private func finishOperation(status: String? = nil) {
        if let status {
            statusMessage = status
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
        beginSleepPrevention(reason: title)
        return true
    }

    func finishBlockingOperation(status: String) {
        statusMessage = status
        isWorking = false
        canCancelCurrentOperation = true
        operationTitle = nil
        operationDetail = nil
        operationProgress = nil
        endSleepPrevention()
    }

    private func updateOperation(detail: String, progress: Double?, updateStatus: Bool = true) {
        if isWorking {
            operationDetail = detail
            operationProgress = progress
        }
        if updateStatus {
            statusMessage = detail
        }
    }

    private func beginSleepPrevention(reason: String) {
        endSleepPrevention()
        operationActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    private func endSleepPrevention() {
        guard let operationActivityToken else { return }
        ProcessInfo.processInfo.endActivity(operationActivityToken)
        self.operationActivityToken = nil
    }

    private func syncBackupSleepPrevention() {
        if backupStatus.isRunning {
            beginBackupSleepPrevention()
            startBackupSleepMonitor()
        } else {
            endBackupSleepPrevention()
        }
    }

    private func beginBackupSleepPrevention() {
        guard backupActivityToken == nil else { return }
        backupActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Time Machine backup"
        )
    }

    private func endBackupSleepPrevention() {
        backupActivityTask?.cancel()
        backupActivityTask = nil
        guard let backupActivityToken else { return }
        ProcessInfo.processInfo.endActivity(backupActivityToken)
        self.backupActivityToken = nil
    }

    private func startBackupSleepMonitor() {
        guard backupActivityTask == nil else { return }
        backupActivityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshBackupStatusForSleepPrevention()
            }
        }
    }

    private func refreshBackupStatusForSleepPrevention() async {
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

    func addRule() {
        guard canEdit else { return }
        rules.append(RegexRule(name: "New rule", pattern: "cache/", kind: .gitignore, isEnabled: false))
        save()
    }

    func deleteRule(_ rule: RegexRule) {
        guard canEdit else { return }
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func addSpecificPaths(_ urls: [URL]) {
        guard canEdit else { return }
        let known = Set(rules.filter { $0.kind == .specific }.map(\.pattern))
        let additions = urls.map(\.path).filter { !known.contains($0) }
        let newRules = additions.map { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return RegexRule(name: name, pattern: path, kind: .specific, isEnabled: true, includeFiles: true)
        }
        rules.append(contentsOf: newRules)
        save()
    }

    func addScanRoots(_ urls: [URL]) {
        guard canEdit else { return }
        let known = Set(settings.scanRoots)
        settings.scanRoots.append(contentsOf: urls.map(\.path).filter { !known.contains($0) })
        save()
    }

    func deleteScanRoot(_ path: String) {
        guard canEdit else { return }
        settings.scanRoots.removeAll { $0 == path }
        save()
    }

    func setMatchSelected(_ match: ScanMatch, isSelected: Bool) {
        guard canEdit else { return }
        guard let index = matches.firstIndex(where: { $0.id == match.id }) else { return }
        matches[index].isSelected = isSelected
    }

    func previewMatches(for rule: RegexRule) async -> [RulePreviewResult] {
        guard rule.isEnabled, RuleMatcher.validationError(for: rule) == nil else { return [] }

        if rule.kind == .specific {
            let path = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return [] }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                return [
                    RulePreviewResult(
                        path: path,
                        isDirectory: false,
                        sizeBytes: nil,
                        status: .missing
                    )
                ]
            }

            let excluded = await Task.detached(priority: .userInitiated) { [timeMachine] in
                (try? timeMachine.isExcluded(path: path)) ?? false
            }.value

            return [
                RulePreviewResult(
                    path: path,
                    isDirectory: isDirectory.boolValue,
                    sizeBytes: nil,
                    status: excluded ? .excluded : .included
                )
            ]
        }

        let candidates = await Task.detached(priority: .userInitiated) { [settings, scanner] in
            scanner.scan(settings: settings, rule: rule, limit: settings.previewResultLimit)
        }.value
        return candidates.map { candidate in
            RulePreviewResult(
                path: candidate.path,
                isDirectory: candidate.isDirectory,
                sizeBytes: candidate.sizeBytes,
                status: .matched
            )
        }
    }

    func scanNow() async {
        updateOperation(detail: "Scanning rules", progress: operationTitle == "Scan + Backup" ? 0.12 : nil)

        let specificRules = rules.filter { $0.kind == .specific && $0.isEnabled && !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        updateOperation(detail: "Searching scan roots", progress: operationTitle == "Scan + Backup" ? 0.20 : nil)
        let scanned = await Task.detached(priority: .userInitiated) { [settings, rules, scanner] in
            scanner.scan(settings: settings, rules: rules)
        }.value
        guard !Task.isCancelled else { return }

        updateOperation(detail: "Collecting specific paths", progress: operationTitle == "Scan + Backup" ? 0.34 : nil)
        // Collect all paths for specific rules that exist on disk and aren't already in scanned results
        let scannedPaths = Set(scanned.map(\.0.path))
        let specificCandidates: [(path: String, rule: RegexRule, isDirectory: Bool)] = specificRules.compactMap { rule in
            let path = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !scannedPaths.contains(path), FileManager.default.fileExists(atPath: path) else { return nil }
            let isDir = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return (path, rule, isDir)
        }
        guard !Task.isCancelled else { return }

        updateOperation(detail: "Checking Time Machine status", progress: operationTitle == "Scan + Backup" ? 0.48 : nil)
        // Check exclusion status for all paths concurrently (one tmutil process per path, all in parallel)
        let allPaths = scanned.map(\.0.path) + specificCandidates.map(\.path)
        let exclusionStatuses = await Task.detached(priority: .userInitiated) { [timeMachine] in
            await withTaskGroup(of: (String, Bool).self) { group in
                for path in allPaths {
                    group.addTask {
                        let excluded = (try? timeMachine.isExcluded(path: path)) ?? false
                        return (path, excluded)
                    }
                }
                var statuses: [String: Bool] = [:]
                for await (path, excluded) in group {
                    statuses[path] = excluded
                }
                return statuses
            }
        }.value
        guard !Task.isCancelled else { return }

        var nextMatches: [ScanMatch] = []

        for (candidate, rule) in scanned {
            let excluded = exclusionStatuses[candidate.path] ?? false
            nextMatches.append(
                ScanMatch(
                    path: candidate.path,
                    source: .rule(rule.name),
                    isDirectory: candidate.isDirectory,
                    isExcluded: excluded,
                    sizeBytes: candidate.sizeBytes,
                    isSelected: !excluded
                )
            )
        }

        for item in specificCandidates {
            let excluded = exclusionStatuses[item.path] ?? false
            nextMatches.append(
                ScanMatch(
                    path: item.path,
                    source: .rule(item.rule.name),
                    isDirectory: item.isDirectory,
                    isExcluded: excluded,
                    sizeBytes: nil,
                    isSelected: !excluded
                )
            )
        }

        matches = nextMatches.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        lastScanDate = Date()
        statusMessage = "Found \(matches.count) candidate exclusions"
        if operationTitle == "Scan + Backup" {
            updateOperation(detail: "Found \(matches.count) candidate exclusions", progress: 0.58)
        }
    }

    func applySelectedMatches() async {
        let targets = matches.filter { $0.isSelected && !$0.isExcluded }
        guard !targets.isEmpty else {
            statusMessage = "Nothing new to exclude"
            if operationTitle == "Scan + Backup" {
                updateOperation(detail: "No new exclusions to apply", progress: 0.72)
            }
            return
        }

        var applied = 0
        var failures: [String] = []

        for (offset, target) in targets.enumerated() {
            guard !Task.isCancelled else {
                statusMessage = "Cancelled after applying \(applied) exclusions"
                save()
                return
            }

            if operationTitle == "Scan + Backup" {
                let fraction = Double(offset) / Double(max(targets.count, 1))
                updateOperation(
                    detail: "Applying exclusion \(offset + 1) of \(targets.count)",
                    progress: 0.60 + min(fraction, 1) * 0.28
                )
            }

            let result = await Task.detached(priority: .userInitiated) { [timeMachine] in
                Result { try timeMachine.addExclusion(path: target.path) }
            }.value

            switch result {
            case .success(let commandResult) where commandResult.isSuccess:
                applied += 1
                appliedExclusions.removeAll { $0.path == target.path }
                appliedExclusions.append(
                    AppliedExclusion(path: target.path, sourceDescription: target.source.label)
                )
            default:
                failures.append(target.path)
            }
        }

        save()
        statusMessage = failures.isEmpty
            ? "Applied \(applied) exclusions"
            : "Applied \(applied), failed \(failures.count)."
        if operationTitle == "Scan + Backup" {
            updateOperation(detail: "Applied \(applied) exclusions", progress: 0.88)
        } else {
            await scanNow()
        }
    }

    func removeApplied(_ exclusion: AppliedExclusion) async {
        guard canEdit else { return }
        let result = await Task.detached(priority: .userInitiated) { [timeMachine] in
            Result { try timeMachine.removeExclusion(path: exclusion.path) }
        }.value
        switch result {
        case .success(let commandResult) where commandResult.isSuccess:
            appliedExclusions.removeAll { $0.id == exclusion.id }
            if let index = matches.firstIndex(where: { $0.path == exclusion.path }) {
                matches[index].isExcluded = false
                matches[index].isSelected = true
            }
            statusMessage = "Removed exclusion"
            save()
        case .success:
            statusMessage = "Could not remove exclusion"
        case .failure(let error):
            statusMessage = "Could not remove exclusion: \(error.localizedDescription)"
        }
    }

    func removeApplied(_ exclusions: [AppliedExclusion]) async {
        guard canEdit else { return }
        let targets = exclusions.filter { target in
            appliedExclusions.contains { $0.id == target.id }
        }
        guard !targets.isEmpty else {
            statusMessage = "No exclusions selected"
            return
        }

        var removedIDs = Set<UUID>()
        var failed = 0

        for exclusion in targets {
            let result = await Task.detached(priority: .userInitiated) { [timeMachine] in
                Result { try timeMachine.removeExclusion(path: exclusion.path) }
            }.value

            switch result {
            case .success(let commandResult) where commandResult.isSuccess:
                removedIDs.insert(exclusion.id)
                if let index = matches.firstIndex(where: { $0.path == exclusion.path }) {
                    matches[index].isExcluded = false
                    matches[index].isSelected = true
                }
            default:
                failed += 1
            }
        }

        if !removedIDs.isEmpty {
            appliedExclusions.removeAll { removedIDs.contains($0.id) }
            save()
        }

        statusMessage = failed == 0
            ? "Removed \(removedIDs.count) exclusions"
            : "Removed \(removedIDs.count), failed \(failed)"
    }

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
            statusMessage = result.isSuccess
                ? "Backup started after applying exclusions"
                : "Exclusions applied, but backup did not start"
            if result.isSuccess {
                backupStatus = TimeMachineBackupStatus(isRunning: true, rawOutput: "")
                syncBackupSleepPrevention()
            }
            updateOperation(
                detail: result.isSuccess ? "Backup started" : "Backup did not start",
                progress: 1.0,
                updateStatus: false
            )
        } catch {
            statusMessage = "Exclusions applied, but backup did not start: \(error.localizedDescription)"
            updateOperation(detail: "Backup did not start", progress: 1.0, updateStatus: false)
        }
    }

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

enum AppSidebarSelection: Hashable {
    case section(SidebarSection)
    case destination(String)
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case exclusionRules = "Rules"
    case appManagedExclusions = "App-Managed"
    case commands = "Time Machine"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .exclusionRules: return "text.magnifyingglass"
        case .appManagedExclusions: return "checklist.checked"
        case .commands: return "terminal"
        case .settings: return "gearshape"
        }
    }
}
