import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderView(
                    title: "Settings",
                    subtitle: "Scanning stays local. Time Machine changes are applied through /usr/bin/tmutil."
                ) {
                    EmptyView()
                }

                GroupBox("Advanced Scanning") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pattern rules search these roots. Maximum depth limits how far TimeMachine++ walks below each root so previews and helper scans stay predictable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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
                                .disabled(!store.canEdit)
                            }
                        }

                        Button {
                            pickScanRoots()
                        } label: {
                            Label("Add Scan Root", systemImage: "plus")
                        }
                        .disabled(!store.canEdit)

                        Stepper(value: $store.settings.maxDepth, in: 1...24) {
                            Text("Maximum scan depth: \(store.settings.maxDepth)")
                        }
                        .disabled(!store.canEdit)

                        Stepper(value: $store.settings.previewResultLimit, in: 5...200, step: 5) {
                            Text("Quick results limit: \(store.settings.previewResultLimit)")
                        }
                        .disabled(!store.canEdit)
                    }
                    .padding(8)
                }

                GroupBox("Background Readiness") {
                    VStack(alignment: .leading, spacing: 14) {
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
                            .disabled(!store.canEdit)

                        Stepper(value: $store.settings.scanIntervalMinutes, in: 60...10_080, step: 60) {
                            Text(helperIntervalLabel)
                        }
                        .disabled(!store.canEdit)

                        if store.isHelperInstalled {
                            Button(role: .destructive) {
                                store.uninstallBackgroundAgent()
                            } label: {
                                Label("Remove Helper", systemImage: "xmark.circle")
                            }
                            .disabled(!store.canEdit)
                        } else {
                            Button {
                                store.installBackgroundAgent()
                            } label: {
                                Label("Install Helper", systemImage: "bolt.badge.clock")
                            }
                            .disabled(!store.canEdit)
                        }

                        Text("macOS does not provide a public pre-backup hook. The helper runs a low-frequency readiness pass; Scan + Start Backup gives exact ordering for backups started here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
        .onChange(of: store.settings) { _, _ in
            if store.canEdit {
                store.save()
            }
        }
        .onAppear {
            store.refreshHelperStatus()
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
