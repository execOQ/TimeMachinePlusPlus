import SwiftUI

struct ScanResultsView: View {
    @ObservedObject var store: AppStateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
