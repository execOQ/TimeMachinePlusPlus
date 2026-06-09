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

    func downloadAvailableUpdate() {
        startUpdateDownload(knownAvailableRelease: nil)
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

        Task { @MainActor in
            let availableRelease = await fetchAvailableGitHubRelease()
            guard !Task.isCancelled else { return }

            lastUpdateCheckDate = Date()

            if let availableRelease {
                capture(metadata: availableRelease)
                updateStatus = .available
                updateStatusMessage = "Update available: \(availableRelease.displayName)"
                statusMessage = updateStatusMessage
                save()

                if isAutomatic {
                    startUpdateDownload(knownAvailableRelease: availableRelease)
                }
                return
            }

            updateStatus = .upToDate
            updateStatusMessage = "TimeMachine++ is up to date"
            statusMessage = updateStatusMessage
            save()
        }
    }

    private func startUpdateDownload(knownAvailableRelease: GitHubReleaseMetadata?) {
        guard updateStatus != .checking, updateStatus != .downloading, updateStatus != .installing else { return }

        updateStatus = .downloading
        updateDownloadProgress = nil
        updateLastError = nil
        updateStatusMessage = "Preparing update download..."
        statusMessage = updateStatusMessage

        Task { @MainActor [weak self] in
            let availableRelease: GitHubReleaseMetadata?
            if let knownAvailableRelease {
                availableRelease = knownAvailableRelease
            } else {
                availableRelease = await self?.fetchAvailableGitHubRelease()
            }
            guard !Task.isCancelled, let self else { return }

            if let availableRelease {
                capture(metadata: availableRelease)
            }

            appUpdater.check(success: { [weak self] in
                Task { @MainActor in
                    self?.lastUpdateCheckDate = Date()
                    self?.save()
                }
            }, fail: { [weak self] error in
                Task { @MainActor in
                    self?.handleUpdateDownloadFailure(error, knownAvailableRelease: availableRelease)
                }
            })
        }
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
            capture(release: release)
            updateDownloadProgress = nil
            if updateStatus == .downloading {
                updateStatusMessage = "Preparing \(release.name)..."
            } else {
                updateStatus = .available
                updateStatusMessage = "Update available: \(release.name)"
            }
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

        updateReleaseNotesTask?.cancel()
        updateReleaseNotesTask = Task { @MainActor in
            let notes = await appUpdater.localizedChangelog(for: release) ?? release.body
            guard !Task.isCancelled else { return }
            updateReleaseNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func capture(metadata release: GitHubReleaseMetadata) {
        updateReleaseVersion = release.version
        updateReleaseName = release.displayName
        updateReleaseURL = release.htmlURL
        updateReleaseNotes = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleUpdateDownloadFailure(_ error: Error, knownAvailableRelease: GitHubReleaseMetadata?) {
        lastUpdateCheckDate = Date()
        updateDownloadProgress = nil
        updateLastError = userFacingUpdateDownloadError(error, release: knownAvailableRelease)

        if let knownAvailableRelease {
            capture(metadata: knownAvailableRelease)
            updateStatus = .available
            updateStatusMessage = "Could not prepare automatic download for \(knownAvailableRelease.displayName)"
            statusMessage = updateStatusMessage
        } else if appUpdater.state.release == nil {
            updateStatus = .failed
            updateStatusMessage = "Could not check update download"
            statusMessage = updateStatusMessage
        } else {
            updateStatus = .failed
            updateStatusMessage = "Could not download update"
            statusMessage = "Could not download update: \(error.localizedDescription)"
        }

        save()
    }

    private func userFacingUpdateDownloadError(_ error: Error, release: GitHubReleaseMetadata?) -> String {
        if let appUpdaterError = error as? AppUpdater.Error {
            switch appUpdaterError {
            case .noValidUpdate:
                if let release {
                    return "A newer release exists, but the automatic updater could not find an installable zip asset for \(release.displayName). Open the release and check that the zip asset name and content type match the updater."
                }
                return "The automatic updater could not find an installable release asset."
            case .codeSigningIdentity:
                return "The downloaded app could not be verified against the current app's code signing identity."
            case .invalidDownloadedBundle:
                return "The downloaded archive did not contain a valid app bundle."
            case .unzipFailed:
                return "The downloaded update archive could not be unzipped."
            case .downloadFailed:
                return "The update archive could not be downloaded."
            case .bundleExecutableURL:
                return "The current app bundle could not be inspected for updating."
            @unknown default:
                break
            }
        }

        return String(describing: error)
    }

    private func fetchAvailableGitHubRelease() async -> GitHubReleaseMetadata? {
        do {
            let releases = try await fetchGitHubReleases()
                .filter { !$0.isPrerelease }
                .sorted { AppVersionComparator.isNewer($0.version, than: $1.version) }

            return releases.first {
                AppVersionComparator.isNewer($0.version, than: AppBuildInfo.version)
            }
        } catch {
            updateLastError = String(describing: error)
            return nil
        }
    }

    private func fetchGitHubReleases() async throws -> [GitHubReleaseMetadata] {
        let url = URL(string: "https://api.github.com/repos/execOQ/TimeMachineAdvanced/releases")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([GitHubReleaseMetadata].self, from: data)
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
        case .checking, .installing:
            return "arrow.triangle.2.circlepath"
        case .available, .downloading:
            return "arrow.down.circle"
        case .readyToInstall:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}
