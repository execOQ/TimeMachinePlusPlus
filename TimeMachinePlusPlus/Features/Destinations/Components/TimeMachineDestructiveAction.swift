import Foundation

enum DestructiveAction: Identifiable {
    case stopBackup
    case removeDestination(TimeMachineDestination)
    case deleteSnapshot(String)
    case thinSnapshots(String, String)
    case deleteBackupPaths([String])
    case deleteInProgress

    var id: String {
        switch self {
        case .stopBackup:
            return "stopBackup"
        case .removeDestination(let destination):
            return "removeDestination-\(destination.id)"
        case .deleteSnapshot(let date):
            return "deleteSnapshot-\(date)"
        case .thinSnapshots(let amount, let urgency):
            return "thinSnapshots-\(amount)-\(urgency)"
        case .deleteBackupPaths(let paths):
            return "deleteBackupPaths-\(paths.joined(separator: "|"))"
        case .deleteInProgress:
            return "deleteInProgress"
        }
    }

    var buttonTitle: String {
        switch self {
        case .stopBackup:
            return "Stop Backup"
        case .removeDestination:
            return "Remove Destination"
        case .deleteSnapshot:
            return "Delete Snapshot"
        case .thinSnapshots:
            return "Thin Snapshots"
        case .deleteBackupPaths:
            return "Delete Backup Paths"
        case .deleteInProgress:
            return "Delete In-Progress Backup"
        }
    }

    var message: String {
        switch self {
        case .stopBackup:
            return "The currently running backup will be stopped."
        case .removeDestination(let destination):
            return "\(destination.name) will be removed from Time Machine destinations."
        case .deleteSnapshot(let date):
            return "Local snapshot \(date) will be deleted."
        case .thinSnapshots:
            return "Time Machine will purge local snapshots for the startup volume."
        case .deleteBackupPaths(let paths):
            return "\(paths.count) backup path\(paths.count == 1 ? "" : "s") will be deleted."
        case .deleteInProgress:
            return "The in-progress backup will be deleted."
        }
    }
}
