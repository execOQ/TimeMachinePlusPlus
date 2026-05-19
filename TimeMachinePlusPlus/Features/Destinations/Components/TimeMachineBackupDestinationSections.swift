import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    var backupsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Backups", subtitle: store.backupStatus.isRunning ? "A Time Machine backup is running." : "No Time Machine backup is currently running.")

            HStack(spacing: 10) {
                Button {
                    run(arguments: ["startbackup", "--auto"], context: .backups, title: "Start Backup", status: "Starting backup...")
                } label: {
                    primaryButtonLabel("Start Backup", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    run(arguments: ["startbackup", "--auto", "--block"], context: .backups, title: "Start and Wait", status: "Starting backup and waiting...")
                } label: {
                    primaryButtonLabel("Start and Wait", systemImage: "hourglass")
                }

                Spacer()

                Button(role: .destructive) {
                    pendingDestructiveAction = .stopBackup
                } label: {
                    primaryButtonLabel("Stop Backup", systemImage: "stop.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.8))
                .disabled(!store.backupStatus.isRunning)
            }

            AppSectionView(title: "Automatic Backups") {
                HStack(spacing: 10) {
                    Button {
                        run(arguments: ["enable"], context: .backups, title: "Enable Automatic Backups", asAdministrator: true, status: "Enabling automatic backups...")
                    } label: {
                        primaryButtonLabel("Enable", systemImage: "checkmark.circle")
                    }

                    Button {
                        run(arguments: ["disable"], context: .backups, title: "Disable Automatic Backups", asAdministrator: true, status: "Disabling automatic backups...")
                    } label: {
                        primaryButtonLabel("Disable", systemImage: "pause.circle")
                    }
                }
            }

            commandFeedback(for: .backups)

            addDestinationView
            adoptionBox
        }
    }

    @ViewBuilder
    func destinationView(_ destination: TimeMachineDestination?) -> some View {
        if let destination {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(destination.name, subtitle: destination.detail)

                AppSectionView(title: "Destination Actions") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button {
                                run(arguments: ["startbackup", "--destination", destination.id], context: .destinationActions(destination.id), title: "Back Up Here", status: "Starting backup to \(destination.name)...")
                            } label: {
                                primaryButtonLabel("Back Up Here", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Spacer()

                            Button(role: .destructive) {
                                pendingDestructiveAction = .removeDestination(destination)
                            } label: {
                                primaryButtonLabel("Remove Destination", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red.opacity(0.8))
                        }

                        Divider()

                        HStack(spacing: 10) {
                            TextField("Quota in GB", text: quotaGBBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)

                            Button {
                                let quota = quotaGB.trimmingCharacters(in: .whitespacesAndNewlines)
                                run(arguments: ["setquota", destination.id, quota], context: .destinationActions(destination.id), title: "Set Quota", asAdministrator: true, status: "Setting quota...")
                            } label: {
                                primaryButtonLabel("Set Quota", systemImage: "internaldrive")
                            }
                            .disabled(quotaGB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        commandFeedback(for: .destinationActions(destination.id))
                    }
                }

                if let mountPoint = destination.mountPoint {
                    storageBox(mountPoint: mountPoint)
                }

                backupHistoryBox(for: destination)

                destinationRestoreCompareBox(destination: destination)
            }
            .task(id: destination.id) {
                // Fetch volume stats async so UI doesn't block on network volumes
                if let mountPoint = destination.mountPoint {
                    let stats = await Task.detached(priority: .utility) { () -> (Int64, Int64) in
                        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: mountPoint)
                        let total = (attrs?[.systemSize] as? Int64) ?? 0
                        let free = (attrs?[.systemFreeSize] as? Int64) ?? 0
                        return (total, free)
                    }.value
                    volumeStats[mountPoint] = (stats.0, stats.1)
                }
                // Auto-measure any uncached snapshot sizes in the background
                let backups = store.backupHistoriesByDestinationID[destination.id]?.backups ?? []
                let uncached = backups.filter { store.snapshotSizeCache[$0] == nil }
                if !uncached.isEmpty {
                    startMeasuringSizes(backups: uncached)
                }
            }
        } else {
            Text("Select a destination.")
                .foregroundStyle(.secondary)
        }
    }

    var addDestinationView: some View {
        AppSectionView(title: "Add Destination") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("/Volumes/Backup Disk or smb://user@host/share", text: destinationURLBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        pickDestination()
                    } label: {
                        Image(systemName: "folder")
                            .foregroundStyle(.primary)
                    }
                    .help("Choose local volume")
                }

                HStack(spacing: 10) {
                    Button {
                        let value = destinationURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        run(arguments: ["setdestination", value], context: .addDestination, title: "Replace Destinations", asAdministrator: true, status: "Setting destination...")
                    } label: {
                        primaryButtonLabel("Replace Destinations", systemImage: "externaldrive")
                    }
                    .disabled(destinationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        let value = destinationURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        run(arguments: ["setdestination", "-a", value], context: .addDestination, title: "Add Destination", asAdministrator: true, status: "Adding destination...")
                    } label: {
                        primaryButtonLabel("Add", systemImage: "plus")
                    }
                    .disabled(destinationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                commandFeedback(for: .addDestination)
            }
        }
    }
}
