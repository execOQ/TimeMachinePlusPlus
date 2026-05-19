import SwiftUI

struct ExclusionsView: View {
    var body: some View {
        RulesView()
    }
}

struct AppManagedExclusionsView: View {
    @Environment(AppStateStore.self) private var store
    @State private var selection = Set<UUID>()
    @State private var selectionPruneTask: Task<Void, Never>?

    private var selectedExclusions: [AppliedExclusion] {
        store.appliedExclusions.filter { selection.contains($0.id) }
    }

    var body: some View {
        PageView(title: "App-Managed Exclusions", subtitle: "Paths that TimeMachine++ has already marked for Time Machine to ignore") {
            VStack(alignment: .leading, spacing: 0) {
                if store.appliedExclusions.isEmpty {
                    ContentUnavailableView(
                        "No App-Managed Exclusions",
                        systemImage: "checklist",
                        description: Text("Applied exclusions will appear here after TimeMachine++ adds them.")
                    )
                } else {
                    List(selection: $selection) {
                        ForEach(store.appliedExclusions) { exclusion in
                            AppManagedExclusionRow(exclusion: exclusion)
                                .tag(exclusion.id)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    let targets = selectedExclusions
                    selection.removeAll()
                    Task { await store.removeApplied(targets) }
                } label: {
                    Label("Remove Selected", systemImage: "trash")
                }
                .disabled(!store.canEdit || selection.isEmpty)
            }
        }
        .onChange(of: store.appliedExclusions) {
            scheduleSelectionPrune()
        }
        .onDisappear {
            selectionPruneTask?.cancel()
        }
    }

    private func scheduleSelectionPrune() {
        selectionPruneTask?.cancel()
        let validIDs = Set(store.appliedExclusions.map(\.id))
        selectionPruneTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            selection = selection.intersection(validIDs)
        }
    }
}

private struct AppManagedExclusionRow: View {
    var exclusion: AppliedExclusion
    @Environment(AppStateStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                AppPathText(path: exclusion.path)

                HStack(spacing: 2) {
                    Text(exclusion.appliedAt, style: .date)
                    Text("•")
                    Text("From \(exclusion.sourceDescription)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(exclusion.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "document.on.document.fill")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: exclusion.path)])
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }

            Divider()

            Button {
                Task { await store.removeApplied([exclusion]) }
            } label: {
                Label("Remove Exclusion", systemImage: "trash")
            }
        }
    }
}
