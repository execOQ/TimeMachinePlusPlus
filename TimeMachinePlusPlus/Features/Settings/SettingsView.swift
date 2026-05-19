import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStateStore

    var body: some View {
        PageView(title: "Settings") {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionView("Scan Roots", description: "Pattern rules search these roots. Maximum depth limits how far TimeMachine++ walks below each root so previews and helper scans stay predictable.") {
                        ForEach(store.settings.scanRoots, id: \.self) { root in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                
                                Text(root)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
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
                        }
                        
                        Stepper(value: $store.settings.maxDepth, in: 1...24) {
                            Text("Maximum scan depth: \(store.settings.maxDepth)")
                        }
                        
                        Stepper(value: $store.settings.previewResultLimit, in: 5...200, step: 5) {
                            Text("Quick results limit: \(store.settings.previewResultLimit)")
                        }
                    }
                    
                    sectionView("Permissions", description: "TimeMachine++ needs Full Disk Access to manage exclusions for Time Machine backups. If you recently granted access, click the button below to refresh the status.") {
                        Button {
                            store.refreshFullDiskAccessStatus()
                            openFullDiskAccessSettings()
                        } label: {
                            Label(
                                store.fullDiskAccessStatus.isGranted ? "Full Disk Access" : "Full Disk Access",
                                systemImage: store.fullDiskAccessStatus.isGranted ? "lock.open" : "lock"
                            )
                        }
                        .help(store.fullDiskAccessStatus.label)
                    }
                    
                    sectionView("Interface", description: "When this is off, the toolbar Start button only scans and applies exclusions. Backups can still be started manually from Time Machine controls.") {
                        Toggle("Start backup after scanning and applying exclusions", isOn: $store.settings.startButtonStartsBackup)
                    }
                    
                    sectionView("Helper", description: "macOS does not provide a public pre-backup hook. The helper runs a low-frequency readiness pass; Scan + Start Backup gives exact ordering for backups started here.") {
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
                        
                        if store.isHelperInstalled {
                            Button(role: .destructive) {
                                store.uninstallBackgroundAgent()
                            } label: {
                                Label("Remove Helper", systemImage: "xmark.circle")
                            }
                        } else {
                            Button {
                                store.installBackgroundAgent()
                            } label: {
                                Label("Install Helper", systemImage: "bolt.badge.clock")
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .disabled(!store.canEdit)
        .onChange(of: store.settings) {
            if store.canEdit { store.save() }
        }
        .onAppear { store.refreshHelperStatus() }
    }
    
    private func openFullDiskAccessSettings() {
        FullDiskAccessSupport.openSystemSettings()
        store.statusMessage = "Opened Full Disk Access settings"
    }

    @ViewBuilder
    private func sectionView<Content: View>(_ title: LocalizedStringKey, description: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupBox(title) {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(8)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
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
