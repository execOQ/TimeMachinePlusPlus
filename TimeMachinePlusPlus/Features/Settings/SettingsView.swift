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

                GroupBox("Scan Roots") {
                    VStack(alignment: .leading, spacing: 10) {
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

                        Stepper(value: $store.settings.scanIntervalMinutes, in: 5...240, step: 5) {
                            Text("Scan every \(store.settings.scanIntervalMinutes) minutes")
                        }
                        .disabled(!store.canEdit)

                        Stepper(value: $store.settings.maxDepth, in: 1...24) {
                            Text("Maximum scan depth: \(store.settings.maxDepth)")
                        }
                        .disabled(!store.canEdit)

                        HStack {
                            Button {
                                store.installBackgroundAgent()
                            } label: {
                                Label("Install Helper", systemImage: "bolt.badge.clock")
                            }
                            .disabled(!store.canEdit)

                            Button(role: .destructive) {
                                store.uninstallBackgroundAgent()
                            } label: {
                                Label("Remove Helper", systemImage: "xmark.circle")
                            }
                            .disabled(!store.canEdit)
                        }

                        Text("macOS does not provide a public pre-backup hook. The helper keeps exclusions ready on a timer; Scan + Start Backup gives exact ordering for backups started here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("App-Managed Exclusions") {
                    VStack(alignment: .leading, spacing: 8) {
                        if store.appliedExclusions.isEmpty {
                            Text("No exclusions have been applied by TimeMachine++ yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.appliedExclusions) { exclusion in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(exclusion.path)
                                            .font(.system(.body, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text("From \(exclusion.sourceDescription)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await store.removeApplied(exclusion) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    .disabled(!store.canEdit)
                                }
                                Divider()
                            }
                        }
                        Text("Exclusions are applied as file attributes. Time Machine respects them, but they won't appear in System Settings — that list requires admin access to the system preferences file.")
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
}
