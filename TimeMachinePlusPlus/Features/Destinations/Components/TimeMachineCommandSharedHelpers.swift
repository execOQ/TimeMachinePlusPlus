import AppKit
import SwiftUI

private struct DiskUsageMeasurement: Sendable {
    var path: String
    var sizeBytes: Int64?
    var result: CommandResult
    var warning: String?
}

private struct SizeCommandResult: Sendable {
    var tool: String
    var commandPath: String
    var sizeBytes: Int64?
    var result: CommandResult
}

extension TimeMachineCommandSurface {
    var parsedExclusionPaths: [String] {
        parsedLines(exclusionPaths)
    }

    var quotaGBBinding: Binding<String> {
        Binding(get: { quotaGB }, set: { quotaGB = $0 })
    }

    var destinationURLBinding: Binding<String> {
        Binding(get: { destinationURL }, set: { destinationURL = $0 })
    }

    var exclusionPathsBinding: Binding<String> {
        Binding(get: { exclusionPaths }, set: { exclusionPaths = $0 })
    }

    var comparePathsBinding: Binding<String> {
        Binding(get: { comparePaths }, set: { comparePaths = $0 })
    }

    var backupDeletePathsBinding: Binding<String> {
        Binding(get: { backupDeletePaths }, set: { backupDeletePaths = $0 })
    }

    var inheritBackupPathBinding: Binding<String> {
        Binding(get: { inheritBackupPath }, set: { inheritBackupPath = $0 })
    }

    var associateMountPointBinding: Binding<String> {
        Binding(get: { associateMountPoint }, set: { associateMountPoint = $0 })
    }

    var associateSnapshotVolumeBinding: Binding<String> {
        Binding(get: { associateSnapshotVolume }, set: { associateSnapshotVolume = $0 })
    }

    var associateAllSnapshotsBinding: Binding<Bool> {
        Binding(get: { associateAllSnapshots }, set: { associateAllSnapshots = $0 })
    }

    var diagnosticPathsBinding: Binding<String> {
        Binding(get: { diagnosticPaths }, set: { diagnosticPaths = $0 })
    }

    var snapshotPurgeAmountBinding: Binding<String> {
        Binding(get: { snapshotPurgeAmount }, set: { snapshotPurgeAmount = $0 })
    }

    var snapshotUrgencyBinding: Binding<String> {
        Binding(get: { snapshotUrgency }, set: { snapshotUrgency = $0 })
    }

    var backupImageAttachWarningPresented: Binding<Bool> {
        Binding(
            get: { pendingBackupImageAttachRequest != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBackupImageAttachRequest = nil
                }
            }
        )
    }

    var canBrowseSelectedSnapshots: Bool {
        !selectedSnapshots.isEmpty && selectedSnapshots.allSatisfy { !$0.localizedCaseInsensitiveContains(".sparsebundle/") }
    }

    @ViewBuilder
    func commandFeedback(for context: TimeMachineCommandContext) -> some View {
        if let activity = commandActivity, activity.context == context {
            InlineCommandProgress(
                title: activity.title,
                detail: activity.detail,
                onCancel: activity.canCancel ? { cancelLongRunningTask(context: context, path: activity.representedPath) } : nil
            )
        } else if let result = commandResults[context] {
            TimeMachineCommandResultCard(result: result)
        }
    }

    func cancelLongRunningTask(context: TimeMachineCommandContext, path: String? = nil) {
        sizeTask?.cancel()
        if let path {
            ProcessRegistry.shared.terminateMatching { process in
                process.executableURL?.lastPathComponent == "hdiutil"
                    && (process.arguments ?? []).contains(path)
            }
            Task.detached(priority: .utility) {
                AppStateStore.detachBackupImageIfAttached(at: path)
            }
        } else {
            ProcessRegistry.shared.terminateAll()
        }
        commandActivity = nil
        commandResults[context] = TimeMachineCommandPresentation(
            title: "Cancelled",
            summary: "The running operation was cancelled.",
            detail: "",
            tone: .warning,
            exitCode: nil
        )
        store.statusMessage = "Operation cancelled"
        sizeTask = nil
    }

    func startMeasuringSizes(backups: [String], cacheKeys: [String]? = nil, title: String = "Measuring Sizes") {
        guard !backups.isEmpty else { return }
        let resolvedCacheKeys = cacheKeys?.count == backups.count ? cacheKeys! : backups
        let context = destinationContextID.map(TimeMachineCommandContext.destinationSnapshots) ?? .backups
        sizeTask?.cancel()
        store.isMeasuringSizes = true
        store.statusMessage = title
        commandActivity = TimeMachineCommandActivity(title: title, context: context)
        commandResults[context] = nil

        sizeTask = Task.detached(priority: .utility) {
            var measuredCount = 0
            var warningMessages: [String] = []
            var failureMessages: [String] = []

            for (offset, path) in backups.enumerated() {
                let cacheKey = resolvedCacheKeys[offset]
                guard !Task.isCancelled else { break }
                let measurement = Self.diskUsageMeasurement(path: path)

                if let sizeBytes = measurement.sizeBytes {
                    measuredCount += 1
                    await MainActor.run {
                        store.snapshotSizeCache[cacheKey] = sizeBytes
                        store.statusMessage = "Measured \(offset + 1) of \(backups.count) backup sizes"
                    }
                    if let warning = measurement.warning {
                        warningMessages.append(warning)
                    }
                } else {
                    failureMessages.append(Self.diskUsageFailureMessage(for: measurement))
                }
            }

            let finalMeasuredCount = measuredCount
            let finalWarningMessages = warningMessages
            let finalFailureMessages = failureMessages
            let wasCancelled = Task.isCancelled

            await MainActor.run {
                store.isMeasuringSizes = false
                commandActivity = nil
                let detailMessages = finalWarningMessages + finalFailureMessages

                if wasCancelled {
                    store.statusMessage = "Cancelled size measurement"
                    commandResults[context] = TimeMachineCommandPresentation(
                        title: title,
                        summary: "Size measurement was cancelled.",
                        detail: detailMessages.joined(separator: "\n\n"),
                        tone: finalMeasuredCount > 0 ? .warning : .failure,
                        exitCode: nil
                    )
                } else if finalFailureMessages.isEmpty, finalWarningMessages.isEmpty {
                    store.statusMessage = "Measured \(finalMeasuredCount) backup sizes"
                    commandResults[context] = TimeMachineCommandPresentation(
                        title: title,
                        summary: "Measured \(finalMeasuredCount) backup size\(finalMeasuredCount == 1 ? "" : "s").",
                        detail: "",
                        tone: .success,
                        exitCode: 0
                    )
                } else if finalFailureMessages.isEmpty {
                    store.statusMessage = "Measured \(finalMeasuredCount) backup sizes with warnings"
                    commandResults[context] = TimeMachineCommandPresentation(
                        title: title,
                        summary: "Measured \(finalMeasuredCount) backup size\(finalMeasuredCount == 1 ? "" : "s") with warnings.",
                        detail: finalWarningMessages.joined(separator: "\n\n"),
                        tone: .warning,
                        exitCode: nil
                    )
                } else {
                    store.statusMessage = "Measured \(finalMeasuredCount), failed \(finalFailureMessages.count)"
                    commandResults[context] = TimeMachineCommandPresentation(
                        title: title,
                        summary: "Measured \(finalMeasuredCount), failed \(finalFailureMessages.count).",
                        detail: detailMessages.joined(separator: "\n\n"),
                        tone: finalMeasuredCount > 0 ? .warning : .failure,
                        exitCode: nil
                    )
                }

                store.save()
                sizeTask = nil
            }
        }
    }

    func attachBackupImageAndRefresh(_ destination: TimeMachineDestination, measureAfterAttach: Bool = false) {
        guard let sparsebundlePath = destination.sparsebundlePath else { return }
        let context = TimeMachineCommandContext.destinationSnapshots(destination.id)
        sizeTask?.cancel()
        commandResults[context] = nil
        commandActivity = TimeMachineCommandActivity(
            title: "Attaching Backup Image",
            context: context,
            detail: "Starting disk image attach...",
            canCancel: true,
            representedPath: sparsebundlePath
        )
        store.statusMessage = "Attaching \(destination.name) backup image..."

        sizeTask = Task { @MainActor in
            let statusTask = Task { @MainActor in
                while !Task.isCancelled {
                    let status = await Task.detached(priority: .utility) {
                        AppStateStore.backupImageAttachStatus(for: sparsebundlePath)
                    }.value
                    guard !Task.isCancelled else { return }
                    if commandActivity?.context == context {
                        var nextActivity = commandActivity
                        nextActivity?.detail = status
                        commandActivity = nextActivity
                        store.statusMessage = status
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }

            let result = await AppStateStore.attachBackupImage(at: sparsebundlePath)
            statusTask.cancel()
            await store.refreshTimeMachineState()

            guard !Task.isCancelled else {
                commandActivity = nil
                commandResults[context] = TimeMachineCommandPresentation(
                    title: "Attach Backup Image",
                    summary: "Backup image attach was cancelled.",
                    detail: Self.attachDetail(result),
                    tone: .warning,
                    exitCode: result.exitCode
                )
                store.statusMessage = "Backup image attach cancelled"
                sizeTask = nil
                return
            }

            guard result.isSuccess else {
                commandActivity = nil
                commandResults[context] = TimeMachineCommandPresentation(
                    title: "Attach Backup Image",
                    summary: Self.firstAttachError(result) ?? "hdiutil attach failed with exit \(result.exitCode).",
                    detail: Self.attachDetail(result),
                    tone: .failure,
                    exitCode: result.exitCode
                )
                store.statusMessage = "Could not attach backup image"
                sizeTask = nil
                return
            }

            let refreshedDestination = store.timeMachineDestinations.first { $0.id == destination.id }
            let refreshedBackups = refreshedDestination
                .flatMap { store.backupHistoriesByDestinationID[$0.id]?.backups }
                ?? store.backupHistoriesByDestinationID[destination.id]?.backups
                ?? []
            let attachRefreshDetail = Self.attachRefreshDetail(
                attachResult: result,
                originalDestination: destination,
                refreshedDestination: refreshedDestination,
                refreshedBackups: refreshedBackups
            )
            let measurable = refreshedBackups
                .filter { FileManager.default.fileExists(atPath: $0) }
                .filter { store.snapshotSizeCache[$0] == nil }

            if measureAfterAttach, !measurable.isEmpty {
                commandActivity = nil
                sizeTask = nil
                startMeasuringSizes(backups: measurable, title: "Measuring Snapshot Sizes")
            } else {
                commandActivity = nil
                let hasMountedVolume = refreshedDestination?.mountPoint != nil
                let hasUsableBackups = !measurable.isEmpty
                let didOnlyAttachImage = hasMountedVolume && !measureAfterAttach
                let summary: String
                let tone: TimeMachineCommandResultTone
                let detail: String

                if hasUsableBackups {
                    summary = "Backup image attached. \(measurable.count) snapshot size\(measurable.count == 1 ? "" : "s") ready to measure."
                    tone = .success
                    detail = attachRefreshDetail
                    store.statusMessage = "Backup image attached"
                } else if didOnlyAttachImage {
                    summary = "Backup image mounted, but no readable snapshot folders were exposed."
                    tone = .warning
                    detail = Self.noReadableSnapshotsDetail(attachRefreshDetail)
                    store.statusMessage = "Backup image mounted without readable snapshots"
                } else {
                    summary = "No snapshot sizes were measured because the backup image did not expose readable snapshot folders."
                    tone = .warning
                    detail = Self.noReadableSnapshotsDetail(attachRefreshDetail)
                    store.statusMessage = "Backup image attach incomplete"
                }

                commandResults[context] = TimeMachineCommandPresentation(
                    title: "Attach Backup Image",
                    summary: summary,
                    detail: detail,
                    tone: tone,
                    exitCode: result.exitCode
                )
                sizeTask = nil
            }
        }
    }

    func requestBackupImageAttach(_ destination: TimeMachineDestination, measureAfterAttach: Bool = false) {
        pendingBackupImageAttachRequest = BackupImageAttachRequest(
            destination: destination,
            measureAfterAttach: measureAfterAttach
        )
    }

    func runPendingBackupImageAttachRequest() {
        guard let request = pendingBackupImageAttachRequest else { return }
        pendingBackupImageAttachRequest = nil
        attachBackupImageAndRefresh(
            request.destination,
            measureAfterAttach: request.measureAfterAttach
        )
    }

    nonisolated fileprivate static func diskUsageMeasurement(path: String) -> DiskUsageMeasurement {
        let usesTimeMachineUniqueSize = isTimeMachineSnapshotPath(path)
        guard usesTimeMachineUniqueSize else {
            let primary = runSizeCommand(
                tool: "du",
                executablePath: "/usr/bin/du",
                arguments: ["-sk", path],
                commandPath: path,
                displayPath: path
            )
            if let sizeBytes = primary.sizeBytes {
                return DiskUsageMeasurement(
                    path: path,
                    sizeBytes: sizeBytes,
                    result: primary.result,
                    warning: primary.result.isSuccess ? nil : Self.diskUsageWarningMessage(path: path, result: primary.result)
                )
            }
            return DiskUsageMeasurement(path: path, sizeBytes: nil, result: primary.result, warning: nil)
        }

        let candidatePaths = sizeCommandCandidates(for: path)
        var lastUniqueSizeResult: CommandResult?
        for candidatePath in candidatePaths {
            let primary = runSizeCommand(
                tool: "tmutil uniquesize",
                executablePath: "/usr/bin/tmutil",
                arguments: ["uniquesize", candidatePath],
                commandPath: candidatePath,
                displayPath: path
            )
            lastUniqueSizeResult = primary.result
            if let sizeBytes = primary.sizeBytes {
                return DiskUsageMeasurement(
                    path: path,
                    sizeBytes: sizeBytes,
                    result: primary.result,
                    warning: primary.result.isSuccess ? nil : Self.diskUsageWarningMessage(path: path, result: primary.result)
                )
            }
        }

        var lastFallbackResult: CommandResult?
        for fallbackPath in candidatePaths {
            let fallback = runSizeCommand(
                tool: "du fallback",
                executablePath: "/usr/bin/du",
                arguments: ["-sk", fallbackPath],
                commandPath: fallbackPath,
                displayPath: path
            )
            lastFallbackResult = fallback.result
            if let sizeBytes = fallback.sizeBytes {
                return DiskUsageMeasurement(
                    path: path,
                    sizeBytes: sizeBytes,
                    result: fallback.result,
                    warning: fallback.result.isSuccess ? nil : Self.diskUsageWarningMessage(path: path, result: fallback.result)
                )
            }
        }

        return DiskUsageMeasurement(path: path, sizeBytes: nil, result: lastFallbackResult ?? lastUniqueSizeResult ?? CommandResult(exitCode: -1, output: "", errorOutput: "No size command was run."), warning: nil)
    }

    nonisolated fileprivate static func runSizeCommand(
        tool: String,
        executablePath: String,
        arguments: [String],
        commandPath: String,
        displayPath: String
    ) -> SizeCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        debugMeasureLog("starting tool=\(tool) command=\(executablePath) \(arguments.joined(separator: " ")) displayPath=\(displayPath)")
        let outPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errorPipe
        ProcessRegistry.shared.register(process)
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            ProcessRegistry.shared.deregister(process)
            debugMeasureLog("failed to launch tool=\(tool) displayPath=\(displayPath) commandPath=\(commandPath) error=\(error.localizedDescription)")
            return SizeCommandResult(
                tool: tool,
                commandPath: commandPath,
                sizeBytes: nil,
                result: CommandResult(exitCode: -1, output: "", errorOutput: error.localizedDescription)
            )
        }
        ProcessRegistry.shared.deregister(process)
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let sizeBytes = tool == "tmutil uniquesize"
            ? uniqueSizeBytes(from: output)
            : diskUsageBytes(from: output)
        debugMeasureLog(
            """
            finished tool=\(tool)
            displayPath=\(displayPath)
            commandPath=\(commandPath)
            exit=\(process.terminationStatus)
            parsedBytes=\(sizeBytes.map(String.init) ?? "nil")
            stdout=\(output.trimmingCharacters(in: .whitespacesAndNewlines))
            stderr=\(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        )
        return SizeCommandResult(
            tool: tool,
            commandPath: commandPath,
            sizeBytes: sizeBytes,
            result: CommandResult(exitCode: process.terminationStatus, output: output, errorOutput: errorOutput)
        )
    }

    nonisolated fileprivate static func diskUsageWarningMessage(path: String, result: CommandResult) -> String {
        let detail = commandOutputSnippet(result) ?? "No warning output."
        return "\(path): measured a size, but the command exited \(result.exitCode). \(detail)"
    }

    nonisolated fileprivate static func diskUsageFailureMessage(for measurement: DiskUsageMeasurement) -> String {
        let detail = commandOutputSnippet(measurement.result) ?? "No size returned."
        return "\(measurement.path): exit \(measurement.result.exitCode). \(detail)"
    }

    nonisolated fileprivate static func commandOutputSnippet(_ result: CommandResult) -> String? {
        let output = [result.errorOutput, result.output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let output else { return nil }

        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let visibleLines = lines.prefix(8)
        var snippet = visibleLines.joined(separator: "\n")
        if lines.count > visibleLines.count {
            snippet += "\n... \(lines.count - visibleLines.count) more line\(lines.count - visibleLines.count == 1 ? "" : "s")"
        }
        if snippet.count > 4_000 {
            let endIndex = snippet.index(snippet.startIndex, offsetBy: 4_000)
            snippet = String(snippet[..<endIndex]) + "\n... output truncated"
        }
        return snippet
    }

    nonisolated fileprivate static func isTimeMachineSnapshotPath(_ path: String) -> Bool {
        let lowercasedPath = path.lowercased()
        return lowercasedPath.hasPrefix("/volumes/.timemachine/")
            && lowercasedPath.contains(".backup/")
            && lowercasedPath.hasSuffix(".backup")
    }

    nonisolated fileprivate static func sizeCommandCandidates(for path: String) -> [String] {
        let normalizedPath = normalizedBackupSnapshotPath(for: path)
        return [path, normalizedPath].reduce(into: [String]()) { result, candidate in
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
    }

    nonisolated fileprivate static func normalizedBackupSnapshotPath(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        let parent = url.deletingLastPathComponent()
        guard last.localizedCaseInsensitiveCompare(parent.lastPathComponent) == .orderedSame,
              last.lowercased().hasSuffix(".backup") else {
            return path
        }
        return parent.path
    }

    nonisolated fileprivate static func diskUsageBytes(from output: String) -> Int64? {
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).first ?? ""
        return Int64(token).map { $0 * 1024 }
    }

    nonisolated fileprivate static func uniqueSizeBytes(from output: String) -> Int64? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bytes = firstIntegerBeforeBytes(in: text) {
            return bytes
        }
        if let firstToken = text.components(separatedBy: .whitespacesAndNewlines).first {
            return sizeTokenBytes(firstToken)
        }
        return nil
    }

    nonisolated fileprivate static func firstIntegerBeforeBytes(in text: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(\d[\d,\.]*)\s*bytes"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let digits = text[valueRange].filter(\.isNumber)
        return Int64(digits)
    }

    nonisolated fileprivate static func sizeTokenBytes(_ token: String) -> Int64? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let unit = trimmed.last.map(String.init) ?? ""
        let numberText: String
        let multiplier: Double

        switch unit.uppercased() {
        case "K":
            numberText = String(trimmed.dropLast())
            multiplier = 1024
        case "M":
            numberText = String(trimmed.dropLast())
            multiplier = 1024 * 1024
        case "G":
            numberText = String(trimmed.dropLast())
            multiplier = 1024 * 1024 * 1024
        case "T":
            numberText = String(trimmed.dropLast())
            multiplier = 1024 * 1024 * 1024 * 1024
        default:
            numberText = trimmed
            multiplier = 1
        }

        let normalizedNumber = numberText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalizedNumber) else { return nil }
        return Int64(value * multiplier)
    }

    nonisolated fileprivate static func debugMeasureLog(_ message: String) {
        NSLog("TimeMachine++ measure debug: %@", message)
    }

    nonisolated static func attachDetail(_ result: CommandResult) -> String {
        [result.output, result.errorOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    nonisolated static func attachRefreshDetail(
        attachResult: CommandResult,
        originalDestination: TimeMachineDestination,
        refreshedDestination: TimeMachineDestination?,
        refreshedBackups: [String]
    ) -> String {
        var lines: [String] = []
        let attachText = attachDetail(attachResult)
        if !attachText.isEmpty {
            lines.append("Attach output:")
            lines.append(attachText)
        }

        lines.append("Original destination:")
        lines.append("id=\(originalDestination.id)")
        lines.append("mountPoint=\(originalDestination.mountPoint ?? "<nil>")")
        lines.append("shareMountPoint=\(originalDestination.shareMountPoint ?? "<nil>")")
        lines.append("sparsebundlePath=\(originalDestination.sparsebundlePath ?? "<nil>")")

        lines.append("Refreshed destination:")
        if let refreshedDestination {
            lines.append("id=\(refreshedDestination.id)")
            lines.append("mountPoint=\(refreshedDestination.mountPoint ?? "<nil>")")
            lines.append("shareMountPoint=\(refreshedDestination.shareMountPoint ?? "<nil>")")
            lines.append("sparsebundlePath=\(refreshedDestination.sparsebundlePath ?? "<nil>")")
        } else {
            lines.append("<not found>")
        }

        lines.append("Refreshed backup paths:")
        if refreshedBackups.isEmpty {
            lines.append("<none>")
        } else {
            for path in refreshedBackups {
                lines.append("\(FileManager.default.fileExists(atPath: path) ? "exists" : "missing") \(path)")
            }
        }

        let detail = lines.joined(separator: "\n")
        NSLog("TimeMachine++ attach refresh debug: %@", detail)
        return detail
    }

    nonisolated static func noReadableSnapshotsDetail(_ attachRefreshDetail: String) -> String {
        """
        No measurement was attempted because none of the refreshed snapshot paths currently exists on disk. This can match macOS disk image errors such as code 150: the APFS backup image is mounted, but Time Machine snapshot folders are not exposed.

        \(attachRefreshDetail)
        """
    }

    nonisolated static func firstAttachError(_ result: CommandResult) -> String? {
        [result.errorOutput, result.output]
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    func parsedLines(_ value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var destructiveActionPresented: Binding<Bool> {
        Binding(
            get: { pendingDestructiveAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDestructiveAction = nil
                }
            }
        )
    }

    func sectionHeader(_ title: String, subtitle: String) -> some View {
        AppSectionHeader(title: title, subtitle: subtitle)
    }

    func sectionLabel(_ text: String) -> some View {
        AppSectionLabel(title: text)
    }

    func primaryButtonLabel(_ title: String, systemImage: String) -> some View {
        AppActionLabel(title: title, systemImage: systemImage)
    }

    func diagnosticsBox(arguments: [String], title: String) -> some View {
        AppSectionView(title: "Diagnostics") {
            Button {
                run(arguments: arguments, context: .diagnostics, title: title, status: "Running \(title)...")
            } label: {
                primaryButtonLabel(title, systemImage: "terminal")
            }
        }
    }

    func diagnosticsButton(_ title: String, systemImage: String, arguments: [String]) -> some View {
        Button {
            run(arguments: arguments, context: .diagnostics, title: title, status: "Running \(title)...")
        } label: {
            primaryButtonLabel(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ToolbarContentBuilder
    var toolbarOperationItems: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button {
                    pickAndSetDestination(shouldAppend: true)
                } label: {
                    primaryButtonLabel("Add Destination", systemImage: "plus")
                }

                Button {
                    pickAndSetDestination(shouldAppend: false)
                } label: {
                    primaryButtonLabel("Replace Destinations", systemImage: "externaldrive")
                }
            } label: {
                primaryButtonLabel("Add", systemImage: "plus")
            }
            .help("Add or replace Time Machine destinations")
            .disabled(store.isWorking)
        }

        ToolbarItem {
            if store.isWorking {
                if store.canCancelCurrentOperation {
                    Button(role: .cancel) {
                        store.cancelOperation()
                    } label: {
                        primaryButtonLabel("Cancel", systemImage: "xmark.circle")
                    }
                    .help("Cancel the current operation")
                }
            } else {
                if store.backupStatus.isRunning {
                    Button(role: .destructive) {
                        Task { await stopRunningBackup() }
                    } label: {
                        primaryButtonLabel("Stop", systemImage: "stop.fill")
                    }
                    .help("Stop the running Time Machine backup")
                } else {
                    Button {
                        store.startConfiguredStartAction()
                    } label: {
                        primaryButtonLabel("Start", systemImage: "play.fill")
                    }
                    .help(store.startActionHelp)
                }
            }
        }
    }

    func pickAndSetDestination(shouldAppend: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = shouldAppend ? "Add" : "Replace"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let client = LiveTimeMachineClient()
            var arguments = ["setdestination"]
            if shouldAppend {
                arguments.append("-a")
            }
            arguments.append(url.path)
            let result = try? client.run(arguments: arguments, asAdministrator: true)
            await MainActor.run {
                store.statusMessage = result?.isSuccess == true ? "Destination updated" : "Could not update destination"
            }
            await store.refreshTimeMachineState()
        }
    }

    func stopRunningBackup() async {
        let client = LiveTimeMachineClient()
        _ = try? client.stopBackup()
        await store.refreshTimeMachineState()
        store.statusMessage = "Stop backup requested"
    }

}
