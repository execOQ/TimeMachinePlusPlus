import Foundation

struct TimeMachineDestination: Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String
    var url: String?
    var mountPoint: String?
    var shareMountPoint: String?
    var sparsebundlePath: String?

    var detail: String {
        if let mountPoint, !mountPoint.isEmpty {
            return mountPoint
        }
        if let sparsebundlePath, !sparsebundlePath.isEmpty {
            return sparsebundlePath
        }
        if let shareMountPoint, !shareMountPoint.isEmpty {
            return shareMountPoint
        }
        if let url, !url.isEmpty {
            return url
        }
        return kind
    }
}

struct TimeMachineBackupHistory: Equatable {
    var destinationID: String
    var backups: [String]
    var machineDirectories: [String]
    var message: String?
    var requiresFullDiskAccess: Bool
    var noBackupsForCurrentHost: Bool

    static func empty(destinationID: String) -> TimeMachineBackupHistory {
        TimeMachineBackupHistory(
            destinationID: destinationID,
            backups: [],
            machineDirectories: [],
            message: nil,
            requiresFullDiskAccess: false,
            noBackupsForCurrentHost: false
        )
    }
}

struct TimeMachineBackupStatus: Equatable {
    var isRunning: Bool
    var rawOutput: String

    static let unknown = TimeMachineBackupStatus(isRunning: false, rawOutput: "")
}
