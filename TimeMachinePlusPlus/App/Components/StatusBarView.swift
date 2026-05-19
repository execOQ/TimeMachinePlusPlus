import SwiftUI

struct StatusBarView: View {
    @Environment(AppStateStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            if store.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Text(store.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let operationTitle = store.operationTitle {
                Text("· \(operationTitle)")
                    .foregroundStyle(.tertiary)
            }

            if let operationDetail = store.operationDetail {
                Text("· \(operationDetail)")
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if store.isWorking, store.canCancelCurrentOperation {
                Button("Cancel") {
                    store.cancelOperation()
                }
                .controlSize(.small)
            }

            if let lastScanDate = store.lastScanDate {
                Text("Last scan \(Formatters.relativeDate.localizedString(for: lastScanDate, relativeTo: Date()))")
                    .foregroundStyle(.tertiary)
            }

            if let helperScanSummary = store.helperScanSummary {
                Text("· \(helperScanSummary)")
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
