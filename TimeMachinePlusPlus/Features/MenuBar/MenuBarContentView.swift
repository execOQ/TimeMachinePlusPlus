import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: AppStateStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.statusMessage)
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .leading)

            if let lastScanDate = store.lastScanDate {
                Text("Last scan \(Formatters.relativeDate.localizedString(for: lastScanDate, relativeTo: Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label(
                store.isHelperInstalled ? "Helper installed" : "Helper not installed",
                systemImage: store.isHelperInstalled ? "checkmark.circle.fill" : "xmark.circle"
            )
            .font(.caption)
            .foregroundStyle(store.isHelperInstalled ? .green : .secondary)

            Divider()

            Button("Open TimeMachine++") {
                if !WindowFocus.focusMainWindow() {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            if store.isWorking {
                Button("Cancel Current Operation") {
                    store.cancelOperation()
                }
            } else {
                Button("Scan + Start Backup") {
                    store.startScanAndBackup()
                }
            }

            Divider()

            Button("Refresh Helper Status") {
                store.refreshHelperStatus()
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
    }
}
