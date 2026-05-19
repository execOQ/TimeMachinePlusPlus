import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    var restoreCompareView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Restore & Compare", subtitle: "Restore files from backup snapshots or compare current paths against backup data.")

            AppSectionView(title: "Compare") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Optional snapshot path, or two paths on separate lines", text: comparePathsBinding)

                    Button {
                        run(arguments: ["compare"] + parsedLines(comparePaths), context: .restoreCompare, title: "Compare", status: "Comparing backup data...")
                    } label: {
                        primaryButtonLabel("Compare", systemImage: "arrow.left.arrow.right")
                    }
                }
            }

            AppSectionView(title: "Restore") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Source paths from backups", text: restoreSourcesBinding)
                    TextField("Destination path", text: restoreDestinationBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        run(arguments: ["restore", "-v"] + parsedLines(restoreSources) + [restoreDestination], context: .restoreCompare, title: "Restore", status: "Restoring files...")
                    } label: {
                        primaryButtonLabel("Restore", systemImage: "arrow.down.doc")
                    }
                    .disabled(parsedLines(restoreSources).isEmpty || restoreDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            commandFeedback(for: .restoreCompare)

            AppSectionView(title: "Delete Backup Snapshots") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Backup snapshot paths", text: backupDeletePathsBinding)

                    Button(role: .destructive) {
                        pendingDestructiveAction = .deleteBackupPaths(parsedLines(backupDeletePaths))
                    } label: {
                        primaryButtonLabel("Delete Backup Paths", systemImage: "trash")
                    }
                    .disabled(parsedLines(backupDeletePaths).isEmpty)

                    commandFeedback(for: .deleteBackups)
                }
            }
        }
    }


}
