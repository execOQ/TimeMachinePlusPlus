import AppKit
import SwiftUI

// MARK: - Exclusions (combined tabbed entry point)

enum ExclusionTab: String, CaseIterable, Identifiable {
    case rules = "Rules"
    case results = "Results"
    var id: String { rawValue }
}

struct ExclusionsView: View {
    @ObservedObject var store: AppStateStore
    @State private var tab: ExclusionTab = .results

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Exclusions",
                subtitle: tab.subtitle
            ) {
                Picker("Tab", selection: $tab) {
                    ForEach(ExclusionTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                tabActions
            }

            switch tab {
            case .rules:
                RulesView(store: store, showsHeader: false)
            case .results:
                ScanResultsView(store: store, showsHeader: false)
            }
        }
    }

    @ViewBuilder
    private var tabActions: some View {
        switch tab {
        case .rules:
            Button {
                store.addRule()
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .disabled(!store.canEdit)

            Button {
                pickSpecificPaths()
            } label: {
                Label("Add Specific", systemImage: "folder.badge.plus")
            }
            .disabled(!store.canEdit)

        case .results:
            Button {
                store.startScanNow()
            } label: {
                Label("Scan", systemImage: "arrow.clockwise")
            }
            .disabled(store.isWorking)

            Button {
                store.startApplySelectedMatches()
            } label: {
                Label("Apply Selected", systemImage: "checkmark.circle")
            }
            .disabled(store.isWorking)
        }
    }

    private func pickSpecificPaths() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        store.addSpecificPaths(panel.urls)
        store.startScanNow()
        tab = .results
    }
}

private extension ExclusionTab {
    var subtitle: String {
        switch self {
        case .rules: return "Add specific paths or define git-like patterns and regex to match folders automatically."
        case .results: return "Preview exactly what TimeMachine++ will ask Time Machine to exclude."
        }
    }
}

// MARK: - Scan Results

struct ScanResultsView: View {
    @ObservedObject var store: AppStateStore
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HeaderView(
                    title: "Scan Results",
                    subtitle: "Preview exactly what TimeMachine++ will ask Time Machine to exclude."
                ) {
                    Button {
                        store.startScanNow()
                    } label: {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isWorking)

                    Button {
                        store.startApplySelectedMatches()
                    } label: {
                        Label("Apply Selected", systemImage: "checkmark.circle")
                    }
                    .disabled(store.isWorking)
                }
            }

            if store.matches.isEmpty {
                EmptyStateView()
            } else {
                List {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            Text("")
                            Text("Path")
                            Text("Source")
                            Text("Status")
                            Text("Size")
                            Text("Action")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Divider()
                            .gridCellColumns(6)

                        ForEach(store.matches) { match in
                            GridRow {
                                Toggle("", isOn: Binding(
                                    get: { match.isSelected },
                                    set: { store.setMatchSelected(match, isSelected: $0) }
                                ))
                                .labelsHidden()
                                .disabled(match.isExcluded || !store.canEdit)

                                Label {
                                    Text(match.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } icon: {
                                    Image(systemName: match.isDirectory ? "folder" : "doc")
                                }
                                .font(.system(.body, design: .monospaced))

                                Text(match.source.label)
                                    .lineLimit(1)

                                StatusPill(isExcluded: match.isExcluded)

                                Text(Formatters.fileSize(match.sizeBytes))
                                    .foregroundStyle(.secondary)

                                Text(match.plannedAction)
                                    .foregroundStyle(match.isExcluded ? .secondary : .primary)
                            }

                            Divider()
                                .gridCellColumns(6)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct StatusPill: View {
    var isExcluded: Bool

    var body: some View {
        Label(isExcluded ? "Excluded" : "Included", systemImage: isExcluded ? "checkmark.circle.fill" : "circle")
            .font(.caption)
            .foregroundStyle(isExcluded ? .green : .secondary)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "No Scan Results",
            systemImage: "magnifyingglass",
            description: Text("Run a scan after adding rules, manual exclusions, or scan roots.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
