import SwiftUI

struct AppManagedExclusionsView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()
    @State private var sourceFilter = AppManagedExclusionSourceFilter.all
    @State private var sortOrder = AppManagedExclusionSortOrder.newestFirst
    @State private var selectionPruneTask: Task<Void, Never>?

    private var visibleExclusions: [AppliedExclusion] {
        store.appliedExclusions
            .filter { sourceFilter.includes($0) }
            .sorted(using: sortOrder)
    }

    private var selectedVisibleExclusions: [AppliedExclusion] {
        visibleExclusions.filter { selection.contains($0.id) }
    }

    private var sourceFilters: [AppManagedExclusionSourceFilter] {
        [.all] + Set(store.appliedExclusions.map(\.sourceDescription))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map(AppManagedExclusionSourceFilter.source)
    }

    var body: some View {
        PageView(title: "App-Managed Exclusions", subtitle: "Paths that TimeMachine++ has already marked for Time Machine to ignore") {
            VStack(alignment: .leading, spacing: 0) {
                if store.appliedExclusions.isEmpty {
                    emptyState()
                } else {
                    controlsBar()
                    exclusionsList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 720, maxHeight: 520)
        .toolbar {
            toolbarItems()
        }
        .onChange(of: store.appliedExclusions, scheduleSelectionPrune)
        .onChange(of: sourceFilter, scheduleSelectionPrune)
        .onDisappear(perform: onDisappear)
    }

    // MARK: - View Components

    private func emptyState() -> some View {
        ContentUnavailableView(
            "No App-Managed Exclusions",
            systemImage: "checklist",
            description: Text("Applied exclusions will appear here after TimeMachine++ adds them.")
        )
    }

    private func controlsBar() -> some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $sourceFilter) {
                ForEach(sourceFilters) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .frame(width: 240)

            Picker("Sort", selection: $sortOrder) {
                ForEach(AppManagedExclusionSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .frame(width: 190)

            Spacer()

            Text("\(visibleExclusions.count) of \(store.appliedExclusions.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func exclusionsList() -> some View {
        List(selection: $selection) {
            ForEach(visibleExclusions) { exclusion in
                AppManagedExclusionRow(exclusion: exclusion)
                    .tag(exclusion.id)
            }
        }
        .listStyle(.inset)
    }

    @ToolbarContentBuilder
    private func toolbarItems() -> some ToolbarContent {
        ToolbarItem {
            Button("Close") {
                dismiss()
            }
            .help("Close App-Managed Exclusions")
        }

        ToolbarItem {
            Button(role: .destructive, action: removeSelectedExclusions) {
                Label("Remove Selected", systemImage: "trash")
            }
            .disabled(!store.canEdit || selectedVisibleExclusions.isEmpty)
        }
    }
}

private extension AppManagedExclusionsView {
    func removeSelectedExclusions() {
        let targets = selectedVisibleExclusions
        selection.removeAll()
        Task { await store.removeApplied(targets) }
    }

    func scheduleSelectionPrune() {
        selectionPruneTask?.cancel()
        let validIDs = Set(visibleExclusions.map(\.id))
        selectionPruneTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            selection = selection.intersection(validIDs)
        }
    }

    func onDisappear() {
        selectionPruneTask?.cancel()
    }
}
