import SwiftUI

struct SettingsAppSection: View {
    @Environment(AppStateStore.self) private var store
    @State private var permissionsStatusMessage: String?
    @State private var helperActionMessage: String?

    var body: some View {
        AppSectionView(
            title: "App",
            description: "TimeMachine++ needs Full Disk Access to manage exclusions for Time Machine backups. If you recently granted access, recheck the status."
        ) {
            launchAtLoginToggle()
            fullDiskAccessRow()
            helperStatusRow()
            permissionsMessage()
        }
    }

    // MARK: - View Components

    private func launchAtLoginToggle() -> some View {
        Toggle(isOn: Binding(
            get: { store.isLoginItemEnabled },
            set: { store.setLaunchAtLogin($0) }
        )) {
            Label("Open TimeMachine++ when logging in", systemImage: "arrow.trianglehead.2.counterclockwise")
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toggleStyle(.switch)
    }

    private func fullDiskAccessRow() -> some View {
        HStack(spacing: 10) {
            Label(store.fullDiskAccessStatus.label, systemImage: fullDiskAccessStatusIcon)
                .foregroundStyle(fullDiskAccessStatusColor)

            Spacer()

            Button {
                store.refreshFullDiskAccessStatus()
                permissionsStatusMessage = "Full Disk Access status refreshed"
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Recheck Full Disk Access status")

            Button {
                openFullDiskAccessSettings()
            } label: {
                AppActionLabel(title: "Open Settings", systemImage: "gear")
            }
        }
    }

    private func helperStatusRow() -> some View {
        HStack(spacing: 10) {
            Label(helperStatusLabel, systemImage: helperStatusIcon)
                .foregroundStyle(helperStatusColor)

            Spacer()

            Button {
                store.refreshHelperStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh helper status")

            helperActionButton()
        }
    }

    @ViewBuilder
    private func helperActionButton() -> some View {
        if store.isHelperInstalled && !store.isHelperLoaded {
            Button {
                openBackgroundItemsSettings()
            } label: {
                Label("Open Background Items Settings", systemImage: "gear")
                    .foregroundStyle(.primary)
            }
        } else if store.isHelperInstalled {
            Button(role: .destructive) {
                store.uninstallBackgroundAgent()
                helperActionMessage = "Helper removal requested"
            } label: {
                Label("Remove Helper", systemImage: "xmark.circle")
                    .foregroundStyle(.primary)
            }
        } else {
            Button {
                store.installBackgroundAgent()
                helperActionMessage = "Helper installation requested"
            } label: {
                Label("Install Helper", systemImage: "bolt.badge.clock")
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func permissionsMessage() -> some View {
        if let permissionsStatusMessage {
            Label(permissionsStatusMessage, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension SettingsAppSection {
    func openFullDiskAccessSettings() {
        FullDiskAccessSupport.openSystemSettings()
        permissionsStatusMessage = "Opened Full Disk Access settings"
    }

    func openBackgroundItemsSettings() {
        BackgroundItemsSupport.openSystemSettings()
        helperActionMessage = "Opened Background Items settings"
    }

    var fullDiskAccessStatusIcon: String {
        switch store.fullDiskAccessStatus {
        case .granted:
            return "lock.open.fill"
        case .missing:
            return "lock.fill"
        case .sandboxed:
            return "exclamationmark.triangle.fill"
        }
    }

    var fullDiskAccessStatusColor: Color {
        switch store.fullDiskAccessStatus {
        case .granted:
            return .green
        case .missing:
            return .orange
        case .sandboxed:
            return .secondary
        }
    }

    var helperStatusLabel: String {
        if !store.isHelperInstalled { return "Helper not installed" }
        if !store.isHelperLoaded { return "Helper disabled" }
        if store.isHelperRunning { return "Helper running" }
        return "Helper installed"
    }

    var helperStatusIcon: String {
        if !store.isHelperInstalled { return "xmark.circle" }
        if !store.isHelperLoaded { return "exclamationmark.circle.fill" }
        if store.isHelperRunning { return "gearshape.arrow.triangle.2.circlepath" }
        return "checkmark.circle.fill"
    }

    var helperStatusColor: Color {
        if !store.isHelperInstalled { return .secondary }
        if !store.isHelperLoaded { return .orange }
        if store.isHelperRunning { return .blue }
        return .green
    }
}
