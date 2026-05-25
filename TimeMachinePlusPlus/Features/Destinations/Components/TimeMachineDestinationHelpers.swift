import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    func destinationSummaryBox(_ destination: TimeMachineDestination) -> some View {
        AppSectionView(title: "Destination") {
            VStack(alignment: .leading, spacing: 12) {
                Label(destination.detail, systemImage: destination.mountPoint == nil ? "network" : "externaldrive")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                if destination.isNetworkShareMissing {
                    HStack(spacing: 10) {
                        Label("Network share is not connected.", systemImage: "network.badge.shield.half.filled")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Spacer()

                        Button {
                            store.mountNetworkShare(for: destination)
                        } label: {
                            primaryButtonLabel("Mount Share", systemImage: "externaldrive.connected.to.line.below")
                        }
                        .disabled(store.isWorking)
                    }
                }

                if let sparsebundlePath = destination.sparsebundlePath {
                    HStack {
                        storageCell("Backup image", value: Formatters.fileSize(store.snapshotSizeCache[sparsebundlePath]))
                        Spacer()
                    }

                    if destination.mountPoint == nil {
                        HStack(spacing: 10) {
                            Label("Network share is mounted, but the backup image is not attached as a browsable snapshot volume.", systemImage: "externaldrive.badge.xmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                requestBackupImageAttach(destination)
                            } label: {
                                primaryButtonLabel("Attach Image", systemImage: "externaldrive.connected.to.line.below")
                            }
                            .disabled(store.isWorking)
                        }
                    }
                }

                if let storagePath = storageStatsPath(for: destination) {
                    storageContent(path: storagePath)
                } else {
                    Label("Storage statistics are available when the destination is mounted.", systemImage: "externaldrive.badge.xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func storageBox(mountPoint: String) -> some View {
        AppSectionView(title: "Storage") {
            storageContent(path: mountPoint)
        }
        .padding(.vertical, 2)
    }

    var compareSelectedTitle: String {
        selectedSnapshots.count == 1 ? "Compare with Current Mac State" : "Compare Selected"
    }

    @ViewBuilder
    func storageContent(path: String) -> some View {
        if let stats = volumeStats[path] {
            let used = max(0, stats.total - stats.free)
            let usedFraction = stats.total > 0 ? Double(used) / Double(stats.total) : 0
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: usedFraction)
                    .progressViewStyle(.linear)
                    .tint(usedFraction > 0.9 ? .red : usedFraction > 0.75 ? .orange : .accentColor)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                    GridRow {
                        storageCell("Taken", value: Formatters.fileSize(used))
                        storageCell("Free", value: Formatters.fileSize(stats.free))
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

    func storageCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
    }

    func storageStatsPath(for destination: TimeMachineDestination) -> String? {
        if let mountPoint = destination.mountPoint, FileManager.default.fileExists(atPath: mountPoint) {
            return mountPoint
        }
        if let shareMountPoint = destination.shareMountPoint, FileManager.default.fileExists(atPath: shareMountPoint) {
            return shareMountPoint
        }
        if let sparsebundlePath = destination.sparsebundlePath, FileManager.default.fileExists(atPath: sparsebundlePath) {
            return sparsebundlePath
        }
        return nil
    }

}
