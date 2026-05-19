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
                    switch store.selectedSelection ?? .section(.exclusionRules) {
                    case .destination(let id):
                        TimeMachineCommandsView(
                            store: store,
                            initialSelection: .destination(id),
                            showsInternalSidebar: false
                        )
                        .id("destination-\(id)")
                    case .section(let section):
                        switch section {
                        case .exclusionRules:
                            ExclusionsView(store: store)
                        case .appManagedExclusions:
                            AppManagedExclusionsView(store: store)
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

            if store.isWorking {
                BlockingOperationOverlay(
                    title: store.operationTitle ?? "Working",
                    detail: store.operationDetail,
                    progress: store.operationProgress,
                    canCancel: store.canCancelCurrentOperation,
                    onCancel: { store.cancelOperation() }
                )
            }
        }
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
                Label(SidebarSection.exclusionRules.rawValue, systemImage: SidebarSection.exclusionRules.systemImage)
                    .tag(AppSidebarSelection.section(.exclusionRules))
                Label(SidebarSection.appManagedExclusions.rawValue, systemImage: SidebarSection.appManagedExclusions.systemImage)
                    .tag(AppSidebarSelection.section(.appManagedExclusions))
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

            if let operationDetail = store.operationDetail {
                Text("· \(operationDetail)")
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
        .background(.ultraThinMaterial)
    }
}

private struct BlockingOperationOverlay: View {
    var title: String
    var detail: String?
    var progress: Double?
    var canCancel: Bool
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 250)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                }
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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
