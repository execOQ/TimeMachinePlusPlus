import AppKit
import SwiftUI

private struct SnapshotDateRowItem: Identifiable {
    let date: String
    var id: String { date }
}

extension TimeMachineCommandSurface {
    var snapshotsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Local Snapshots", subtitle: "\(store.localSnapshotDates.count) local snapshot date\(store.localSnapshotDates.count == 1 ? "" : "s") found for /.")

            HStack(spacing: 10) {
                Button {
                    run(arguments: ["localsnapshot"], context: .snapshots, title: "Create Snapshot", status: "Creating local snapshot...")
                } label: {
                    primaryButtonLabel("Create Snapshot", systemImage: "plus")
                }

                Button(role: .destructive) {
                    pendingDestructiveAction = .thinSnapshots(snapshotPurgeAmount, snapshotUrgency)
                } label: {
                    primaryButtonLabel("Thin Snapshots", systemImage: "scissors")
                }
            }

            AppSectionView(title: "Local Snapshots") {
                HStack(spacing: 10) {
                    Button {
                        run(arguments: ["enablelocal"], context: .snapshots, title: "Enable Local Snapshots", asAdministrator: true, status: "Enabling local snapshots...")
                    } label: {
                        primaryButtonLabel("Enable", systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        run(arguments: ["disablelocal"], context: .snapshots, title: "Disable Local Snapshots", asAdministrator: true, status: "Disabling local snapshots...")
                    } label: {
                        primaryButtonLabel("Disable", systemImage: "pause.circle")
                    }
                }
            }

            commandFeedback(for: .snapshots)

            AppSectionView(title: "Thin Options") {
                HStack(spacing: 10) {
                    TextField("Purge amount bytes", text: snapshotPurgeAmountBinding)
                        .textFieldStyle(.roundedBorder)
                    TextField("Urgency", text: snapshotUrgencyBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
            }

            AppSectionView(title: "Snapshot Dates") {
                if store.localSnapshotDates.isEmpty {
                    Text("No local snapshot dates found.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.localSnapshotDates.map(SnapshotDateRowItem.init)) { item in
                            let date = item.date
                            HStack {
                                AppPathText(path: date)
                                Spacer()
                                Button(role: .destructive) {
                                    pendingDestructiveAction = .deleteSnapshot(date)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.borderless)
                                .help("Delete snapshot")
                            }
                            Divider()
                        }
                    }
                }
            }
        }
    }


}
