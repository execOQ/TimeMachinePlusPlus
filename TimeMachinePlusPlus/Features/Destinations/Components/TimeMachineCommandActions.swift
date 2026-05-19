import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    func refresh() {
        Task {
            await store.refreshTimeMachineState()
            store.statusMessage = "Refreshed Time Machine state"
        }
    }

    func run(
        arguments: [String],
        context: TimeMachineCommandContext? = nil,
        title: String? = nil,
        asAdministrator: Bool = false,
        status: String
    ) {
        let resolvedContext = context ?? currentCommandContext
        let resolvedTitle = title ?? arguments.first.map { "tmutil \($0)" } ?? "Time Machine"
        guard store.beginBlockingOperation(title: status) else { return }
        commandActivity = TimeMachineCommandActivity(title: status, context: resolvedContext)

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try LiveTimeMachineClient().run(arguments: arguments, asAdministrator: asAdministrator) }
            }.value

            var finalStatus = "Time Machine command finished"
            await MainActor.run {
                switch result {
                case .success(let commandResult):
                    let presentation = TimeMachineCommandPresentationFormatter.presentation(
                        title: resolvedTitle,
                        arguments: arguments,
                        result: commandResult
                    )
                    commandResults[resolvedContext] = presentation
                    finalStatus = commandResult.isSuccess ? "\(resolvedTitle) finished" : presentation.summary
                    if asAdministrator, !commandResult.isSuccess {
                        store.refreshFullDiskAccessStatus()
                    }
                case .failure(let error):
                    commandResults[resolvedContext] = TimeMachineCommandPresentationFormatter.failure(
                        title: resolvedTitle,
                        error: error
                    )
                    finalStatus = "tmutil failed"
                }
                commandActivity = nil
            }

            await store.refreshTimeMachineState()
            await MainActor.run {
                store.finishBlockingOperation(status: finalStatus)
            }
        }
    }

    func runDestructiveAction(_ action: DestructiveAction) {
        switch action {
        case .stopBackup:
            run(arguments: ["stopbackup"], context: .backups, title: "Stop Backup", status: "Stopping backup...")
        case .removeDestination(let destination):
            run(arguments: ["removedestination", destination.id], context: .destinationActions(destination.id), title: "Remove Destination", asAdministrator: true, status: "Removing destination...")
        case .deleteSnapshot(let date):
            run(arguments: ["deletelocalsnapshots", date], context: .snapshots, title: "Delete Local Snapshot", asAdministrator: true, status: "Deleting local snapshot...")
        case .thinSnapshots(let purgeAmount, let urgency):
            var arguments = ["thinlocalsnapshots", "/"]
            let amount = purgeAmount.trimmingCharacters(in: .whitespacesAndNewlines)
            let urgencyValue = urgency.trimmingCharacters(in: .whitespacesAndNewlines)
            if !amount.isEmpty {
                arguments.append(amount)
                if !urgencyValue.isEmpty {
                    arguments.append(urgencyValue)
                }
            }
            run(arguments: arguments, context: .snapshots, title: "Thin Local Snapshots", status: "Thinning local snapshots...")
        case .deleteBackupPaths(let paths):
            run(arguments: ["delete"] + paths, context: deleteContext(for: paths), title: "Delete Backup Paths", asAdministrator: true, status: "Deleting backup paths...")
        case .deleteInProgress:
            break
        }
    }

    var currentCommandContext: TimeMachineCommandContext {
        if let id = destinationContextID {
            return .destinationActions(id)
        }
        return .backups
    }

    func deleteContext(for paths: [String]) -> TimeMachineCommandContext {
        if let id = destinationContextID {
            return .destinationSnapshots(id)
        }
        return .deleteBackups
    }

    func pickDestination() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationURL = url.path
    }

    func pickExclusionPaths() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return }
        let additions = panel.urls.map(\.path).joined(separator: "\n")
        exclusionPaths = exclusionPaths.isEmpty ? additions : exclusionPaths + "\n" + additions
    }

    func pickAdoptionPath(assignTo value: Binding<String>, canChooseFiles: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = canChooseFiles
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        value.wrappedValue = url.path
    }

    func revealCurrentAppInFinder() {
        FullDiskAccessSupport.revealCurrentAppInFinder()
        store.statusMessage = "Revealed the app that needs Full Disk Access"
    }
}
