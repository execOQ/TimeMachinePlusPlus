import AppKit
import SwiftUI

private struct KnownExclusionRowItem: Identifiable {
    let path: String
    var id: String { path }
}

extension TimeMachineCommandSurface {
    var knownExclusionsBox: some View {
        AppSectionView(title: "Known Exclusions") {
            VStack(alignment: .leading, spacing: 10) {
                let paths = knownExclusionPaths

                if paths.isEmpty {
                    Text("No known exclusions yet. Add specific rules or apply exclusions through backup readiness.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(paths.map(KnownExclusionRowItem.init)) { item in
                        let path = item.path
                        HStack(spacing: 10) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            AppPathText(path: path)
                            Spacer()
                            Button(role: .destructive) {
                                run(arguments: ["removeexclusion", path], context: .exclusions, title: "Remove Exclusion", status: "Removing exclusion...")
                            } label: {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.borderless)
                            .help("Allow this path to be backed up")
                        }
                        Divider()
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        let paths = knownExclusionPaths
                        run(arguments: ["isexcluded"] + paths, context: .exclusions, title: "Refresh Exclusion Status", status: "Refreshing exclusion status...")
                    } label: {
                        primaryButtonLabel("Refresh Status", systemImage: "arrow.clockwise")
                    }
                    .disabled(paths.isEmpty)
                }
            }
        }
    }

    var knownExclusionPaths: [String] {
        let applied = store.appliedExclusions.map(\.path)
        let specific = store.rules.filter { $0.kind == .specific && $0.isEnabled }.map(\.pattern)
        let scanned = store.matches.filter(\.isExcluded).map(\.path)
        return Array(Set(applied + specific + scanned))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }


}
