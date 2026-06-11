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
    var matches: [ScanMatch] = []
    var statusMessage = "Ready"
    var rulesStatusMessage = "Ready"
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
    let appUpdater = AppUpdater(owner: "execOQ", repo: "TimeMachineAdvanced", releasePrefix: "TimeMachine++", interval: 365 * 24 * 60 * 60, provider: NormalizingGitHubReleaseProvider())
    @ObservationIgnored
    var activeTask: Task<Void, Never>?
    @ObservationIgnored
    var updateReleaseNotesTask: Task<Void, Never>?
    @ObservationIgnored
    var updateCancellables = Set<AnyCancellable>()
    @ObservationIgnored
    var operationActivityToken: NSObjectProtocol?

    var canEdit: Bool { !isWorking }
    var startActionTitle: String {
        "Scan + Apply Exclusions"
    }
    var startActionHelp: String {
        "Scan and apply exclusions without starting a backup"
    }
    var isScanAndApplyOperation: Bool {
        operationTitle == "Scan + Apply"
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
    var updateMenuBarImage: String {
        updateStatus.menuBarImage
    }

    init(timeMachine: TimeMachineClient = LiveTimeMachineClient()) {
        self.timeMachine = timeMachine
        configureAppUpdater()
    }

}
