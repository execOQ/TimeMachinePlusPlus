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
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                title: "App-Managed Exclusions",
                subtitle: "Paths that TimeMachine++ has already marked for Time Machine to ignore."
            ) {
                Button(role: .destructive) {
                    let targets = selectedExclusions
                    selection.removeAll()
                    Task { await store.removeApplied(targets) }
                } label: {
                    Label("Remove Selected", systemImage: "trash")
                }
                .disabled(!store.canEdit || selection.isEmpty)
            }

            if store.appliedExclusions.isEmpty {
                ContentUnavailableView(
                    "No App-Managed Exclusions",
                    systemImage: "checklist",
                    description: Text("Applied exclusions will appear here after TimeMachine++ adds them.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(store.appliedExclusions) { exclusion in
                        AppManagedExclusionRow(exclusion: exclusion)
                            .tag(exclusion.id)
                    }
                }
                .listStyle(.inset)
            }

            Text("Exclusions are applied as file attributes. Time Machine respects them, but they won't appear in System Settings because that list requires admin access to the system preferences file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .bottom], 16)
        }
        .onChange(of: store.appliedExclusions) { _, current in
            let validIDs = Set(current.map(\.id))
            selection = selection.intersection(validIDs)
        }
    }
}

private struct AppManagedExclusionRow: View {
    var exclusion: AppliedExclusion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)

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

            Text(exclusion.appliedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}
