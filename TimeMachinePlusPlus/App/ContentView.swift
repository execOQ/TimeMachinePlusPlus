import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStateStore

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(store: store)
                    .disabled(store.isWorking)
            } detail: {
                Group {
                    switch store.selectedSelection ?? .section(.exclusions) {
                    case .destination(let id):
                        TimeMachineCommandsView(
                            store: store,
                            initialSelection: .destination(id),
                            showsInternalSidebar: false
                        )
                        .id("destination-\(id)")
                    case .section(let section):
                        switch section {
                    case .exclusions:
                        ExclusionsView(store: store)
                    case .commands:
                            TimeMachineCommandsView(store: store, showsInternalSidebar: false)
                                .id("time-machine-overview")
                    case .settings:
                        SettingsView(store: store)
                        }
                    }
                }
                .disabled(store.isWorking)
                .safeAreaInset(edge: .bottom) {
                    StatusBarView(store: store)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        Button {
                            pickAndSetDestination(shouldAppend: true)
                        } label: {
                            Label("Add Destination", systemImage: "plus")
                        }

                        Button {
                            pickAndSetDestination(shouldAppend: false)
                        } label: {
                            Label("Replace Destinations", systemImage: "externaldrive")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .help("Add or replace Time Machine destinations")
                    .disabled(store.isWorking)
                }

                toolbarOperationItems
            }

            if store.isWorking {
                BlockingOperationOverlay(
                    title: store.operationTitle ?? "Working",
                    canCancel: store.canCancelCurrentOperation,
                    onCancel: { store.cancelOperation() }
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarOperationItems: some ToolbarContent {
        ToolbarItemGroup {
            if store.isWorking {
                if store.canCancelCurrentOperation {
                    Button(role: .cancel) {
                        store.cancelOperation()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .help("Cancel the current operation")
                }
            } else {
                Button {
                    store.startScanNow()
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .help("Scan now")

                Button {
                    store.startApplySelectedMatches()
                } label: {
                    Label("Exclude", systemImage: "minus.circle")
                }
                .help("Apply selected exclusions")

                if store.backupStatus.isRunning {
                    Button(role: .destructive) {
                        Task { await stopRunningBackup() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Stop the running Time Machine backup")
                } else {
                    Button {
                        store.startScanAndBackup()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .help("Scan, apply exclusions, then start Time Machine backup")
                }
            }
        }
    }

    private func pickAndSetDestination(shouldAppend: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = shouldAppend ? "Add" : "Replace"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let client = LiveTimeMachineClient()
            var arguments = ["setdestination"]
            if shouldAppend {
                arguments.append("-a")
            }
            arguments.append(url.path)
            let result = try? client.run(arguments: arguments, asAdministrator: true)
            await MainActor.run {
                store.statusMessage = result?.isSuccess == true ? "Destination updated" : "Could not update destination"
            }
            await store.refreshTimeMachineState()
        }
    }

    private func stopRunningBackup() async {
        let client = LiveTimeMachineClient()
        _ = try? client.stopBackup()
        await store.refreshTimeMachineState()
        store.statusMessage = "Stop backup requested"
    }
}

struct SidebarView: View {
    @ObservedObject var store: AppStateStore
    @State private var localSelection: AppSidebarSelection?

    private var selectionBinding: Binding<AppSidebarSelection?> {
        Binding(
            get: {
                localSelection ?? store.selectedSelection
            },
            set: { newSelection in
                localSelection = newSelection
                DispatchQueue.main.async {
                    store.selectedSelection = newSelection
                }
            }
        )
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section("Time Machine") {
                Label("Overview", systemImage: "clock.arrow.circlepath")
                    .tag(AppSidebarSelection.section(.commands))

                if store.timeMachineDestinations.isEmpty {
                    Text("No destinations found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.timeMachineDestinations) { destination in
                        DestinationMainSidebarRow(destination: destination)
                            .tag(AppSidebarSelection.destination(destination.id))
                    }
                }
            }

            Section("Exclusions") {
                Label(SidebarSection.exclusions.rawValue, systemImage: SidebarSection.exclusions.systemImage)
                    .tag(AppSidebarSelection.section(.exclusions))
            }

            Section("App") {
                Label(SidebarSection.settings.rawValue, systemImage: SidebarSection.settings.systemImage)
                    .tag(AppSidebarSelection.section(.settings))
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("TimeMachine++")
        .onAppear {
            localSelection = store.selectedSelection
        }
        .onChange(of: store.selectedSelection) { _, newSelection in
            if localSelection != newSelection {
                localSelection = newSelection
            }
        }
    }
}

private struct DestinationMainSidebarRow: View {
    var destination: TimeMachineDestination

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.kind == "Network" ? "network" : "externaldrive")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name)
                    .lineLimit(1)
                Text(destination.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct StatusBarView: View {
    @ObservedObject var store: AppStateStore

    var body: some View {
        HStack(spacing: 10) {
            if store.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Text(store.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let operationTitle = store.operationTitle {
                Text("· \(operationTitle)")
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if store.isWorking, store.canCancelCurrentOperation {
                Button("Cancel") {
                    store.cancelOperation()
                }
                .controlSize(.small)
            }

            if let lastScanDate = store.lastScanDate {
                Text("Last scan \(Formatters.relativeDate.localizedString(for: lastScanDate, relativeTo: Date()))")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct BlockingOperationOverlay: View {
    var title: String
    var canCancel: Bool
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(title)
                    .font(.headline)
                if canCancel {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .padding(.top, 4)
                } else {
                    Text("This window will unlock when the operation finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 18)
        }
    }
}
