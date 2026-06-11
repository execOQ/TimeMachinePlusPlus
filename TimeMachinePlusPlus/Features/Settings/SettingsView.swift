import AppKit
import MarkdownUI
import SwiftUI

private struct ScanRootRowItem: Identifiable {
    let path: String
    var id: String { path }
}

struct SettingsView: View {
    @Environment(AppStateStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var autosaveTask: Task<Void, Never>?
    @State private var permissionsStatusMessage: String?
    @State private var appStatusMessage: String?
    @State private var helperActionMessage: String?
    @State private var intervalUnit: IntervalUnit = .minutes

    private enum IntervalUnit {
        case minutes, hours, days
    }

    private var intervalRange: ClosedRange<Int> {
        switch intervalUnit {
        case .minutes:
            return 1...60
        case .hours:
            return 1...24
        case .days:
            return 1...7
        }
    }

    private var intervalStep: Int {
        1
    }

    private func clampMinutes(_ minutes: Int) -> Int {
        min(max(1, minutes), 10_080)
    }

    var body: some View {
        @Bindable var store = store

        PageView(title: "Settings") {
            List {
                VStack(alignment: .leading, spacing: 22) {
                    AppSectionView(title: "App", description: "TimeMachine++ needs Full Disk Access to manage exclusions for Time Machine backups. If you recently granted access, recheck the status.") {
                        Toggle(isOn: Binding(
                            get: { store.isLoginItemEnabled },
                            set: { isEnabled in
                                store.setLaunchAtLogin(isEnabled)
                                appStatusMessage = isEnabled
                                    ? "TimeMachine++ will open at login"
                                    : "TimeMachine++ will not open at login"
                            }
                        )) {
                            Label("Open TimeMachine++ when logging in", systemImage: "arrow.trianglehead.2.counterclockwise")
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .toggleStyle(.switch)

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

                        HStack(spacing: 10) {
                            Label(
                                helperStatusLabel,
                                systemImage: helperStatusIcon
                            )
                            .foregroundStyle(helperStatusColor)

                            Spacer()

                            Button {
                                store.refreshHelperStatus()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh helper status")

                            if store.isHelperInstalled {
                                Button(role: .destructive) {
                                    store.uninstallBackgroundAgent()
                                    helperActionMessage = "Helper removal requested"
                                } label: {
                                    Label("Remove Helper", systemImage: "xmark.circle")
                                        .foregroundStyle(.primary)
                                }
                            } else if store.isHelperInstalled && !store.isHelperLoaded {
                                Button {
                                    openBackgroundItemsSettings()
                                } label: {
                                    Label("Open Background Items Settings", systemImage: "gear")
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

                        if let permissionsStatusMessage {
                            Label(permissionsStatusMessage, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    AppSectionView(title: "Scan", description: "Pattern rules search these roots. Maximum depth limits how far TimeMachine++ walks below each root. The Check Frequency defines how often in background the app would scan files.") {
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

                        Button(action: pickScanRoots) {
                            Label("Add Scan Root", systemImage: "plus")
                                .foregroundStyle(.primary)
                        }

                        HStack {
                            Text("Maximum scan depth")

                            Spacer()

                            Stepper(value: $store.settings.maxDepth, in: 1...24) {
                                Text(store.settings.maxDepth.description)
                            }
                            .fixedSize()
                            .controlSize(.small)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("Check Frequency")
                            Spacer()
                            // Numeric value bound via unit conversion
                            Stepper(value: Binding<Int>(
                                get: {
                                    let minutes = store.settings.scanIntervalMinutes
                                    switch intervalUnit {
                                    case .minutes: return max(1, minutes)
                                    case .hours: return max(1, minutes / 60)
                                    case .days: return max(1, minutes / AppSettings.dailyScanIntervalMinutes)
                                    }
                                },
                                set: { newValue in
                                    switch intervalUnit {
                                    case .minutes:
                                        store.settings.scanIntervalMinutes = clampMinutes(newValue)
                                    case .hours:
                                        store.settings.scanIntervalMinutes = clampMinutes(newValue * 60)
                                    case .days:
                                        store.settings.scanIntervalMinutes = clampMinutes(newValue * AppSettings.dailyScanIntervalMinutes)
                                    }
                                }
                            ), in: intervalRange.lowerBound...intervalRange.upperBound, step: intervalStep) {
                                Text("\(currentIntervalValue)")
                                    .monospacedDigit()
                                    .font(.body)
                            }
                            .fixedSize()
                            .controlSize(.small)

                            Picker("", selection: $intervalUnit) {
                                Text("minutes").tag(IntervalUnit.minutes)
                                Text("hours").tag(IntervalUnit.hours) 
                                Text("days").tag(IntervalUnit.days)
                            }
                            .fixedSize()
                            .pickerStyle(.menu)
                            .onChange(of: intervalUnit) {
                                // Compute the current numeric value in the new unit (rounded down) and clamp to that unit's range
                                let minutes = store.settings.scanIntervalMinutes
                                let valueInNewUnit: Int
                                switch intervalUnit {
                                case .minutes:
                                    valueInNewUnit = max(1, minutes)
                                case .hours:
                                    valueInNewUnit = max(1, minutes / 60)
                                case .days:
                                    valueInNewUnit = max(1, minutes / AppSettings.dailyScanIntervalMinutes)
                                }

                                // Clamp within the unit's available range
                                let clampedValue = min(max(valueInNewUnit, intervalRange.lowerBound), intervalRange.upperBound)

                                // Convert back to minutes and clamp to global bounds
                                switch intervalUnit {
                                case .minutes:
                                    store.settings.scanIntervalMinutes = clampMinutes(clampedValue)
                                case .hours:
                                    store.settings.scanIntervalMinutes = clampMinutes(clampedValue * 60)
                                case .days:
                                    store.settings.scanIntervalMinutes = clampMinutes(clampedValue * AppSettings.dailyScanIntervalMinutes)
                                }
                            }
                        }

                        Label(store.helperScanSummary ?? "Helper scan: no runs yet", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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

                        if let helperActionMessage {
                            Label(helperActionMessage, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    AppSectionView(title: "Updates", description: "Updates are downloaded from GitHub releases.") {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Label("Version \(AppBuildInfo.displayVersion)", systemImage: "app.badge")
                                .foregroundStyle(.secondary)

                            Label(updateTargetVersionLabel, systemImage: "arrow.right")
                                .foregroundStyle(updateStatusColor)
                        }

                        if !store.updateReleaseNotes.isEmpty {
                            ReleaseNotesDisclosureList(markdown: store.updateReleaseNotes)
                        }

                        if let updateLastError = store.updateLastError, shouldShowUpdateError {
                            Label(updateLastError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(updateStatusColor)
                                .textSelection(.enabled)
                        }

                        Group {
                            switch store.updateStatus {
                            case .downloading:
                                if let progress = store.updateDownloadProgress {
                                    ProgressView(value: progress) {
                                        Text("Downloading update")
                                    } currentValueLabel: {
                                        Text("\(Int(progress * 100))%")
                                    }
                                } else {
                                    ProgressView {
                                        Text("Preparing download")
                                    }
                                }
                            case .available:
                                Button {
                                    store.downloadAvailableUpdate()
                                } label: {
                                    Label("Download Update", systemImage: "arrow.down.circle")
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity)
                                }
                            case .readyToInstall:
                                Button {
                                    store.installDownloadedUpdate()
                                } label: {
                                    Label("Install Update", systemImage: "arrow.down.app")
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity)
                                }
                            default:
                                Button {
                                    store.checkForUpdates()
                                } label: {
                                    if store.updateStatus == .checking {
                                        HStack {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Checking...")
                                        }
                                        .frame(maxWidth: .infinity)
                                    } else {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Check Updates")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                                .disabled(store.updateStatus == .checking || store.updateStatus == .downloading || store.updateStatus == .installing)
                                .help("Check GitHub releases for updates")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        VStack {
                            Divider()
                            Toggle("Automatically download updates", isOn: $store.settings.automaticallyChecksForUpdates)
                                .onChange(of: store.settings.automaticallyChecksForUpdates) {
                                    if store.settings.automaticallyChecksForUpdates {
                                        store.requestUpdateNotificationPermission()
                                    }
                                }
                                .toggleStyle(.switch)
                        }
                    }
                }
                .padding(6)
            }
            .listStyle(.plain)
        }
        .frame(width: 450, height: 500)
        .toolbar {
            Button("Close") {
                dismiss()
            }
            .help("Close Settings")
        }
        .disabled(!store.canEdit)
        .onChange(of: store.settings) {
            if store.canEdit { scheduleAutosave() }
        }
        .onDisappear {
            autosaveTask?.cancel()
            store.save()
        }
        .onAppear {
            store.refreshHelperStatus()
            store.refreshLoginItemStatus()
        }
    }

    private func openFullDiskAccessSettings() {
        FullDiskAccessSupport.openSystemSettings()
        permissionsStatusMessage = "Opened Full Disk Access settings"
    }

    private func openBackgroundItemsSettings() {
        BackgroundItemsSupport.openSystemSettings()
        helperActionMessage = "Opened Background Items settings"
    }

    private var fullDiskAccessStatusIcon: String {
        switch store.fullDiskAccessStatus {
        case .granted:
            return "lock.open.fill"
        case .missing:
            return "lock.fill"
        case .sandboxed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var helperStatusLabel: String {
        if !store.isHelperInstalled { return "Helper not installed" }
        if !store.isHelperLoaded { return "Helper disabled" }
        if store.isHelperRunning { return "Helper running" }
        return "Helper installed"
    }

    private var helperStatusIcon: String {
        if !store.isHelperInstalled { return "xmark.circle" }
        if !store.isHelperLoaded { return "exclamationmark.circle.fill" }
        if store.isHelperRunning { return "gearshape.arrow.triangle.2.circlepath" }
        return "checkmark.circle.fill"
    }

    private var helperStatusColor: Color {
        if !store.isHelperInstalled { return .secondary }
        if !store.isHelperLoaded { return .orange }
        if store.isHelperRunning { return .blue }
        return .green
    }

    private var fullDiskAccessStatusColor: Color {
        switch store.fullDiskAccessStatus {
        case .granted:
            return .green
        case .missing:
            return .orange
        case .sandboxed:
            return .secondary
        }
    }

    private var updateStatusColor: Color {
        switch store.updateStatus {
        case .failed:
            return .red
        case .available where store.updateLastError != nil:
            return .orange
        case .readyToInstall, .downloading, .available:
            return .blue
        case .checking, .installing:
            return .secondary
        case .idle, .upToDate:
            return .secondary
        }
    }

    private var updateTargetVersionLabel: String {
        if let updateReleaseVersion = store.updateReleaseVersion {
            return updateReleaseVersion
        }
        if let updateReleaseName = store.updateReleaseName {
            return updateReleaseName
        }

        switch store.updateStatus {
        case .checking:
            return "Checking"
        case .upToDate:
            return "Up to date"
        case .failed:
            return "Update failed"
        case .idle:
            return "No update"
        case .available, .downloading, .readyToInstall, .installing:
            return "Update available"
        }
    }

    private var shouldShowUpdateError: Bool {
        store.updateStatus == .failed || store.updateStatus == .available
    }

    private func pickScanRoots() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"

        guard panel.runModal() == .OK else { return }
        store.addScanRoots(panel.urls)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            store.save()
        }
    }

    private var helperIntervalLabel: String {
        let minutes = store.settings.scanIntervalMinutes
        if minutes == AppSettings.dailyScanIntervalMinutes {
            return "Run helper daily"
        }
        if minutes < AppSettings.dailyScanIntervalMinutes {
            return "Run helper every \(minutes / 60) hour\(minutes == 60 ? "" : "s")"
        }
        let days = minutes / AppSettings.dailyScanIntervalMinutes
        return "Run helper every \(days) day\(days == 1 ? "" : "s")"
    }

    private var currentIntervalValue: Int {
        let minutes = store.settings.scanIntervalMinutes
        switch intervalUnit {
        case .minutes: return max(1, minutes)
        case .hours: return max(1, minutes / 60)
        case .days: return max(1, minutes / AppSettings.dailyScanIntervalMinutes)
        }
    }

    private var currentUnitLabel: String {
        switch intervalUnit {
        case .minutes: return currentIntervalValue == 1 ? "minute" : "minutes"
        case .hours: return currentIntervalValue == 1 ? "hour" : "hours"
        case .days: return currentIntervalValue == 1 ? "day" : "days"
        }
    }
}

private struct ReleaseNotesDisclosureList: View {
    let markdown: String
    @State private var expandedSectionIDs: Set<String> = []

    private var sections: [ReleaseNoteSection] {
        ReleaseNoteParser.sections(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionLabel(title: "Release Notes", topPadding: 2)

            ScrollView {
                if sections.isEmpty {
                    Markdown(markdown)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .releaseNoteGroupBackground()
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sections) { section in
                            ReleaseNoteSectionDisclosure(
                                section: section,
                                isExpanded: isExpandedBinding(for: section)
                            ) {
                                releaseNoteContent(for: section)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 220)
        }
        .onAppear(perform: expandFirstSectionIfNeeded)
        .onChange(of: markdown) {
            expandedSectionIDs.removeAll()
            expandFirstSectionIfNeeded()
        }
    }

    @ViewBuilder
    private func releaseNoteContent(for section: ReleaseNoteSection) -> some View {
        let items = section.displayListItems

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ReleaseNoteItemRow(
                        item: item,
                        showsDivider: index < items.count - 1
                    )
                }
            }
        } else if section.markdown.isEmpty {
            Text("No details provided.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        } else {
            Markdown(section.markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
    }

    private func isExpandedBinding(for section: ReleaseNoteSection) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(section.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(section.id)
                } else {
                    expandedSectionIDs.remove(section.id)
                }
            }
        )
    }

    private func expandFirstSectionIfNeeded() {
        guard expandedSectionIDs.isEmpty, let firstSection = sections.first else { return }
        expandedSectionIDs.insert(firstSection.id)
    }
}

private struct ReleaseNoteSectionDisclosure<Content: View>: View {
    let section: ReleaseNoteSection
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    private var titleParts: ReleaseNoteTitleParts {
        ReleaseNoteTitleParts(section.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 16)

                    Text(titleParts.symbol ?? "📰")
                        .font(.title3)
                        .frame(width: 24)

                    Text(titleParts.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .releaseNoteGroupBackground()
    }
}

private struct ReleaseNoteItemRow: View {
    let item: ReleaseNoteListItem
    var showsDivider = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.symbol ?? "•")
                .font(item.symbol == nil ? .body : .title3)
                .foregroundStyle(item.symbol == nil ? .secondary : .primary)
                .frame(width: 28, alignment: .center)

            Markdown(item.markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let issueReference = item.issueReference {
                if let issueURL = item.issueURL {
                    Link(issueReference, destination: issueURL)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text(issueReference)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .padding(.leading, 54)
            }
        }
    }
}

private struct ReleaseNoteTitleParts {
    let symbol: String?
    let title: String

    init(_ rawTitle: String) {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let whitespaceIndex = trimmedTitle.firstIndex(where: \.isWhitespace) else {
            symbol = nil
            title = trimmedTitle
            return
        }

        let prefix = String(trimmedTitle[..<whitespaceIndex])
        guard prefix.rangeOfCharacter(from: .alphanumerics) == nil else {
            symbol = nil
            title = trimmedTitle
            return
        }

        symbol = prefix
        title = trimmedTitle[whitespaceIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension View {
    func releaseNoteGroupBackground() -> some View {
        background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.secondary.opacity(0.2), lineWidth: 1)
            }
    }
}

#Preview {
    SettingsView()
        .previewModifiers(setSize: false)
}
