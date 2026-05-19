import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppStateStore {
    var rules: [RegexRule] = []
    var manualExclusions: [ManualExclusion] = []
    var appliedExclusions: [AppliedExclusion] = []
    var settings: AppSettings = .defaults
    var snapshotSizeCache: [String: Int64] = [:]
    var matches: [ScanMatch] = []
    var selectedSelection: AppSidebarSelection = .section(.exclusionRules)
    var statusMessage = "Ready"
    var lastScanDate: Date?
    var isWorking = false
    var canCancelCurrentOperation = true
    var operationTitle: String?
    var operationDetail: String?
    var operationProgress: Double?
    var isHelperInstalled = false
    var timeMachineDestinations: [TimeMachineDestination] = []
    var backupHistoriesByDestinationID: [String: TimeMachineBackupHistory] = [:]
    var backupStatus: TimeMachineBackupStatus = .unknown
    var localSnapshotDates: [String] = []
    var fullDiskAccessStatus: FullDiskAccessStatus = .missing
    var isMeasuringSizes = false

    @ObservationIgnored
    let storage = StateStorage()
    @ObservationIgnored
    let scanner = FileSystemScanner()
    @ObservationIgnored
    let timeMachine: TimeMachineClient
    @ObservationIgnored
    let launchAgent = LaunchAgentService()
    @ObservationIgnored
    var activeTask: Task<Void, Never>?
    @ObservationIgnored
    var didStartBackupDuringActiveTask = false
    @ObservationIgnored
    var operationActivityToken: NSObjectProtocol?
    @ObservationIgnored
    var backupActivityToken: NSObjectProtocol?
    @ObservationIgnored
    var backupActivityTask: Task<Void, Never>?

    var canEdit: Bool { !isWorking }
    var startActionTitle: String {
        settings.startButtonStartsBackup ? "Scan + Start Backup" : "Scan + Apply Exclusions"
    }
    var startActionHelp: String {
        settings.startButtonStartsBackup
            ? "Scan, apply exclusions, then start Time Machine backup"
            : "Scan and apply exclusions without starting a backup"
    }
    var isCombinedStartOperation: Bool {
        operationTitle == "Scan + Backup" || operationTitle == "Scan + Apply"
    }

    init(timeMachine: TimeMachineClient = LiveTimeMachineClient()) {
        self.timeMachine = timeMachine
    }

}
