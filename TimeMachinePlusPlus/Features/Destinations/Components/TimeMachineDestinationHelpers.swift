import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    func destinationRestoreCompareBox(destination: TimeMachineDestination) -> some View {
        AppSectionView(title: "Compare & Restore") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select one snapshot above, or enter exact snapshot item paths below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        run(arguments: ["compare"] + Array(selectedSnapshots), context: .destinationRestoreCompare(destination.id), title: "Compare Selected", status: "Comparing selected snapshots...")
                    } label: {
                        primaryButtonLabel("Compare Selected", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(selectedSnapshots.isEmpty || !canBrowseSelectedSnapshots)
                    .help(canBrowseSelectedSnapshots ? "Compare selected snapshots" : "These entries came from sparsebundle history and are not mounted snapshot paths yet.")

                    Button {
                        restoreSources = Array(selectedSnapshots).joined(separator: "\n")
                    } label: {
                        primaryButtonLabel("Use Selected for Restore", systemImage: "arrow.down.doc")
                    }
                    .disabled(selectedSnapshots.isEmpty)
                }

                pathEditor("Restore sources", text: restoreSourcesBinding)
                TextField("Restore destination", text: restoreDestinationBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button {
                    run(arguments: ["restore", "-v"] + parsedLines(restoreSources) + [restoreDestination], context: .destinationRestoreCompare(destination.id), title: "Restore", status: "Restoring files...")
                } label: {
                    primaryButtonLabel("Restore", systemImage: "arrow.down.doc")
                }
                .disabled(parsedLines(restoreSources).isEmpty || restoreDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                commandFeedback(for: .destinationRestoreCompare(destination.id))
            }
        }
    }

    func storageBox(mountPoint: String) -> some View {
        AppSectionView(title: "Storage") {
            if let stats = volumeStats[mountPoint] {
                let used = max(0, stats.total - stats.free)
                let usedFraction = stats.total > 0 ? Double(used) / Double(stats.total) : 0
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: usedFraction)
                        .progressViewStyle(.linear)
                        .tint(usedFraction > 0.9 ? .red : usedFraction > 0.75 ? .orange : .accentColor)

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                        GridRow {
                            storageCell("Used", value: Formatters.fileSize(used))
                            storageCell("Available", value: Formatters.fileSize(stats.free))
                            storageCell("Total", value: Formatters.fileSize(stats.total))
                        }
                    }
                    .font(.caption)
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    func storageCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
    }


}
