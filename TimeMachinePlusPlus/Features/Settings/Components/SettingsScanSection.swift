import SwiftUI

private struct ScanRootRowItem: Identifiable {
    let path: String
    var id: String { path }
}

struct SettingsScanSection: View {
    @Environment(AppStateStore.self) private var store
    @State private var intervalUnit: SettingsIntervalUnit = .minutes
    @State private var helperActionMessage: String?

    var body: some View {
        @Bindable var store = store

        AppSectionView(
            title: "Scan",
            description: "Pattern rules search these roots. Maximum depth limits how far TimeMachine++ walks below each root. The Check Frequency defines how often in background the app would scan files."
        ) {
            scanRootsList()
            addScanRootButton()
            maxDepthControl(store: store)
            scanIntervalControl()
            helperScanSummary()
            debugHelperControls()
            helperActionStatus()
        }
    }

    // MARK: - View Components

    private func scanRootsList() -> some View {
        ForEach(store.settings.scanRoots.map(ScanRootRowItem.init)) { item in
            let root = item.path
            AppPathRow(path: root) {
                Button(role: .destructive) {
                    store.deleteScanRoot(root)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addScanRootButton() -> some View {
        Button(action: pickScanRoots) {
            Label("Add Scan Root", systemImage: "plus")
                .foregroundStyle(.primary)
        }
    }

    @ContentBuilder
    private func maxDepthControl(@Bindable store: AppStateStore) -> some View {
        HStack {
            Text("Maximum scan depth")

            Spacer()

            Stepper(value: $store.settings.maxDepth, in: 1...24) {
                Text(store.settings.maxDepth.description)
            }
            .fixedSize()
            .controlSize(.small)
        }
    }

    private func scanIntervalControl() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Check Frequency")

            Spacer()

            Stepper(value: intervalValueBinding, in: intervalRange) {
                Text("\(currentIntervalValue)")
                    .monospacedDigit()
                    .font(.body)
            }
            .fixedSize()
            .controlSize(.small)

            Picker("", selection: $intervalUnit) {
                Text("minutes").tag(SettingsIntervalUnit.minutes)
                Text("hours").tag(SettingsIntervalUnit.hours)
                Text("days").tag(SettingsIntervalUnit.days)
            }
            .fixedSize()
            .pickerStyle(.menu)
            .onChange(of: intervalUnit, updateScanIntervalForSelectedUnit)
        }
    }

    private func helperScanSummary() -> some View {
        Label(store.helperScanSummary ?? "Helper scan: no runs yet", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func debugHelperControls() -> some View {
        #if DEBUG
        Divider()

        HStack(spacing: 8) {
            Button {
                store.runDebugHelperScanNow()
                helperActionMessage = "Helper scan started"
            } label: {
                Label("Run Helper Scan Now", systemImage: "play.circle")
                    .foregroundStyle(.primary)
            }
            .disabled(!store.canEdit)

            Button(role: .destructive) {
                store.clearDebugHelperScanInfo()
                helperActionMessage = "Helper info cleared"
            } label: {
                Label("Clear Helper Info", systemImage: "trash")
                    .foregroundStyle(.primary)
            }
            .disabled(!store.canEdit)
        }

        if let helperRuntimeSummary = store.helperRuntimeSummary {
            Label(helperRuntimeSummary, systemImage: store.isHelperRunning ? "gearshape.arrow.triangle.2.circlepath" : "info.circle")
                .font(.caption)
                .foregroundStyle(store.isHelperRunning ? .blue : .secondary)
        }
        #endif
    }

    @ViewBuilder
    private func helperActionStatus() -> some View {
        if let helperActionMessage {
            Label(helperActionMessage, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension SettingsScanSection {
    func pickScanRoots() {
        let urls = PathPicker.pickPaths(canChooseFiles: false, canChooseDirectories: true)
        guard !urls.isEmpty else { return }
        store.addScanRoots(urls)
    }

    var intervalRange: ClosedRange<Int> {
        switch intervalUnit {
        case .minutes:
            return 1...60
        case .hours:
            return 1...24
        case .days:
            return 1...7
        }
    }

    var intervalValueBinding: Binding<Int> {
        Binding(
            get: { currentIntervalValue },
            set: { store.settings.scanIntervalMinutes = minutes(from: $0, unit: intervalUnit) }
        )
    }

    var currentIntervalValue: Int {
        let minutes = store.settings.scanIntervalMinutes
        switch intervalUnit {
        case .minutes:
            return max(1, minutes)
        case .hours:
            return max(1, minutes / 60)
        case .days:
            return max(1, minutes / AppSettings.dailyScanIntervalMinutes)
        }
    }

    func updateScanIntervalForSelectedUnit() {
        let clampedValue = min(max(currentIntervalValue, intervalRange.lowerBound), intervalRange.upperBound)
        store.settings.scanIntervalMinutes = minutes(from: clampedValue, unit: intervalUnit)
    }

    func minutes(from value: Int, unit: SettingsIntervalUnit) -> Int {
        switch unit {
        case .minutes:
            return clampMinutes(value)
        case .hours:
            return clampMinutes(value * 60)
        case .days:
            return clampMinutes(value * AppSettings.dailyScanIntervalMinutes)
        }
    }

    func clampMinutes(_ minutes: Int) -> Int {
        min(max(1, minutes), 10_080)
    }
}
