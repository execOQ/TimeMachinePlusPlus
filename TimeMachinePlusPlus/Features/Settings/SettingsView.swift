import AppKit
import SwiftUI

private struct ScanRootRowItem: Identifiable {
    let path: String
    var id: String { path }
}

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        @Bindable var store = store

        PageView(title: "Settings") {
            List {
                VStack(alignment: .leading, spacing: 22) {
                    AppSectionView(title: "Scan Roots", description: "Pattern rules search these roots. Maximum depth limits how far TimeMachine++ walks below each root so previews and helper scans stay predictable.") {
                        ForEach(store.settings.scanRoots.map(ScanRootRowItem.init)) { item in
                            let root = item.path
                            AppPathRow(path: root) {
                                Button(role: .destructive) {
                                    store.deleteScanRoot(root)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button(action: pickScanRoots) {
                            Label("Add Scan Root", systemImage: "plus")
                                .foregroundStyle(.primary)
                        }

                        Stepper(value: $store.settings.maxDepth, in: 1...24) {
                            Text("Maximum scan depth: \(store.settings.maxDepth)")
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        Stepper(value: $store.settings.previewResultLimit, in: 5...200, step: 5) {
                            Text("Quick results limit: \(store.settings.previewResultLimit)")
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    AppSectionView(title: "Permissions", description: "TimeMachine++ needs Full Disk Access to manage exclusions for Time Machine backups. If you recently granted access, recheck the status.") {
                        HStack(spacing: 10) {
                            Label(store.fullDiskAccessStatus.label, systemImage: fullDiskAccessStatusIcon)
                                .foregroundStyle(fullDiskAccessStatusColor)

                            Spacer()

                            Button {
                                store.refreshFullDiskAccessStatus()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Recheck Full Disk Access status")

                            Button {
                                openFullDiskAccessSettings()
                            } label: {
                                AppActionLabel(title: "Open Settings", systemImage: "gear")
                            }
                        }
                    }

                    AppSectionView(title: "Interface", description: "When this is off, the toolbar Start button only scans and applies exclusions. Backups can still be started manually from Time Machine controls.") {
                        Toggle("Start backup after scanning and applying exclusions", isOn: $store.settings.startButtonStartsBackup)
                    }

                    AppSectionView(title: "App", description: "Launch at login is managed through macOS Login Items.") {
                        Toggle("Open TimeMachine++ when logging in", isOn: Binding(
                            get: { store.isLoginItemEnabled },
                            set: { store.setLaunchAtLogin($0) }
                        ))
                    }

                    AppSectionView(title: "Updates", description: "Updates are downloaded from GitHub releases. Installation starts only after you confirm it here.") {
                        HStack(spacing: 10) {
                            Label("Version \(AppBuildInfo.displayVersion)", systemImage: "app.badge")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                store.checkForUpdates()
                            } label: {
                                if store.updateStatus == .checking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(store.updateStatus == .checking || store.updateStatus == .downloading || store.updateStatus == .installing)
                            .help("Check GitHub releases for updates")

                            Button {
                                store.openLatestReleasePage()
                            } label: {
                                AppActionLabel(title: store.hasAvailableUpdate ? "View Release" : "Open Releases", systemImage: "safari")
                            }
                        }

                        Label(store.updateSummary, systemImage: store.updateStatus.settingsIcon)
                            .font(.caption)
                            .foregroundStyle(updateStatusColor)

                        if store.updateStatus == .downloading, let progress = store.updateDownloadProgress {
                            ProgressView(value: progress) {
                                Text("Downloading update")
                            } currentValueLabel: {
                                Text("\(Int(progress * 100))%")
                            }
                        }

                        if store.updateStatus == .readyToInstall {
                            Button {
                                store.installDownloadedUpdate()
                            } label: {
                                Label("Install Update", systemImage: "arrow.down.app")
                                    .foregroundStyle(.primary)
                            }
                        }

                        if let updateLastError = store.updateLastError, store.updateStatus == .failed {
                            Text(updateLastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }

                        Toggle("Automatically download updates", isOn: $store.settings.automaticallyChecksForUpdates)
                            .onChange(of: store.settings.automaticallyChecksForUpdates) {
                                if store.settings.automaticallyChecksForUpdates {
                                    store.requestUpdateNotificationPermission()
                                }
                            }

                        if !store.updateReleaseNotes.isEmpty {
                            AppSectionLabel(title: "Release Notes", topPadding: 2)
                            ScrollView {
                                Text(store.updateReleaseNotes)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 180)
                        }
                    }

                    AppSectionView(title: "Helper", description: "macOS does not provide a public pre-backup hook. The helper runs a low-frequency readiness pass; Scan + Start Backup gives exact ordering for backups started here.") {
                        HStack(spacing: 10) {
                            Label(
                                helperStatusLabel,
                                systemImage: helperStatusIcon
                            )
                            .foregroundStyle(helperStatusColor)

                            Spacer()

                            Button {
                                store.refreshHelperStatus()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh helper status")
                        }

                        if let helperScanSummary = store.helperScanSummary {
                            Label(helperScanSummary, systemImage: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Helper scan: no runs yet", systemImage: "clock.badge.questionmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let helperRuntimeSummary = store.helperRuntimeSummary {
                            Label(helperRuntimeSummary, systemImage: store.isHelperRunning ? "gearshape.arrow.triangle.2.circlepath" : "info.circle")
                                .font(.caption)
                                .foregroundStyle(store.isHelperRunning ? .blue : .secondary)
                        }

                        if store.isHelperInstalled && !store.isHelperLoaded {
                            Button {
                                openBackgroundItemsSettings()
                            } label: {
                                Label("Open Background Items Settings", systemImage: "gear")
                                    .foregroundStyle(.primary)
                            }
                        }

                        Stepper(value: $store.settings.scanIntervalMinutes, in: 60...10_080, step: 60) {
                            Text(helperIntervalLabel)
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        if store.isHelperInstalled {
                            Button(role: .destructive) {
                                store.uninstallBackgroundAgent()
                            } label: {
                                Label("Remove Helper", systemImage: "xmark.circle")
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            Button {
                                store.installBackgroundAgent()
                            } label: {
                                Label("Install Helper", systemImage: "bolt.badge.clock")
                                    .foregroundStyle(.primary)
                            }
                        }

                        #if DEBUG
                        Divider()

                        HStack(spacing: 8) {
                            Button {
                                store.runDebugHelperScanNow()
                            } label: {
                                Label("Run Helper Scan Now", systemImage: "play.circle")
                                    .foregroundStyle(.primary)
                            }
                            .disabled(!store.canEdit)

                            Button(role: .destructive) {
                                store.clearDebugHelperScanInfo()
                            } label: {
                                Label("Clear Helper Info", systemImage: "trash")
                                    .foregroundStyle(.primary)
                            }
                            .disabled(!store.canEdit)
                        }
                        #endif
                    }
                }
                .scenePadding()
            }
            .listStyle(.plain)
        }
        .disabled(!store.canEdit)
        .onChange(of: store.settings) {
            if store.canEdit { scheduleAutosave() }
        }
        .onDisappear {
            autosaveTask?.cancel()
            store.save()
        }
        .onAppear {
            store.refreshHelperStatus()
            store.refreshLoginItemStatus()
        }
    }

    private func openFullDiskAccessSettings() {
        FullDiskAccessSupport.openSystemSettings()
        store.statusMessage = "Opened Full Disk Access settings"
    }

    private func openBackgroundItemsSettings() {
        BackgroundItemsSupport.openSystemSettings()
        store.statusMessage = "Opened Background Items settings"
    }

    private var fullDiskAccessStatusIcon: String {
        switch store.fullDiskAccessStatus {
        case .granted:
            return "lock.open.fill"
        case .missing:
            return "lock.fill"
        case .sandboxed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var helperStatusLabel: String {
        if !store.isHelperInstalled { return "Helper not installed" }
        if !store.isHelperLoaded { return "Helper disabled" }
        if store.isHelperRunning { return "Helper running" }
        return "Helper installed"
    }

    private var helperStatusIcon: String {
        if !store.isHelperInstalled { return "xmark.circle" }
        if !store.isHelperLoaded { return "exclamationmark.circle.fill" }
        if store.isHelperRunning { return "gearshape.arrow.triangle.2.circlepath" }
        return "checkmark.circle.fill"
    }

    private var helperStatusColor: Color {
        if !store.isHelperInstalled { return .secondary }
        if !store.isHelperLoaded { return .orange }
        if store.isHelperRunning { return .blue }
        return .green
    }

    private var fullDiskAccessStatusColor: Color {
        switch store.fullDiskAccessStatus {
        case .granted:
            return .green
        case .missing:
            return .orange
        case .sandboxed:
            return .secondary
        }
    }

    private var updateStatusColor: Color {
        switch store.updateStatus {
        case .failed:
            return .red
        case .readyToInstall, .downloading, .available:
            return .blue
        case .checking, .installing:
            return .secondary
        case .idle, .upToDate:
            return .secondary
        }
    }

    private func pickScanRoots() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK else { return }
        store.addScanRoots(panel.urls)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            store.save()
        }
    }

    private var helperIntervalLabel: String {
        let minutes = store.settings.scanIntervalMinutes
        if minutes == AppSettings.dailyScanIntervalMinutes {
            return "Run helper daily"
        }
        if minutes < AppSettings.dailyScanIntervalMinutes {
            return "Run helper every \(minutes / 60) hour\(minutes == 60 ? "" : "s")"
        }
        let days = minutes / AppSettings.dailyScanIntervalMinutes
        return "Run helper every \(days) day\(days == 1 ? "" : "s")"
    }
}
