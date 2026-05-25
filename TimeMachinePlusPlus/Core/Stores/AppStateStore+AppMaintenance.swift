import AppKit
import AppUpdater
import Combine
import Foundation
import UserNotifications

extension AppStateStore {
    func configureAppUpdater() {
        appUpdater.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.handleAppUpdaterState(state)
                }
            }
            .store(in: &updateCancellables)

        appUpdater.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                Task { @MainActor in
                    self?.updateLastError = error.map { String(describing: $0) }
                }
            }
            .store(in: &updateCancellables)
    }

    func refreshLoginItemStatus() {
        isLoginItemEnabled = loginItem.isEnabled
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try loginItem.setEnabled(isEnabled)
            refreshLoginItemStatus()
            statusMessage = isEnabled ? "TimeMachine++ will open at login" : "TimeMachine++ will not open at login"
        } catch {
            refreshLoginItemStatus()
            statusMessage = "Could not update login item: \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        startUpdateCheck(isAutomatic: false)
    }

    func checkForUpdatesAutomaticallyIfNeeded() {
        guard settings.automaticallyChecksForUpdates else { return }
        guard shouldRunAutomaticUpdateCheck else { return }
        requestUpdateNotificationPermission()
        startUpdateCheck(isAutomatic: true)
    }

    func openLatestReleasePage() {
        let url = updateReleaseURL ?? URL(string: "https://github.com/execOQ/TimeMachineAdvanced/releases")!
        NSWorkspace.shared.open(url)
    }

    func installDownloadedUpdate() {
        guard case .downloaded(_, _, let bundle) = appUpdater.state else { return }
        updateStatus = .installing
        updateStatusMessage = "Installing update..."
        statusMessage = updateStatusMessage

        appUpdater.install(bundle, success: { [weak self] in
            Task { @MainActor in
                self?.updateStatusMessage = "Update installed"
                self?.statusMessage = "Update installed"
            }
        }, fail: { [weak self] error in
            Task { @MainActor in
                self?.updateStatus = .failed
                self?.updateLastError = String(describing: error)
                self?.updateStatusMessage = "Could not install update"
                self?.statusMessage = "Could not install update: \(error.localizedDescription)"
            }
        })
    }

    func requestUpdateNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private var shouldRunAutomaticUpdateCheck: Bool {
        guard let lastUpdateCheckDate else { return true }
        return Date().timeIntervalSince(lastUpdateCheckDate) >= 24 * 60 * 60
    }

    private func startUpdateCheck(isAutomatic: Bool) {
        guard updateStatus != .checking, updateStatus != .downloading, updateStatus != .installing else { return }

        updateStatus = .checking
        updateDownloadProgress = nil
        updateLastError = nil
        updateStatusMessage = isAutomatic ? "Automatically checking for updates..." : "Checking for updates..."
        statusMessage = updateStatusMessage

        appUpdater.check(success: { [weak self] in
            Task { @MainActor in
                self?.lastUpdateCheckDate = Date()
                self?.save()
            }
        }, fail: { [weak self] error in
            Task { @MainActor in
                self?.lastUpdateCheckDate = Date()
                self?.updateDownloadProgress = nil
                self?.updateLastError = String(describing: error)
                if self?.appUpdater.state.release == nil {
                    self?.updateStatus = .upToDate
                    self?.updateStatusMessage = "TimeMachine++ is up to date"
                    self?.statusMessage = "TimeMachine++ is up to date"
                } else {
                    self?.updateStatus = .failed
                    self?.updateStatusMessage = "Could not download update"
                    self?.statusMessage = "Could not download update: \(error.localizedDescription)"
                }
                self?.save()
            }
        })
    }

    private func handleAppUpdaterState(_ state: AppUpdater.UpdateState) {
        switch state {
        case .none:
            if updateStatus != .checking {
                updateStatus = .idle
                updateDownloadProgress = nil
                updateReleaseVersion = nil
                updateReleaseName = nil
                updateReleaseNotes = ""
                updateReleaseURL = nil
            }
        case .newVersionDetected(let release, _):
            updateStatus = .available
            capture(release: release)
            updateDownloadProgress = nil
            updateStatusMessage = "Update available: \(release.name)"
            statusMessage = updateStatusMessage
        case .downloading(let release, _, let fraction):
            updateStatus = .downloading
            capture(release: release)
            updateDownloadProgress = fraction
            updateStatusMessage = "Downloading \(release.tagName.description)..."
            statusMessage = updateStatusMessage
        case .downloaded(let release, _, _):
            updateStatus = .readyToInstall
            capture(release: release)
            updateDownloadProgress = 1
            updateStatusMessage = "Update ready to install: \(release.name)"
            statusMessage = updateStatusMessage
            notifyUpdateReadyIfNeeded(version: release.tagName.description, name: release.name)
        }
    }

    private func capture(release: Release) {
        updateReleaseVersion = release.tagName.description
        updateReleaseName = release.name
        updateReleaseURL = URL(string: release.htmlUrl)

        updateCheckTask?.cancel()
        updateCheckTask = Task { @MainActor in
            let notes = await appUpdater.localizedChangelog(for: release) ?? release.body
            guard !Task.isCancelled else { return }
            updateReleaseNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func notifyUpdateReadyIfNeeded(version: String, name: String) {
        guard AppUpdateNotificationPolicy.shouldNotify(version: version, lastNotifiedVersion: lastNotifiedUpdateVersion) else { return }
        lastNotifiedUpdateVersion = version
        save()

        requestUpdateNotificationPermission()

        let content = UNMutableNotificationContent()
        content.title = "New TimeMachine++ update is available"
        content.body = "\(name) is downloaded and ready to install."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "timemachineplusplus-update-\(version)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension AppUpdateStatus {
    var settingsIcon: String {
        switch self {
        case .idle, .upToDate:
            return "checkmark.circle"
        case .checking, .available, .downloading, .installing:
            return "arrow.triangle.2.circlepath"
        case .readyToInstall:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}
