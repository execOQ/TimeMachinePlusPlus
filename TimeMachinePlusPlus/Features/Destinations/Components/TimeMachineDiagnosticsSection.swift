import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Diagnostics", subtitle: "Read-only tmutil information and backup history helpers.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                diagnosticsButton("Status", systemImage: "waveform.path.ecg", arguments: ["status"])
                diagnosticsButton("Latest Backup", systemImage: "clock", arguments: ["latestbackup"])
                diagnosticsButton("List Backups", systemImage: "list.bullet.rectangle", arguments: ["listbackups"])
                diagnosticsButton("Resolved Machine Dir", systemImage: "folder", arguments: ["machinedirectory"])
                diagnosticsButton("tmutil Version", systemImage: "number", arguments: ["version"])
                diagnosticsButton("Help", systemImage: "questionmark.circle", arguments: ["help"])
            }
            commandFeedback(for: .diagnostics)

            AppSectionView(title: "Path Diagnostics") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Paths", text: diagnosticPathsBinding)

                    HStack(spacing: 10) {
                        Button {
                            run(arguments: ["uniquesize"] + parsedLines(diagnosticPaths), context: .pathDiagnostics, title: "Unique Size", status: "Calculating unique size...")
                        } label: {
                            primaryButtonLabel("Unique Size", systemImage: "sum")
                        }
                        .disabled(parsedLines(diagnosticPaths).isEmpty)

                        Button {
                            run(arguments: ["verifychecksums"] + parsedLines(diagnosticPaths), context: .pathDiagnostics, title: "Verify Checksums", status: "Verifying checksums...")
                        } label: {
                            primaryButtonLabel("Verify Checksums", systemImage: "checkmark.seal")
                        }
                        .disabled(parsedLines(diagnosticPaths).isEmpty)
                    }

                    commandFeedback(for: .pathDiagnostics)
                }
            }
        }
    }


}
