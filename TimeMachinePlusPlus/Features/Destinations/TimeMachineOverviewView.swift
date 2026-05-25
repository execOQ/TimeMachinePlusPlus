import AppKit
import Charts
import SwiftUI

struct TimeMachineOverviewView: TimeMachineCommandSurface {
    @Environment(AppStateStore.self) var store

    @State private var overviewState = TimeMachineOverviewCommandState()
    @State private var destinationState = TimeMachineDestinationCommandState()
    @State private var pathState = TimeMachinePathCommandState()
    @State private var commandState = TimeMachineCommandState()

    let client = LiveTimeMachineClient()
    let destinationContextID: String? = nil

    var quotaGB: String {
        get { destinationState.quotaGB }
        nonmutating set { destinationState.quotaGB = newValue }
    }

    var destinationURL: String {
        get { overviewState.destinationURL }
        nonmutating set { overviewState.destinationURL = newValue }
    }

    var exclusionPaths: String {
        get { pathState.exclusionPaths }
        nonmutating set { pathState.exclusionPaths = newValue }
    }

    var selectedSnapshots: Set<String> {
        get { destinationState.selectedSnapshots }
        nonmutating set { destinationState.selectedSnapshots = newValue }
    }

    var comparePaths: String {
        get { pathState.comparePaths }
        nonmutating set { pathState.comparePaths = newValue }
    }

    var backupDeletePaths: String {
        get { pathState.backupDeletePaths }
        nonmutating set { pathState.backupDeletePaths = newValue }
    }

    var inheritBackupPath: String {
        get { overviewState.inheritBackupPath }
        nonmutating set { overviewState.inheritBackupPath = newValue }
    }

    var associateMountPoint: String {
        get { overviewState.associateMountPoint }
        nonmutating set { overviewState.associateMountPoint = newValue }
    }

    var associateSnapshotVolume: String {
        get { overviewState.associateSnapshotVolume }
        nonmutating set { overviewState.associateSnapshotVolume = newValue }
    }

    var associateAllSnapshots: Bool {
        get { overviewState.associateAllSnapshots }
        nonmutating set { overviewState.associateAllSnapshots = newValue }
    }

    var diagnosticPaths: String {
        get { pathState.diagnosticPaths }
        nonmutating set { pathState.diagnosticPaths = newValue }
    }

    var snapshotPurgeAmount: String {
        get { destinationState.snapshotPurgeAmount }
        nonmutating set { destinationState.snapshotPurgeAmount = newValue }
    }

    var snapshotUrgency: String {
        get { destinationState.snapshotUrgency }
        nonmutating set { destinationState.snapshotUrgency = newValue }
    }

    var commandActivity: TimeMachineCommandActivity? {
        get { commandState.activity }
        nonmutating set { commandState.activity = newValue }
    }

    var commandResults: [TimeMachineCommandContext: TimeMachineCommandPresentation] {
        get { commandState.results }
        nonmutating set { commandState.results = newValue }
    }

    var pendingDestructiveAction: DestructiveAction? {
        get { commandState.pendingDestructiveAction }
        nonmutating set { commandState.pendingDestructiveAction = newValue }
    }

    var pendingBackupImageAttachRequest: BackupImageAttachRequest? {
        get { commandState.pendingBackupImageAttachRequest }
        nonmutating set { commandState.pendingBackupImageAttachRequest = newValue }
    }

    var sizeTask: Task<Void, Never>? {
        get { destinationState.sizeTask }
        nonmutating set { destinationState.sizeTask = newValue }
    }

    var volumeStats: [String: (total: Int64, free: Int64)] {
        get { destinationState.volumeStats }
        nonmutating set { destinationState.volumeStats = newValue }
    }

    var body: some View {
        PageView(title: "Time Machine Overview", subtitle: "Backup status, destination setup, and adoption controls") {
            List {
                VStack(alignment: .leading, spacing: 18) {
                    backupsView
                }
                .scenePadding()
            }
            .listStyle(.plain)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    refresh()
                } label: {
                    primaryButtonLabel("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isWorking)
            }

            toolbarOperationItems
        }
        .confirmationDialog(
            "This changes Time Machine backup data.",
            isPresented: destructiveActionPresented
        ) {
            if let action = pendingDestructiveAction {
                Button(action.buttonTitle, role: .destructive) {
                    runDestructiveAction(action)
                }
                .foregroundStyle(.primary)
            }
            Button("Cancel", role: .cancel) {}
                .foregroundStyle(.primary)
        } message: {
            Text(pendingDestructiveAction?.message ?? "")
        }
        .alert(
            "Attaching a NAS Backup Image Can Be Slow",
            isPresented: backupImageAttachWarningPresented
        ) {
            Button(pendingBackupImageAttachRequest?.buttonTitle ?? "Attach") {
                runPendingBackupImageAttachRequest()
            }
            Button("Cancel", role: .cancel) {
                pendingBackupImageAttachRequest = nil
            }
        } message: {
            Text("Time Machine sparsebundles on a NAS can take from several minutes to several hours to attach, depending on the size of the image.")
        }
    }
}
