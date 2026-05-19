import SwiftUI

struct SidebarView: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedSelection) {
            Label("Overview", systemImage: "clock.arrow.circlepath")
                .tag(AppSidebarSelection.section(.commands))

            Label(SidebarSection.settings.rawValue, systemImage: SidebarSection.settings.systemImage)
                .tag(AppSidebarSelection.section(.settings))

            Section("Destinations") {
                if store.timeMachineDestinations.isEmpty {
                    Text("No destinations found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.timeMachineDestinations) { destination in
                        DestinationMainSidebarRow(
                            destination: destination,
                            isSelected: store.selectedSelection == .destination(destination.id)
                        )
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
        }
        .listStyle(.sidebar)
    }
}

private struct DestinationMainSidebarRow: View {
    var destination: TimeMachineDestination
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.kind == "Network" ? "network" : "externaldrive")
                .foregroundStyle(isSelected ? Color.primary : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name)

                Text(destination.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}
