import SwiftUI

struct DestinationSidebarRow: View {
    var destination: TimeMachineDestination
    var isSelected = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.kind == "Network" ? "network" : "externaldrive")
                .foregroundStyle(isSelected ? Color.primary : Color.accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name)
                    .lineLimit(1)
                Text(destination.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
