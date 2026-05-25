import AppKit
import AppUpdater
import Combine
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
    var lastHelperScanDate: Date?
    var lastHelperScannedItemCount = 0
    var lastHelperAddedExclusionCount = 0
    var isWorking = false
    var canCancelCurrentOperation = true
    var operationTitle: String?
    var operationDetail: String?
    var operationProgress: Double?
    var isHelperInstalled = false
    var isHelperLoaded = false
    var isHelperRunning = false
    var helperRunCount: Int?
    var helperLastExitCode: Int32?
    var timeMachineDestinations: [TimeMachineDestination] = []
    var backupHistoriesByDestinationID: [String: TimeMachineBackupHistory] = [:]
    var backupStatus: TimeMachineBackupStatus = .unknown
    var localSnapshotDates: [String] = []
    var fullDiskAccessStatus: FullDiskAccessStatus = .missing
    var isMeasuringSizes = false
    var isLoginItemEnabled = false
    var updateStatus: AppUpdateStatus = .idle
    var updateReleaseVersion: String?
    var updateReleaseName: String?
    var updateReleaseNotes = ""
    var updateReleaseURL: URL?
    var updateDownloadProgress: Double?
    var updateLastError: String?
    var updateStatusMessage = "Update status unknown"
    var lastUpdateCheckDate: Date?
    var lastNotifiedUpdateVersion: String?

    @ObservationIgnored
    let storage = StateStorage()
    @ObservationIgnored
    let scanner = FileSystemScanner()
    @ObservationIgnored
    let timeMachine: TimeMachineClient
    @ObservationIgnored
    let launchAgent = LaunchAgentService()
    @ObservationIgnored
    let loginItem = LoginItemService()
    @ObservationIgnored
    let appUpdater = AppUpdater(owner: "execOQ", repo: "TimeMachineAdvanced", releasePrefix: "TimeMachine++", interval: 365 * 24 * 60 * 60)
    @ObservationIgnored
    var activeTask: Task<Void, Never>?
    @ObservationIgnored
    var updateCheckTask: Task<Void, Never>?
    @ObservationIgnored
    var updateCancellables = Set<AnyCancellable>()
    @ObservationIgnored
    var didStartBackupDuringActiveTask = false
    @ObservationIgnored
    var operationActivityToken: NSObjectProtocol?
    @ObservationIgnored
    var backupActivityToken: NSObjectProtocol?
    @ObservationIgnored
    var backupActivityTask: Task<Void, Never>?
    @ObservationIgnored
    var attemptedNetworkShareMounts: Set<String> = []

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
    var helperScanSummary: String? {
        guard let lastHelperScanDate else { return nil }
        let relativeDate = Formatters.relativeDate.localizedString(for: lastHelperScanDate, relativeTo: Date())
        return "Helper scan \(relativeDate): \(lastHelperScannedItemCount) files scanned, \(lastHelperAddedExclusionCount) added to exceptions"
    }
    var helperRuntimeSummary: String? {
        guard isHelperInstalled else { return nil }
        if isHelperRunning { return "Helper is running now" }
        guard isHelperLoaded else { return "Helper is installed but disabled in macOS background items or not loaded" }
        if let helperRunCount, let helperLastExitCode {
            return "LaunchAgent runs: \(helperRunCount), last exit: \(helperLastExitCode)"
        }
        return "Helper is loaded"
    }
    var updateSummary: String {
        if let lastUpdateCheckDate {
            let relativeDate = Formatters.relativeDate.localizedString(for: lastUpdateCheckDate, relativeTo: Date())
            return "\(updateStatusMessage) Last checked \(relativeDate)."
        }
        return updateStatusMessage
    }
    var hasAvailableUpdate: Bool { updateStatus == .readyToInstall || updateStatus == .downloading || updateStatus == .available }
    var updateMenuBarSystemImage: String {
        updateStatus.menuBarSystemImage
    }

    init(timeMachine: TimeMachineClient = LiveTimeMachineClient()) {
        self.timeMachine = timeMachine
        configureAppUpdater()
    }

}
