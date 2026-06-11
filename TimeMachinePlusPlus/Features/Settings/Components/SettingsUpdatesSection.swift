import SwiftUI

struct SettingsUpdatesSection: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        @Bindable var store = store

        AppSectionView(title: "Updates", description: "Updates are downloaded from GitHub releases.") {
            versionRow()
            releaseNotes()
            updateError()
            updateAction()
            automaticUpdatesToggle(store: store)
        }
    }

    // MARK: - View Components

    private func versionRow() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Label("Version \(AppBuildInfo.displayVersion)", systemImage: "app.badge")
                .foregroundStyle(.secondary)

            if let updateTargetVersionLabel {
                Label(updateTargetVersionLabel, systemImage: "arrow.right")
                    .foregroundStyle(updateStatusColor)
            }
        }
    }

    @ViewBuilder
    private func releaseNotes() -> some View {
        if !store.updateReleaseNotes.isEmpty {
            ReleaseNotesDisclosureList(markdown: store.updateReleaseNotes)
        }
    }

    @ViewBuilder
    private func updateError() -> some View {
        if let updateLastError = store.updateLastError, shouldShowUpdateError {
            Label(updateLastError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(updateStatusColor)
                .textSelection(.enabled)
        }
    }

    private func updateAction() -> some View {
        Group {
            switch store.updateStatus {
            case .downloading:
                downloadProgress()
            case .available:
                Button {
                    store.downloadAvailableUpdate()
                } label: {
                    Label("Download Update", systemImage: "arrow.down.circle")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                }
            case .readyToInstall:
                Button {
                    store.installDownloadedUpdate()
                } label: {
                    Label("Install Update", systemImage: "arrow.down.app")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                }
            default:
                checkUpdatesButton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func downloadProgress() -> some View {
        if let progress = store.updateDownloadProgress {
            ProgressView(value: progress) {
                Text("Downloading update")
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
            }
        } else {
            ProgressView {
                Text("Preparing download")
            }
        }
    }

    private func checkUpdatesButton() -> some View {
        Button {
            store.checkForUpdates()
        } label: {
            if store.updateStatus == .checking {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking...")
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Check Updates")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(store.updateStatus == .checking || store.updateStatus == .downloading || store.updateStatus == .installing)
        .help("Check GitHub releases for updates")
    }

    private func automaticUpdatesToggle(@Bindable store: AppStateStore) -> some View {
        VStack {
            Divider()

            Toggle(isOn: $store.settings.automaticallyChecksForUpdates) {
                Text("Automatically download updates")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .onChange(of: store.settings.automaticallyChecksForUpdates, onAutomaticUpdateChecksChanged)
        }
    }
}

private extension SettingsUpdatesSection {
    func onAutomaticUpdateChecksChanged() {
        if store.settings.automaticallyChecksForUpdates {
            store.requestUpdateNotificationPermission()
        }
    }

    var updateStatusColor: Color {
        switch store.updateStatus {
        case .failed:
            return .red
        case .available where store.updateLastError != nil:
            return .orange
        case .readyToInstall, .downloading, .available:
            return .blue
        case .checking, .installing:
            return .secondary
        case .idle, .upToDate:
            return .secondary
        }
    }

    var updateTargetVersionLabel: String? {
        if let updateReleaseVersion = store.updateReleaseVersion {
            return updateReleaseVersion
        }
        if let updateReleaseName = store.updateReleaseName {
            return updateReleaseName
        }

        switch store.updateStatus {
        case .checking:
            return "Checking"
        case .upToDate:
            return "Up to date"
        case .failed:
            return "Update failed"
        case .available, .downloading, .readyToInstall, .installing:
            return "Update available"
        default:
            return nil
        }
    }

    var shouldShowUpdateError: Bool {
        store.updateStatus == .failed || store.updateStatus == .available
    }
}

#Preview {
    SettingsUpdatesSection()
        .previewModifiers()
}
