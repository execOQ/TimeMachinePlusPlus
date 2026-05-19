import SwiftUI

struct ExclusionsView: View {
    @ObservedObject var store: AppStateStore

    var body: some View {
        RulesView(store: store)
    }
}

struct AppManagedExclusionsView: View {
    @ObservedObject var store: AppStateStore
    @State private var selection = Set<UUID>()

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
                        Text("Exclusions are applied as file attributes. Time Machine respects them, but they won't appear in System Settings")
                            .boxContainer()

                        ForEach(store.appliedExclusions) { exclusion in
                            AppManagedExclusionRow(exclusion: exclusion, store: store)
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
            let validIDs = Set(store.appliedExclusions.map(\.id))
            selection = selection.intersection(validIDs)
        }
    }
}

private struct AppManagedExclusionRow: View {
    var exclusion: AppliedExclusion
    @ObservedObject var store: AppStateStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exclusion.path)
                    .font(.system(.body, design: .monospaced))
                    .truncationMode(.middle)

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

extension View {
    func boxContainer(color: Color = .secondary, cornerRadius: CGFloat = 6, padding: CGFloat = 6) -> some View {
        self.padding(.horizontal, padding + 2)
            .padding(.vertical, padding)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color.opacity(0.15))
            )
    }
}
