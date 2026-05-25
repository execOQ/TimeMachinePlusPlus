import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    var compareView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Compare", subtitle: "Compare current paths against Time Machine backup data.")

            AppSectionView(title: "Compare") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Optional snapshot path, or two paths on separate lines", text: comparePathsBinding)

                    Button {
                        run(arguments: ["compare"] + parsedLines(comparePaths), context: .compare, title: "Compare", status: "Comparing backup data...")
                    } label: {
                        primaryButtonLabel("Compare", systemImage: "arrow.left.arrow.right")
                    }
                }
            }

            commandFeedback(for: .compare)

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
