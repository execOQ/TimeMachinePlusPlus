import AppKit
import SwiftUI

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

    var restoreSourcesBinding: Binding<String> {
        Binding(get: { restoreSources }, set: { restoreSources = $0 })
    }

    var restoreDestinationBinding: Binding<String> {
        Binding(get: { restoreDestination }, set: { restoreDestination = $0 })
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

    var canBrowseSelectedSnapshots: Bool {
        !selectedSnapshots.isEmpty && selectedSnapshots.allSatisfy { !$0.localizedCaseInsensitiveContains(".sparsebundle/") }
    }

    @ViewBuilder
    func commandFeedback(for context: TimeMachineCommandContext) -> some View {
        if commandActivity?.context == context {
            InlineCommandProgress(title: commandActivity?.title ?? "Running")
        } else if let result = commandResults[context] {
            TimeMachineCommandResultCard(result: result)
        }
    }

    func startMeasuringSizes(backups: [String]) {
        sizeTask?.cancel()
        store.isMeasuringSizes = true

        sizeTask = Task.detached(priority: .utility) { [store] in
            for path in backups {
                guard !Task.isCancelled else { break }
                if let kb = Self.diskUsageKB(path: path) {
                    await MainActor.run {
                        store.snapshotSizeCache[path] = kb * 1024
                        store.save()
                    }
                }
            }
            await MainActor.run { store.isMeasuringSizes = false }
        }
    }

    nonisolated static func diskUsageKB(path: String) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        ProcessRegistry.shared.register(process)
        try? process.run()
        process.waitUntilExit()
        ProcessRegistry.shared.deregister(process)
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).first ?? ""
        return Int64(token)
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
