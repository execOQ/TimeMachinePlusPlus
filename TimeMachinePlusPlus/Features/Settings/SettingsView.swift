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

                    AppSectionView(title: "Helper", description: "macOS does not provide a public pre-backup hook. The helper runs a low-frequency readiness pass; Scan + Start Backup gives exact ordering for backups started here.") {
                        HStack(spacing: 10) {
                            Label(
                                store.isHelperInstalled ? "Helper installed" : "Helper not installed",
                                systemImage: store.isHelperInstalled ? "checkmark.circle.fill" : "xmark.circle"
                            )
                            .foregroundStyle(store.isHelperInstalled ? .green : .secondary)

                            Spacer()

                            Button {
                                store.refreshHelperStatus()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh helper status")
                        }

                        Toggle("Enable background scanning preference", isOn: $store.settings.backgroundScanningEnabled)

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
        .onAppear { store.refreshHelperStatus() }
    }

    private func openFullDiskAccessSettings() {
        FullDiskAccessSupport.openSystemSettings()
        store.statusMessage = "Opened Full Disk Access settings"
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
