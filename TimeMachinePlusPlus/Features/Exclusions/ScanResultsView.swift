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
                    ContentUnavailableView(
                        "No App-Managed Exclusions",
                        systemImage: "checklist",
                        description: Text("Applied exclusions will appear here after TimeMachine++ adds them.")
                    )
                } else {
                    controlsBar

                    List(selection: $selection) {
                        ForEach(visibleExclusions) { exclusion in
                            AppManagedExclusionRow(exclusion: exclusion)
                                .tag(exclusion.id)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 720, maxHeight: 520)
        .toolbar {
            ToolbarItem {
                Button("Close") {
                    dismiss()
                }
                .help("Close App-Managed Exclusions")
            }

            ToolbarItem {
                Button(role: .destructive) {
                    let targets = selectedVisibleExclusions
                    selection.removeAll()
                    Task { await store.removeApplied(targets) }
                } label: {
                    Label("Remove Selected", systemImage: "trash")
                }
                .disabled(!store.canEdit || selectedVisibleExclusions.isEmpty)
            }
        }
        .onChange(of: store.appliedExclusions) {
            scheduleSelectionPrune()
        }
        .onChange(of: sourceFilter) {
            scheduleSelectionPrune()
        }
        .onDisappear {
            selectionPruneTask?.cancel()
        }
    }

    private var controlsBar: some View {
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

    private func scheduleSelectionPrune() {
        selectionPruneTask?.cancel()
        let validIDs = Set(visibleExclusions.map(\.id))
        selectionPruneTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            selection = selection.intersection(validIDs)
        }
    }
}

private enum AppManagedExclusionSourceFilter: Hashable, Identifiable {
    case all
    case source(String)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .source(let source):
            return source
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All rules"
        case .source(let source):
            return source
        }
    }

    func includes(_ exclusion: AppliedExclusion) -> Bool {
        switch self {
        case .all:
            return true
        case .source(let source):
            return exclusion.sourceDescription == source
        }
    }
}

private enum AppManagedExclusionSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case rule
    case path

    var id: Self { self }

    var title: String {
        switch self {
        case .newestFirst:
            return "Newest first"
        case .oldestFirst:
            return "Oldest first"
        case .rule:
            return "Rule"
        case .path:
            return "Path"
        }
    }
}

private extension Array where Element == AppliedExclusion {
    func sorted(using order: AppManagedExclusionSortOrder) -> [AppliedExclusion] {
        sorted { lhs, rhs in
            switch order {
            case .newestFirst:
                if lhs.appliedAt != rhs.appliedAt {
                    return lhs.appliedAt > rhs.appliedAt
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            case .oldestFirst:
                if lhs.appliedAt != rhs.appliedAt {
                    return lhs.appliedAt < rhs.appliedAt
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            case .rule:
                let sourceComparison = lhs.sourceDescription.localizedCaseInsensitiveCompare(rhs.sourceDescription)
                if sourceComparison != .orderedSame {
                    return sourceComparison == .orderedAscending
                }
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            case .path:
                return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
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
