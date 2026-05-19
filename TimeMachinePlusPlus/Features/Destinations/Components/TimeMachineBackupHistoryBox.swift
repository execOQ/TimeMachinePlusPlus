import AppKit
import SwiftUI

private struct BackupPathRowItem: Identifiable {
    let path: String
    var id: String { path }
}

extension TimeMachineCommandSurface {
    func backupHistoryBox(for destination: TimeMachineDestination) -> some View {
        AppSectionView(title: "Snapshots") {
            VStack(alignment: .leading, spacing: 10) {
                if let mountPoint = destination.mountPoint {
                    Label(mountPoint, systemImage: "externaldrive")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Label("Backup volume is not mounted", systemImage: "externaldrive.badge.xmark")
                        .foregroundStyle(.secondary)
                }

                let history = store.backupHistoriesByDestinationID[destination.id] ?? .empty(destinationID: destination.id)

                if !history.backups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(history.backups.map(BackupPathRowItem.init)) { item in
                            let backup = item.path
                            HStack(spacing: 8) {
                                Toggle("", isOn: snapshotBinding(backup))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                AppPathText(path: backup)
                                Spacer()
                                if let size = store.snapshotSizeCache[backup] {
                                    Text(Formatters.fileSize(size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                } else if store.isMeasuringSizes {
                                    ProgressView().controlSize(.mini)
                                }
                                Button(role: .destructive) {
                                    pendingDestructiveAction = .deleteBackupPaths([backup])
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.borderless)
                                .help("Delete this backup snapshot")
                            }
                        }

                        let measured = history.backups.compactMap { store.snapshotSizeCache[$0] }
                        if !measured.isEmpty {
                            HStack {
                                Text("Total measured (\(measured.count) of \(history.backups.count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.fileSize(measured.reduce(0, +)))
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                            }
                            .padding(.top, 4)
                        }
                    }
                } else if history.noBackupsForCurrentHost {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("This destination has backup storage, but tmutil did not find backups for this Mac identity.", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.orange)

                        if !history.machineDirectories.isEmpty {
                            Text("Machine directories found:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(history.machineDirectories.map(BackupPathRowItem.init)) { item in
                                let directory = item.path
                                AppPathText(path: directory, style: .caption, isSelectable: true)
                            }
                        }

                        Text("If this is backup history from another Mac or renamed disk, Inherit Backup or Associate Disk may be needed before snapshots appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if history.requiresFullDiskAccess {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Backup history exists, but this running app still cannot read it.", systemImage: "lock.fill")
                            .foregroundStyle(.orange)

                        Text("Add this exact app to Full Disk Access, then quit and reopen it:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AppPathText(path: Bundle.main.bundlePath, style: .caption, isSelectable: true)
                            .foregroundStyle(.secondary)

                        if let message = history.message, !message.isEmpty {
                            AppPathText(path: message, style: .caption, isSelectable: true)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button {
                                revealCurrentAppInFinder()
                            } label: {
                                primaryButtonLabel("Reveal App", systemImage: "magnifyingglass")
                            }

                            Button {
                                store.refreshFullDiskAccessStatus()
                            } label: {
                                primaryButtonLabel("Recheck", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                } else if let message = history.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.localizedCaseInsensitiveContains("sparsebundle") ? .orange : .secondary)
                } else {
                    Text("No backup history was returned for this destination.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        pendingDestructiveAction = .deleteBackupPaths(Array(selectedSnapshots))
                    } label: {
                        primaryButtonLabel("Delete Selected", systemImage: "trash")
                    }
                    .disabled(selectedSnapshots.isEmpty)

                    Button(role: .destructive) {
                        pendingDestructiveAction = .thinSnapshots(snapshotPurgeAmount, snapshotUrgency)
                    } label: {
                        primaryButtonLabel("Thin Local", systemImage: "scissors")
                    }

                    Button {
                        if let mountPoint = destination.mountPoint {
                            run(arguments: ["listbackups", "-d", mountPoint], context: .destinationSnapshots(destination.id), title: "List Backups", status: "Listing backups...")
                        } else {
                            run(arguments: ["listbackups"], context: .destinationSnapshots(destination.id), title: "List Backups", status: "Listing backups...")
                        }
                    } label: {
                        primaryButtonLabel("List Backups", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(destination.mountPoint == nil)
                    .help(destination.mountPoint == nil ? "The network share is mounted, but the Time Machine backup image is not mounted as a browsable snapshot volume." : "List backups for this destination")

                    Button {
                        if let mountPoint = destination.mountPoint {
                            run(arguments: ["latestbackup", "-d", mountPoint], context: .destinationSnapshots(destination.id), title: "Latest Backup", status: "Finding latest backup...")
                        } else {
                            run(arguments: ["latestbackup"], context: .destinationSnapshots(destination.id), title: "Latest Backup", status: "Finding latest backup...")
                        }
                    } label: {
                        primaryButtonLabel("Latest", systemImage: "clock")
                    }
                    .disabled(destination.mountPoint == nil)
                    .help(destination.mountPoint == nil ? "The network share is mounted, but the Time Machine backup image is not mounted as a browsable snapshot volume." : "Find latest backup for this destination")

                    Divider().frame(height: 16)

                    if store.isMeasuringSizes {
                        ProgressView().controlSize(.small)
                        Button("Cancel") {
                            sizeTask?.cancel()
                            store.isMeasuringSizes = false
                        }
                        .foregroundStyle(.primary)
                    } else {
                        let uncached = history.backups.filter { store.snapshotSizeCache[$0] == nil }
                        Button {
                            let toMeasure = uncached.isEmpty ? history.backups : uncached
                            startMeasuringSizes(backups: toMeasure)
                        } label: {
                            primaryButtonLabel(uncached.isEmpty ? "Re-measure" : "Measure Sizes", systemImage: "ruler")
                        }
                        .disabled(history.backups.isEmpty)
                        .help(uncached.isEmpty ? "All sizes cached — click to re-measure" : "Measure total disk usage of each snapshot")
                    }
                }

                commandFeedback(for: .destinationSnapshots(destination.id))
            }
        }
    }


}
