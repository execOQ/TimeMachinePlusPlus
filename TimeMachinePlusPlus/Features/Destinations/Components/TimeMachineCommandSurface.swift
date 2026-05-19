import SwiftUI

struct TimeMachineCommandState {
    var activity: TimeMachineCommandActivity?
    var results: [TimeMachineCommandContext: TimeMachineCommandPresentation] = [:]
    var pendingDestructiveAction: DestructiveAction?
}

struct TimeMachineOverviewCommandState {
    var destinationURL = ""
    var inheritBackupPath = ""
    var associateMountPoint = ""
    var associateSnapshotVolume = ""
    var associateAllSnapshots = false
}

struct TimeMachineDestinationCommandState {
    var quotaGB = ""
    var selectedSnapshots: Set<String> = []
    var restoreSources = ""
    var restoreDestination = ""
    var snapshotPurgeAmount = ""
    var snapshotUrgency = "4"
    var sizeTask: Task<Void, Never>?
    var volumeStats: [String: (total: Int64, free: Int64)] = [:]
}

struct TimeMachinePathCommandState {
    var exclusionPaths = ""
    var comparePaths = ""
    var backupDeletePaths = ""
    var diagnosticPaths = ""
}

@MainActor
protocol TimeMachineCommandSurface: View {
    var store: AppStateStore { get }
    var destinationContextID: String? { get }
    var quotaGB: String { get nonmutating set }
    var destinationURL: String { get nonmutating set }
    var exclusionPaths: String { get nonmutating set }
    var selectedSnapshots: Set<String> { get nonmutating set }
    var restoreSources: String { get nonmutating set }
    var restoreDestination: String { get nonmutating set }
    var comparePaths: String { get nonmutating set }
    var backupDeletePaths: String { get nonmutating set }
    var inheritBackupPath: String { get nonmutating set }
    var associateMountPoint: String { get nonmutating set }
    var associateSnapshotVolume: String { get nonmutating set }
    var associateAllSnapshots: Bool { get nonmutating set }
    var diagnosticPaths: String { get nonmutating set }
    var snapshotPurgeAmount: String { get nonmutating set }
    var snapshotUrgency: String { get nonmutating set }
    var commandActivity: TimeMachineCommandActivity? { get nonmutating set }
    var commandResults: [TimeMachineCommandContext: TimeMachineCommandPresentation] { get nonmutating set }
    var pendingDestructiveAction: DestructiveAction? { get nonmutating set }
    var sizeTask: Task<Void, Never>? { get nonmutating set }
    var volumeStats: [String: (total: Int64, free: Int64)] { get nonmutating set }
    var client: LiveTimeMachineClient { get }
}
