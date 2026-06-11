import SwiftUI

struct AppManagedExclusionRow: View {
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
                FinderPathActions.copy(path: exclusion.path)
            } label: {
                Label("Copy Path", systemImage: "document.on.document.fill")
            }

            Button {
                FinderPathActions.reveal(path: exclusion.path)
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
