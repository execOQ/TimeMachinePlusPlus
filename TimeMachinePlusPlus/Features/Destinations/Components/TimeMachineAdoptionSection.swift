import AppKit
import SwiftUI

extension TimeMachineCommandSurface {
    var adoptionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Adoption", subtitle: "Inherit existing backup history or associate a disk with snapshot history.")
            adoptionBox
        }
    }

    var adoptionBox: some View {
        AppSectionView(title: "Adoption") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inherit Backup")
                        .font(.headline)
                    Text("Claim an existing machine directory or sparsebundle for this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Machine directory or sparsebundle", text: inheritBackupPathBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            pickAdoptionPath(assignTo: inheritBackupPathBinding, canChooseFiles: true)
                        } label: {
                            Image(systemName: "folder")
                                .foregroundStyle(.primary)
                        }
                        .help("Choose machine directory or sparsebundle")
                    }

                    Button {
                        run(arguments: ["inheritbackup", inheritBackupPath], context: .adoption, title: "Inherit Backup", asAdministrator: true, status: "Inheriting backup...")
                    } label: {
                        primaryButtonLabel("Inherit", systemImage: "link")
                    }
                    .disabled(inheritBackupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Associate Disk")
                        .font(.headline)
                    Text("Connect a current mounted disk to an existing snapshot volume path.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Current mount point", text: associateMountPointBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            pickAdoptionPath(assignTo: associateMountPointBinding, canChooseFiles: false)
                        } label: {
                            Image(systemName: "folder")
                                .foregroundStyle(.primary)
                        }
                        .help("Choose current mount point")
                    }

                    HStack(spacing: 8) {
                        TextField("Snapshot volume path", text: associateSnapshotVolumeBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            pickAdoptionPath(assignTo: associateSnapshotVolumeBinding, canChooseFiles: false)
                        } label: {
                            Image(systemName: "folder")
                                .foregroundStyle(.primary)
                        }
                        .help("Choose snapshot volume")
                    }

                    Toggle("Apply to matching snapshots", isOn: associateAllSnapshotsBinding)

                    Button {
                        var arguments = ["associatedisk"]
                        if associateAllSnapshots {
                            arguments.append("-a")
                        }
                        arguments.append(contentsOf: [associateMountPoint, associateSnapshotVolume])
                        run(arguments: arguments, context: .adoption, title: "Associate Disk", asAdministrator: true, status: "Associating disk...")
                    } label: {
                        primaryButtonLabel("Associate", systemImage: "link.badge.plus")
                    }
                    .disabled(
                        associateMountPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || associateSnapshotVolume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                commandFeedback(for: .adoption)
            }
        }
    }

}
