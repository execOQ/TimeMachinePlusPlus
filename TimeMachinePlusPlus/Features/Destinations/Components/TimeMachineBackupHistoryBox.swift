import AppKit
import SwiftUI

private struct BackupPathRowItem: Identifiable {
    let path: String
    var id: String { path }
}

extension TimeMachineCommandSurface {
    func backupHistoryBox(for destination: TimeMachineDestination) -> some View {
        let history = store.backupHistoriesByDestinationID[destination.id] ?? .empty(destinationID: destination.id)

        return AppSectionView(title: "Snapshots") {
            VStack(alignment: .leading, spacing: 10) {
                if let mountPoint = destination.mountPoint {
                    Label(mountPoint, systemImage: "externaldrive")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if destination.sparsebundlePath != nil || destination.shareMountPoint != nil {
                    Label("Network share is mounted; attach the backup image to browse or measure individual snapshots.", systemImage: "network")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Backup volume is not mounted", systemImage: "externaldrive.badge.xmark")
                        .foregroundStyle(.secondary)
                }

                if !history.backups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(history.backups.map(BackupPathRowItem.init)) { item in
                            let backup = item.path
                            HStack(spacing: 8) {
                                Toggle("", isOn: snapshotBinding(backup))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                backupPathLabel(backup)
                                Spacer()
                                if let size = store.snapshotSizeCache[backup] {
                                    Text(Formatters.fileSize(size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                } else if !isMeasurableBackupPath(backup) {
                                    Text(isTimeMachineSnapshotPath(backup) ? "Not mounted" : "History only")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
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
                            presentBackupHistoryList(history, destination: destination)
                        }
                    } label: {
                        primaryButtonLabel("List Backups", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(destination.mountPoint == nil && history.backups.isEmpty)
                    .help(destination.mountPoint == nil ? "Show backup history already loaded from this destination." : "List backups for this destination")

                    Button {
                        if let mountPoint = destination.mountPoint {
                            run(arguments: ["latestbackup", "-d", mountPoint], context: .destinationSnapshots(destination.id), title: "Latest Backup", status: "Finding latest backup...")
                        } else {
                            presentLatestBackup(history, destination: destination)
                        }
                    } label: {
                        primaryButtonLabel("Latest", systemImage: "clock")
                    }
                    .disabled(destination.mountPoint == nil && history.backups.isEmpty)
                    .help(destination.mountPoint == nil ? "Show the latest backup already loaded from this destination." : "Find latest backup for this destination")

                    Button {
                        run(arguments: ["compare"] + Array(selectedSnapshots), context: .destinationSnapshots(destination.id), title: "Compare Selected", status: "Comparing selected snapshots...")
                    } label: {
                        primaryButtonLabel(compareSelectedTitle, systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(selectedSnapshots.isEmpty)
                    .help(selectedSnapshots.count == 1 ? "Compare the selected snapshot with the current Mac state." : "Compare the selected snapshots.")

                    Divider().frame(height: 16)

                    if store.isMeasuringSizes {
                        ProgressView().controlSize(.small)
                        Button("Cancel") {
                            sizeTask?.cancel()
                            store.isMeasuringSizes = false
                        }
                        .foregroundStyle(.primary)
                    } else {
                        let measurableBackups = measurableBackupEntries(in: history.backups)
                        let uncached = measurableBackups.filter { store.snapshotSizeCache[$0.cacheKey] == nil }
                        let unmeasuredHistoryOnlyBackups = history.backups.filter {
                            store.snapshotSizeCache[$0] == nil && !isMeasurableBackupPath($0)
                        }
                        let canAttachBackupImage = destination.sparsebundlePath != nil
                        if measurableBackups.isEmpty, canAttachBackupImage {
                            Button {
                                requestBackupImageAttach(destination, measureAfterAttach: true)
                            } label: {
                                primaryButtonLabel("Attach + Measure", systemImage: "externaldrive.connected.to.line.below")
                            }
                            .help("Attach the sparsebundle image, refresh snapshot paths, then measure any mounted snapshots.")
                        } else if uncached.isEmpty, !unmeasuredHistoryOnlyBackups.isEmpty, canAttachBackupImage {
                            Button {
                                requestBackupImageAttach(destination, measureAfterAttach: true)
                            } label: {
                                primaryButtonLabel("Attach + Measure Missing", systemImage: "externaldrive.connected.to.line.below")
                            }
                            .help("Known mounted snapshot sizes are cached. Attach the sparsebundle image to measure history-only snapshots that are still missing sizes.")
                        } else if uncached.isEmpty, !unmeasuredHistoryOnlyBackups.isEmpty {
                            Button {
                            } label: {
                                primaryButtonLabel("Snapshots Not Mounted", systemImage: "externaldrive.badge.xmark")
                            }
                            .disabled(true)
                            .help("Unmeasured snapshots are history-only paths right now. Refresh or attach the backup image before measuring them.")
                        } else {
                            let title = uncached.isEmpty ? "All Measurable Sizes" : "Measure Sizes"
                            Button {
                                startMeasuringSizes(backups: uncached.map(\.measurementPath), cacheKeys: uncached.map(\.cacheKey))
                            } label: {
                                primaryButtonLabel(title, systemImage: "ruler")
                            }
                            .disabled(uncached.isEmpty)
                            .help(measurableBackups.isEmpty ? "Attach the backup image first; these entries are sparsebundle history records, not mounted snapshot paths." : uncached.isEmpty ? "Known snapshot sizes are cached; history-only rows need a mounted image before they can be measured." : "Measure total disk usage of snapshots without cached sizes")
                        }
                    }
                }

                commandFeedback(for: .destinationSnapshots(destination.id))
            }
        }
    }

    @ViewBuilder
    func backupPathLabel(_ path: String) -> some View {
        if !isMeasurableBackupPath(path), isTimeMachineSnapshotPath(path) {
            VStack(alignment: .leading, spacing: 2) {
                Text(backupDisplayName(path))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                AppPathText(path: path, style: .caption, isSelectable: true)
                    .foregroundStyle(.tertiary)
            }
        } else {
            AppPathText(path: path)
        }
    }

    func backupDisplayName(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents.reversed()
        if let backupComponent = components.first(where: { $0.lowercased().hasSuffix(".backup") }) {
            return "Snapshot \(backupComponent)"
        }
        return path
    }

    func isMeasurableBackupPath(_ path: String) -> Bool {
        measurableBackupPath(for: path) != nil
    }

    func measurableBackupPath(for path: String) -> String? {
        let candidates = backupPathMeasurementCandidates(for: path)
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    func backupPathMeasurementCandidates(for path: String) -> [String] {
        var candidates = [path]
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        let parent = url.deletingLastPathComponent()
        if last.localizedCaseInsensitiveCompare(parent.lastPathComponent) == .orderedSame,
           last.lowercased().hasSuffix(".backup") {
            candidates.append(parent.path)
        }

        return candidates.reduce(into: [String]()) { result, candidate in
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
    }

    func measurableBackupEntries(in paths: [String]) -> [(cacheKey: String, measurementPath: String)] {
        paths.compactMap { path in
            measurableBackupPath(for: path).map { (cacheKey: path, measurementPath: $0) }
        }
    }

    func isTimeMachineSnapshotPath(_ path: String) -> Bool {
        let lowercasedPath = path.lowercased()
        return lowercasedPath.hasPrefix("/volumes/.timemachine/")
            && lowercasedPath.contains(".backup/")
            && lowercasedPath.hasSuffix(".backup")
    }

    func presentBackupHistoryList(_ history: TimeMachineBackupHistory, destination: TimeMachineDestination) {
        let context = TimeMachineCommandContext.destinationSnapshots(destination.id)
        let detail = history.backups.joined(separator: "\n")
        commandResults[context] = TimeMachineCommandPresentation(
            title: "List Backups",
            summary: "Listed \(history.backups.count) backup\(history.backups.count == 1 ? "" : "s") from loaded destination history.",
            detail: detail.isEmpty ? "No backup history is loaded for \(destination.name)." : detail,
            tone: history.backups.isEmpty ? .warning : .success,
            exitCode: nil
        )
        store.statusMessage = history.backups.isEmpty ? "No loaded backup history" : "Listed loaded backup history"
    }

    func presentLatestBackup(_ history: TimeMachineBackupHistory, destination: TimeMachineDestination) {
        let context = TimeMachineCommandContext.destinationSnapshots(destination.id)
        let latest = history.backups.last
        let exists = latest.map { FileManager.default.fileExists(atPath: $0) } ?? false
        commandResults[context] = TimeMachineCommandPresentation(
            title: "Latest Backup",
            summary: latest == nil
                ? "No loaded backup history for \(destination.name)."
                : exists
                    ? "Latest mounted backup from loaded destination history."
                    : "Latest backup history record is not mounted.",
            detail: latest.map { path in
                exists
                    ? path
                    : "\(path)\n\nThis path is a Time Machine history record, but it does not currently exist on disk. Attach or remount the backup image before browsing, comparing, or measuring this snapshot."
            } ?? "No backup history is loaded for \(destination.name).",
            tone: latest == nil ? .warning : exists ? .success : .warning,
            exitCode: nil
        )
        store.statusMessage = latest == nil
            ? "No loaded backup history"
            : exists ? "Latest backup found in loaded history" : "Latest backup is history-only"
    }

}
