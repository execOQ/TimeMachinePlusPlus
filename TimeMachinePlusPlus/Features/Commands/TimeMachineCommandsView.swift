import AppKit
import Charts
import SwiftUI

struct TimeMachineCommandsView: View {
    @ObservedObject var store: AppStateStore

    @State private var selection: TimeMachineNativeSelection
    private let showsInternalSidebar: Bool
    @State private var quotaGB = ""
    @State private var destinationURL = ""
    @State private var exclusionPaths = ""
    @State private var selectedSnapshots: Set<String> = []
    @State private var restoreSources = ""
    @State private var restoreDestination = ""
    @State private var comparePaths = ""
    @State private var backupDeletePaths = ""
    @State private var inheritBackupPath = ""
    @State private var associateMountPoint = ""
    @State private var associateSnapshotVolume = ""
    @State private var associateAllSnapshots = false
    @State private var diagnosticPaths = ""
    @State private var snapshotPurgeAmount = ""
    @State private var snapshotUrgency = "4"
    @State private var commandActivity: TimeMachineCommandActivity?
    @State private var commandResults: [TimeMachineCommandContext: TimeMachineCommandPresentation] = [:]
    @State private var pendingDestructiveAction: DestructiveAction?
    @State private var sizeTask: Task<Void, Never>?
    @State private var volumeStats: [String: (total: Int64, free: Int64)] = [:]

    private let client = LiveTimeMachineClient()

    init(
        store: AppStateStore,
        initialSelection: TimeMachineNativeSelection = .backups,
        showsInternalSidebar: Bool = true
    ) {
        self.store = store
        self.showsInternalSidebar = showsInternalSidebar
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: "Time Machine",
                subtitle: "Native controls for destinations, backups, snapshots, exclusions, and diagnostics."
            ) {
                Button {
                    store.refreshFullDiskAccessStatus()
                    openFullDiskAccessSettings()
                } label: {
                    Label(
                        store.fullDiskAccessStatus.isGranted ? "Full Disk Access" : "Full Disk Access",
                        systemImage: store.fullDiskAccessStatus.isGranted ? "lock.open" : "lock"
                    )
                }
                .help(store.fullDiskAccessStatus.label)

                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isWorking)
            }

            HSplitView {
                if showsInternalSidebar {
                    nativeSidebar
                        .frame(minWidth: 270, idealWidth: 320)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        detailView
                    }
                    .padding(20)
                }
                .frame(minWidth: 560)
            }
        }
        .onAppear {
            if case .destination(let id) = selection,
               !store.timeMachineDestinations.contains(where: { $0.id == id }) {
                selection = .backups
            }
        }
        .onChange(of: selection) { _, _ in
            selectedSnapshots.removeAll()
        }
        .confirmationDialog(
            "This changes Time Machine backup data.",
            isPresented: destructiveActionPresented
        ) {
            if let action = pendingDestructiveAction {
                Button(action.buttonTitle, role: .destructive) {
                    runDestructiveAction(action)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pendingDestructiveAction?.message ?? "")
        }
    }

    private var nativeSidebar: some View {
        List(selection: $selection) {
            Section("Manage") {
                Label("Backups", systemImage: "clock.arrow.circlepath")
                    .tag(TimeMachineNativeSelection.backups)
                Label("Local Snapshots", systemImage: "camera.macro")
                    .tag(TimeMachineNativeSelection.snapshots)
                Label("Exclusions", systemImage: "minus.circle")
                    .tag(TimeMachineNativeSelection.exclusions)
                Label("Restore & Compare", systemImage: "arrow.triangle.branch")
                    .tag(TimeMachineNativeSelection.restoreCompare)
                Label("Adoption", systemImage: "link")
                    .tag(TimeMachineNativeSelection.adoption)
                Label("Diagnostics", systemImage: "stethoscope")
                    .tag(TimeMachineNativeSelection.diagnostics)
            }

            Section("Destinations") {
                if store.timeMachineDestinations.isEmpty {
                    Text("No destinations found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.timeMachineDestinations) { destination in
                        DestinationSidebarRow(destination: destination)
                            .tag(TimeMachineNativeSelection.destination(destination.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .backups:
            backupsView
        case .destination(let id):
            destinationView(store.timeMachineDestinations.first { $0.id == id })
        case .snapshots:
            snapshotsView
        case .exclusions:
            exclusionsView
        case .restoreCompare:
            restoreCompareView
        case .adoption:
            adoptionView
        case .diagnostics:
            diagnosticsView
        }
    }

    private var backupsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Backups", subtitle: store.backupStatus.isRunning ? "A Time Machine backup is running." : "No Time Machine backup is currently running.")

            HStack(spacing: 10) {
                Button {
                    run(arguments: ["startbackup", "--auto"], context: .backups, title: "Start Backup", status: "Starting backup...")
                } label: {
                    Label("Start Backup", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    run(arguments: ["startbackup", "--auto", "--block"], context: .backups, title: "Start and Wait", status: "Starting backup and waiting...")
                } label: {
                    Label("Start and Wait", systemImage: "hourglass")
                }

                Spacer()

                Button(role: .destructive) {
                    pendingDestructiveAction = .stopBackup
                } label: {
                    Label("Stop Backup", systemImage: "stop.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.8))
                .disabled(!store.backupStatus.isRunning)
            }

            GroupBox("Automatic Backups") {
                HStack(spacing: 10) {
                    Button {
                        run(arguments: ["enable"], context: .backups, title: "Enable Automatic Backups", asAdministrator: true, status: "Enabling automatic backups...")
                    } label: {
                        Label("Enable", systemImage: "checkmark.circle")
                    }

                    Button {
                        run(arguments: ["disable"], context: .backups, title: "Disable Automatic Backups", asAdministrator: true, status: "Disabling automatic backups...")
                    } label: {
                        Label("Disable", systemImage: "pause.circle")
                    }
                }
                .padding(8)
            }

            commandFeedback(for: .backups)

            addDestinationView
            adoptionBox
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: TimeMachineDestination?) -> some View {
        if let destination {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(destination.name, subtitle: destination.detail)

                GroupBox("Destination Actions") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button {
                                run(arguments: ["startbackup", "--destination", destination.id], context: .destinationActions(destination.id), title: "Back Up Here", status: "Starting backup to \(destination.name)...")
                            } label: {
                                Label("Back Up Here", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Spacer()

                            Button(role: .destructive) {
                                pendingDestructiveAction = .removeDestination(destination)
                            } label: {
                                Label("Remove Destination", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red.opacity(0.8))
                        }

                        Divider()

                        HStack(spacing: 10) {
                            TextField("Quota in GB", text: $quotaGB)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)

                            Button {
                                let quota = quotaGB.trimmingCharacters(in: .whitespacesAndNewlines)
                                run(arguments: ["setquota", destination.id, quota], context: .destinationActions(destination.id), title: "Set Quota", asAdministrator: true, status: "Setting quota...")
                            } label: {
                                Label("Set Quota", systemImage: "internaldrive")
                            }
                            .disabled(quotaGB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        commandFeedback(for: .destinationActions(destination.id))
                    }
                    .padding(8)
                }

                if let mountPoint = destination.mountPoint {
                    storageBox(mountPoint: mountPoint)
                }

                sectionLabel("Snapshots")
                backupHistoryBox(for: destination)

                sectionLabel("Restore & Compare")
                destinationRestoreCompareBox(destination: destination)
            }
            .task(id: destination.id) {
                // Fetch volume stats async so UI doesn't block on network volumes
                if let mountPoint = destination.mountPoint {
                    let stats = await Task.detached(priority: .utility) { () -> (Int64, Int64) in
                        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: mountPoint)
                        let total = (attrs?[.systemSize] as? Int64) ?? 0
                        let free = (attrs?[.systemFreeSize] as? Int64) ?? 0
                        return (total, free)
                    }.value
                    volumeStats[mountPoint] = (stats.0, stats.1)
                }
                // Auto-measure any uncached snapshot sizes in the background
                let backups = store.backupHistoriesByDestinationID[destination.id]?.backups ?? []
                let uncached = backups.filter { store.snapshotSizeCache[$0] == nil }
                if !uncached.isEmpty {
                    startMeasuringSizes(backups: uncached)
                }
            }
        } else {
            Text("Select a destination.")
                .foregroundStyle(.secondary)
        }
    }

    private var addDestinationView: some View {
        GroupBox("Add Destination") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("/Volumes/Backup Disk or smb://user@host/share", text: $destinationURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        pickDestination()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Choose local volume")
                }

                HStack(spacing: 10) {
                    Button {
                        let value = destinationURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        run(arguments: ["setdestination", value], context: .addDestination, title: "Replace Destinations", asAdministrator: true, status: "Setting destination...")
                    } label: {
                        Label("Replace Destinations", systemImage: "externaldrive")
                    }
                    .disabled(destinationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        let value = destinationURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        run(arguments: ["setdestination", "-a", value], context: .addDestination, title: "Add Destination", asAdministrator: true, status: "Adding destination...")
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(destinationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                commandFeedback(for: .addDestination)
            }
            .padding(8)
        }
    }

    private var snapshotsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Local Snapshots", subtitle: "\(store.localSnapshotDates.count) local snapshot date\(store.localSnapshotDates.count == 1 ? "" : "s") found for /.")

            HStack(spacing: 10) {
                Button {
                    run(arguments: ["localsnapshot"], context: .snapshots, title: "Create Snapshot", status: "Creating local snapshot...")
                } label: {
                    Label("Create Snapshot", systemImage: "plus")
                }

                Button(role: .destructive) {
                    pendingDestructiveAction = .thinSnapshots(snapshotPurgeAmount, snapshotUrgency)
                } label: {
                    Label("Thin Snapshots", systemImage: "scissors")
                }
            }

            GroupBox("Local Snapshots") {
                HStack(spacing: 10) {
                    Button {
                        run(arguments: ["enablelocal"], context: .snapshots, title: "Enable Local Snapshots", asAdministrator: true, status: "Enabling local snapshots...")
                    } label: {
                        Label("Enable", systemImage: "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        run(arguments: ["disablelocal"], context: .snapshots, title: "Disable Local Snapshots", asAdministrator: true, status: "Disabling local snapshots...")
                    } label: {
                        Label("Disable", systemImage: "pause.circle")
                    }
                }
                .padding(8)
            }

            commandFeedback(for: .snapshots)

            GroupBox("Thin Options") {
                HStack(spacing: 10) {
                    TextField("Purge amount bytes", text: $snapshotPurgeAmount)
                        .textFieldStyle(.roundedBorder)
                    TextField("Urgency", text: $snapshotUrgency)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                .padding(8)
            }

            GroupBox("Snapshot Dates") {
                if store.localSnapshotDates.isEmpty {
                    Text("No local snapshot dates found.")
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.localSnapshotDates, id: \.self) { date in
                            HStack {
                                Text(date)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(role: .destructive) {
                                    pendingDestructiveAction = .deleteSnapshot(date)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete snapshot")
                            }
                            Divider()
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var exclusionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Exclusions", subtitle: "Add, remove, or check Time Machine exclusions. macOS does not expose a single complete list, so this view combines app-known paths and current scan results.")

            knownExclusionsBox

            GroupBox("Paths") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $exclusionPaths)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 10) {
                        Button {
                            pickExclusionPaths()
                        } label: {
                            Label("Choose Paths", systemImage: "folder")
                        }

                        Button {
                            run(arguments: ["isexcluded"] + parsedExclusionPaths, context: .exclusions, title: "Check Exclusions", status: "Checking exclusions...")
                        } label: {
                            Label("Check", systemImage: "questionmark.circle")
                        }
                        .disabled(parsedExclusionPaths.isEmpty)

                        Button {
                            run(arguments: ["addexclusion"] + parsedExclusionPaths, context: .exclusions, title: "Add Exclusions", status: "Adding exclusions...")
                        } label: {
                            Label("Add", systemImage: "minus.circle")
                        }
                        .disabled(parsedExclusionPaths.isEmpty)

                        Button {
                            run(arguments: ["removeexclusion"] + parsedExclusionPaths, context: .exclusions, title: "Remove Exclusions", status: "Removing exclusions...")
                        } label: {
                            Label("Remove", systemImage: "plus.circle")
                        }
                        .disabled(parsedExclusionPaths.isEmpty)
                    }

                    commandFeedback(for: .exclusions)
                }
                .padding(8)
            }
        }
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Diagnostics", subtitle: "Read-only tmutil information and backup history helpers.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                diagnosticsButton("Status", systemImage: "waveform.path.ecg", arguments: ["status"])
                diagnosticsButton("Latest Backup", systemImage: "clock", arguments: ["latestbackup"])
                diagnosticsButton("List Backups", systemImage: "list.bullet.rectangle", arguments: ["listbackups"])
                diagnosticsButton("Resolved Machine Dir", systemImage: "folder", arguments: ["machinedirectory"])
                diagnosticsButton("tmutil Version", systemImage: "number", arguments: ["version"])
                diagnosticsButton("Help", systemImage: "questionmark.circle", arguments: ["help"])
            }
            commandFeedback(for: .diagnostics)

            GroupBox("Path Diagnostics") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Paths", text: $diagnosticPaths)

                    HStack(spacing: 10) {
                        Button {
                            run(arguments: ["uniquesize"] + parsedLines(diagnosticPaths), context: .pathDiagnostics, title: "Unique Size", status: "Calculating unique size...")
                        } label: {
                            Label("Unique Size", systemImage: "sum")
                        }
                        .disabled(parsedLines(diagnosticPaths).isEmpty)

                        Button {
                            run(arguments: ["verifychecksums"] + parsedLines(diagnosticPaths), context: .pathDiagnostics, title: "Verify Checksums", status: "Verifying checksums...")
                        } label: {
                            Label("Verify Checksums", systemImage: "checkmark.seal")
                        }
                        .disabled(parsedLines(diagnosticPaths).isEmpty)
                    }

                    commandFeedback(for: .pathDiagnostics)
                }
                .padding(8)
            }
        }
    }

    private var restoreCompareView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Restore & Compare", subtitle: "Restore files from backup snapshots or compare current paths against backup data.")

            GroupBox("Compare") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Optional snapshot path, or two paths on separate lines", text: $comparePaths)

                    Button {
                        run(arguments: ["compare"] + parsedLines(comparePaths), context: .restoreCompare, title: "Compare", status: "Comparing backup data...")
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                }
                .padding(8)
            }

            GroupBox("Restore") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Source paths from backups", text: $restoreSources)
                    TextField("Destination path", text: $restoreDestination)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        run(arguments: ["restore", "-v"] + parsedLines(restoreSources) + [restoreDestination], context: .restoreCompare, title: "Restore", status: "Restoring files...")
                    } label: {
                        Label("Restore", systemImage: "arrow.down.doc")
                    }
                    .disabled(parsedLines(restoreSources).isEmpty || restoreDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(8)
            }

            commandFeedback(for: .restoreCompare)

            GroupBox("Delete Backup Snapshots") {
                VStack(alignment: .leading, spacing: 10) {
                    pathEditor("Backup snapshot paths", text: $backupDeletePaths)

                    Button(role: .destructive) {
                        pendingDestructiveAction = .deleteBackupPaths(parsedLines(backupDeletePaths))
                    } label: {
                        Label("Delete Backup Paths", systemImage: "trash")
                    }
                    .disabled(parsedLines(backupDeletePaths).isEmpty)

                    commandFeedback(for: .deleteBackups)
                }
                .padding(8)
            }
        }
    }

    private var adoptionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Adoption", subtitle: "Inherit existing backup history or associate a disk with snapshot history.")
            adoptionBox
        }
    }

    private var adoptionBox: some View {
        GroupBox("Adoption") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inherit Backup")
                        .font(.headline)
                    Text("Claim an existing machine directory or sparsebundle for this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Machine directory or sparsebundle", text: $inheritBackupPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            pickAdoptionPath(assignTo: $inheritBackupPath, canChooseFiles: true)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Choose machine directory or sparsebundle")
                    }

                    Button {
                        run(arguments: ["inheritbackup", inheritBackupPath], context: .adoption, title: "Inherit Backup", asAdministrator: true, status: "Inheriting backup...")
                    } label: {
                        Label("Inherit", systemImage: "link")
                    }
                    .disabled(inheritBackupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Associate Disk")
                        .font(.headline)
                    Text("Connect a current mounted disk to an existing snapshot volume path.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Current mount point", text: $associateMountPoint)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            pickAdoptionPath(assignTo: $associateMountPoint, canChooseFiles: false)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Choose current mount point")
                    }

                    HStack(spacing: 8) {
                        TextField("Snapshot volume path", text: $associateSnapshotVolume)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            pickAdoptionPath(assignTo: $associateSnapshotVolume, canChooseFiles: false)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Choose snapshot volume")
                    }

                    Toggle("Apply to matching snapshots", isOn: $associateAllSnapshots)

                    Button {
                        var arguments = ["associatedisk"]
                        if associateAllSnapshots {
                            arguments.append("-a")
                        }
                        arguments.append(contentsOf: [associateMountPoint, associateSnapshotVolume])
                        run(arguments: arguments, context: .adoption, title: "Associate Disk", asAdministrator: true, status: "Associating disk...")
                    } label: {
                        Label("Associate", systemImage: "link.badge.plus")
                    }
                    .disabled(
                        associateMountPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || associateSnapshotVolume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                commandFeedback(for: .adoption)
            }
            .padding(8)
        }
    }

    private var parsedExclusionPaths: [String] {
        parsedLines(exclusionPaths)
    }

    private var canBrowseSelectedSnapshots: Bool {
        !selectedSnapshots.isEmpty && selectedSnapshots.allSatisfy { !$0.localizedCaseInsensitiveContains(".sparsebundle/") }
    }

    @ViewBuilder
    private func commandFeedback(for context: TimeMachineCommandContext) -> some View {
        if commandActivity?.context == context {
            InlineCommandProgress(title: commandActivity?.title ?? "Running")
        } else if let result = commandResults[context] {
            TimeMachineCommandResultCard(result: result)
        }
    }

    private func startMeasuringSizes(backups: [String]) {
        sizeTask?.cancel()
        store.isMeasuringSizes = true

        sizeTask = Task.detached(priority: .utility) { [store] in
            for path in backups {
                guard !Task.isCancelled else { break }
                if let kb = Self.diskUsageKB(path: path) {
                    await MainActor.run {
                        store.snapshotSizeCache[path] = kb * 1024
                        store.save()
                    }
                }
            }
            await MainActor.run { store.isMeasuringSizes = false }
        }
    }

    nonisolated private static func diskUsageKB(path: String) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        ProcessRegistry.shared.register(process)
        try? process.run()
        process.waitUntilExit()
        ProcessRegistry.shared.deregister(process)
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).first ?? ""
        return Int64(token)
    }

    private func parsedLines(_ value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var destructiveActionPresented: Binding<Bool> {
        Binding(
            get: { pendingDestructiveAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDestructiveAction = nil
                }
            }
        )
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func diagnosticsBox(arguments: [String], title: String) -> some View {
        GroupBox("Diagnostics") {
            Button {
                run(arguments: arguments, context: .diagnostics, title: title, status: "Running \(title)...")
            } label: {
                Label(title, systemImage: "terminal")
            }
            .padding(8)
        }
    }

    private func diagnosticsButton(_ title: String, systemImage: String, arguments: [String]) -> some View {
        Button {
            run(arguments: arguments, context: .diagnostics, title: title, status: "Running \(title)...")
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var knownExclusionsBox: some View {
        GroupBox("Known Exclusions") {
            VStack(alignment: .leading, spacing: 10) {
                let paths = knownExclusionPaths

                if paths.isEmpty {
                    Text("No known exclusions yet. Add specific rules or apply exclusions through backup readiness.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(paths, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(path)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                run(arguments: ["removeexclusion", path], context: .exclusions, title: "Remove Exclusion", status: "Removing exclusion...")
                            } label: {
                                Image(systemName: "plus.circle")
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
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }
                    .disabled(paths.isEmpty)
                }
            }
            .padding(8)
        }
    }

    private var knownExclusionPaths: [String] {
        let applied = store.appliedExclusions.map(\.path)
        let specific = store.rules.filter { $0.kind == .specific && $0.isEnabled }.map(\.pattern)
        let scanned = store.matches.filter(\.isExcluded).map(\.path)
        return Array(Set(applied + specific + scanned))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func backupHistoryBox(for destination: TimeMachineDestination) -> some View {
        GroupBox("Snapshots") {
            VStack(alignment: .leading, spacing: 10) {
                if let mountPoint = destination.mountPoint {
                    Label(mountPoint, systemImage: "externaldrive")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Label("Backup volume is not mounted", systemImage: "externaldrive.badge.xmark")
                        .foregroundStyle(.secondary)
                }

                let history = store.backupHistoriesByDestinationID[destination.id] ?? .empty(destinationID: destination.id)

                if !history.backups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(history.backups, id: \.self) { backup in
                            HStack(spacing: 8) {
                                Toggle("", isOn: snapshotBinding(backup))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                Text(backup)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if let size = store.snapshotSizeCache[backup] {
                                    Text(Formatters.fileSize(size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                } else if store.isMeasuringSizes {
                                    ProgressView().controlSize(.mini)
                                }
                                Button(role: .destructive) {
                                    pendingDestructiveAction = .deleteBackupPaths([backup])
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete this backup snapshot")
                            }
                        }

                        let measured = history.backups.compactMap { store.snapshotSizeCache[$0] }
                        if !measured.isEmpty {
                            HStack {
                                Text("Total measured (\(measured.count) of \(history.backups.count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.fileSize(measured.reduce(0, +)))
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                            }
                            .padding(.top, 4)
                        }
                    }
                } else if history.noBackupsForCurrentHost {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("This destination has backup storage, but tmutil did not find backups for this Mac identity.", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.orange)

                        if !history.machineDirectories.isEmpty {
                            Text("Machine directories found:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(history.machineDirectories, id: \.self) { directory in
                                Text(directory)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Text("If this is backup history from another Mac or renamed disk, Inherit Backup or Associate Disk may be needed before snapshots appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if history.requiresFullDiskAccess {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Backup history exists, but this running app still cannot read it.", systemImage: "lock.fill")
                            .foregroundStyle(.orange)

                        Text("Add this exact app to Full Disk Access, then quit and reopen it:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Bundle.main.bundlePath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)

                        if let message = history.message, !message.isEmpty {
                            Text(message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                        Button {
                            openFullDiskAccessSettings()
                        } label: {
                            Label("Open Full Disk Access", systemImage: "gearshape")
                        }

                            Button {
                                revealCurrentAppInFinder()
                            } label: {
                                Label("Reveal App", systemImage: "magnifyingglass")
                            }

                            Button {
                                store.refreshFullDiskAccessStatus()
                            } label: {
                                Label("Recheck", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                } else if let message = history.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.localizedCaseInsensitiveContains("sparsebundle") ? .orange : .secondary)
                } else {
                    Text("No backup history was returned for this destination.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        pendingDestructiveAction = .deleteBackupPaths(Array(selectedSnapshots))
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(selectedSnapshots.isEmpty)

                    Button(role: .destructive) {
                        pendingDestructiveAction = .thinSnapshots(snapshotPurgeAmount, snapshotUrgency)
                    } label: {
                        Label("Thin Local", systemImage: "scissors")
                    }

                    Button {
                        if let mountPoint = destination.mountPoint {
                            run(arguments: ["listbackups", "-d", mountPoint], context: .destinationSnapshots(destination.id), title: "List Backups", status: "Listing backups...")
                        } else {
                            run(arguments: ["listbackups"], context: .destinationSnapshots(destination.id), title: "List Backups", status: "Listing backups...")
                        }
                    } label: {
                        Label("List Backups", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(destination.mountPoint == nil)
                    .help(destination.mountPoint == nil ? "The network share is mounted, but the Time Machine backup image is not mounted as a browsable snapshot volume." : "List backups for this destination")

                    Button {
                        if let mountPoint = destination.mountPoint {
                            run(arguments: ["latestbackup", "-d", mountPoint], context: .destinationSnapshots(destination.id), title: "Latest Backup", status: "Finding latest backup...")
                        } else {
                            run(arguments: ["latestbackup"], context: .destinationSnapshots(destination.id), title: "Latest Backup", status: "Finding latest backup...")
                        }
                    } label: {
                        Label("Latest", systemImage: "clock")
                    }
                    .disabled(destination.mountPoint == nil)
                    .help(destination.mountPoint == nil ? "The network share is mounted, but the Time Machine backup image is not mounted as a browsable snapshot volume." : "Find latest backup for this destination")

                    Divider().frame(height: 16)

                    if store.isMeasuringSizes {
                        ProgressView().controlSize(.small)
                        Button("Cancel") {
                            sizeTask?.cancel()
                            store.isMeasuringSizes = false
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        let uncached = history.backups.filter { store.snapshotSizeCache[$0] == nil }
                        Button {
                            let toMeasure = uncached.isEmpty ? history.backups : uncached
                            startMeasuringSizes(backups: toMeasure)
                        } label: {
                            Label(uncached.isEmpty ? "Re-measure" : "Measure Sizes", systemImage: "ruler")
                        }
                        .disabled(history.backups.isEmpty)
                        .help(uncached.isEmpty ? "All sizes cached — click to re-measure" : "Measure total disk usage of each snapshot")
                    }
                }

                commandFeedback(for: .destinationSnapshots(destination.id))
            }
            .padding(8)
        }
    }

    private func destinationRestoreCompareBox(destination: TimeMachineDestination) -> some View {
        GroupBox("Compare & Restore") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select one snapshot above, or enter exact snapshot item paths below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        run(arguments: ["compare"] + Array(selectedSnapshots), context: .destinationRestoreCompare(destination.id), title: "Compare Selected", status: "Comparing selected snapshots...")
                    } label: {
                        Label("Compare Selected", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(selectedSnapshots.isEmpty || !canBrowseSelectedSnapshots)
                    .help(canBrowseSelectedSnapshots ? "Compare selected snapshots" : "These entries came from sparsebundle history and are not mounted snapshot paths yet.")

                    Button {
                        restoreSources = Array(selectedSnapshots).joined(separator: "\n")
                    } label: {
                        Label("Use Selected for Restore", systemImage: "arrow.down.doc")
                    }
                    .disabled(selectedSnapshots.isEmpty)
                }

                pathEditor("Restore sources", text: $restoreSources)
                TextField("Restore destination", text: $restoreDestination)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button {
                    run(arguments: ["restore", "-v"] + parsedLines(restoreSources) + [restoreDestination], context: .destinationRestoreCompare(destination.id), title: "Restore", status: "Restoring files...")
                } label: {
                    Label("Restore", systemImage: "arrow.down.doc")
                }
                .disabled(parsedLines(restoreSources).isEmpty || restoreDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                commandFeedback(for: .destinationRestoreCompare(destination.id))
            }
            .padding(8)
        }
    }

    private func storageBox(mountPoint: String) -> some View {
        GroupBox("Storage") {
            if let stats = volumeStats[mountPoint] {
                let used = max(0, stats.total - stats.free)
                let usedFraction = stats.total > 0 ? Double(used) / Double(stats.total) : 0
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: usedFraction)
                        .progressViewStyle(.linear)
                        .tint(usedFraction > 0.9 ? .red : usedFraction > 0.75 ? .orange : .accentColor)

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                        GridRow {
                            storageCell("Used", value: Formatters.fileSize(used))
                            storageCell("Available", value: Formatters.fileSize(stats.free))
                            storageCell("Total", value: Formatters.fileSize(stats.total))
                        }
                    }
                    .font(.caption)
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    private func storageCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
    }

    private func snapshotBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { selectedSnapshots.contains(path) },
            set: { isSelected in
                if isSelected {
                    selectedSnapshots.insert(path)
                } else {
                    selectedSnapshots.remove(path)
                }
            }
        )
    }

    private func pathEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func refresh() {
        Task {
            await store.refreshTimeMachineState()
            store.statusMessage = "Refreshed Time Machine state"
        }
    }

    private func run(
        arguments: [String],
        context: TimeMachineCommandContext? = nil,
        title: String? = nil,
        asAdministrator: Bool = false,
        status: String
    ) {
        let resolvedContext = context ?? currentCommandContext
        let resolvedTitle = title ?? arguments.first.map { "tmutil \($0)" } ?? "Time Machine"
        guard store.beginBlockingOperation(title: status) else { return }
        commandActivity = TimeMachineCommandActivity(title: status, context: resolvedContext)

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try client.run(arguments: arguments, asAdministrator: asAdministrator) }
            }.value

            var finalStatus = "Time Machine command finished"
            await MainActor.run {
                switch result {
                case .success(let commandResult):
                    let presentation = TimeMachineCommandPresentationFormatter.presentation(
                        title: resolvedTitle,
                        arguments: arguments,
                        result: commandResult
                    )
                    commandResults[resolvedContext] = presentation
                    finalStatus = commandResult.isSuccess ? "\(resolvedTitle) finished" : presentation.summary
                    if asAdministrator, !commandResult.isSuccess {
                        store.refreshFullDiskAccessStatus()
                    }
                case .failure(let error):
                    commandResults[resolvedContext] = TimeMachineCommandPresentationFormatter.failure(
                        title: resolvedTitle,
                        error: error
                    )
                    finalStatus = "tmutil failed"
                }
                commandActivity = nil
            }

            await store.refreshTimeMachineState()
            await MainActor.run {
                store.finishBlockingOperation(status: finalStatus)
            }
        }
    }

    private func runDestructiveAction(_ action: DestructiveAction) {
        switch action {
        case .stopBackup:
            run(arguments: ["stopbackup"], context: .backups, title: "Stop Backup", status: "Stopping backup...")
        case .removeDestination(let destination):
            run(arguments: ["removedestination", destination.id], context: .destinationActions(destination.id), title: "Remove Destination", asAdministrator: true, status: "Removing destination...")
        case .deleteSnapshot(let date):
            run(arguments: ["deletelocalsnapshots", date], context: .snapshots, title: "Delete Local Snapshot", asAdministrator: true, status: "Deleting local snapshot...")
        case .thinSnapshots(let purgeAmount, let urgency):
            var arguments = ["thinlocalsnapshots", "/"]
            let amount = purgeAmount.trimmingCharacters(in: .whitespacesAndNewlines)
            let urgencyValue = urgency.trimmingCharacters(in: .whitespacesAndNewlines)
            if !amount.isEmpty {
                arguments.append(amount)
                if !urgencyValue.isEmpty {
                    arguments.append(urgencyValue)
                }
            }
            run(arguments: arguments, context: .snapshots, title: "Thin Local Snapshots", status: "Thinning local snapshots...")
        case .deleteBackupPaths(let paths):
            run(arguments: ["delete"] + paths, context: deleteContext(for: paths), title: "Delete Backup Paths", asAdministrator: true, status: "Deleting backup paths...")
        case .deleteInProgress:
            break
        }
    }

    private var currentCommandContext: TimeMachineCommandContext {
        switch selection {
        case .backups:
            return .backups
        case .destination(let id):
            return .destinationActions(id)
        case .snapshots:
            return .snapshots
        case .exclusions:
            return .exclusions
        case .restoreCompare:
            return .restoreCompare
        case .adoption:
            return .adoption
        case .diagnostics:
            return .diagnostics
        }
    }

    private func deleteContext(for paths: [String]) -> TimeMachineCommandContext {
        if case .destination(let id) = selection {
            return .destinationSnapshots(id)
        }
        return .deleteBackups
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationURL = url.path
    }

    private func pickExclusionPaths() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return }
        let additions = panel.urls.map(\.path).joined(separator: "\n")
        exclusionPaths = exclusionPaths.isEmpty ? additions : exclusionPaths + "\n" + additions
    }

    private func pickAdoptionPath(assignTo value: Binding<String>, canChooseFiles: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = canChooseFiles
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        value.wrappedValue = url.path
    }

    private func openFullDiskAccessSettings() {
        FullDiskAccessSupport.openSystemSettings()
        store.statusMessage = "Opened Full Disk Access settings"
    }

    private func revealCurrentAppInFinder() {
        FullDiskAccessSupport.revealCurrentAppInFinder()
        store.statusMessage = "Revealed the app that needs Full Disk Access"
    }
}

enum TimeMachineNativeSelection: Hashable {
    case backups
    case destination(String)
    case snapshots
    case exclusions
    case restoreCompare
    case adoption
    case diagnostics
}

private enum DestructiveAction: Identifiable {
    case stopBackup
    case removeDestination(TimeMachineDestination)
    case deleteSnapshot(String)
    case thinSnapshots(String, String)
    case deleteBackupPaths([String])
    case deleteInProgress

    var id: String {
        switch self {
        case .stopBackup:
            return "stopBackup"
        case .removeDestination(let destination):
            return "removeDestination-\(destination.id)"
        case .deleteSnapshot(let date):
            return "deleteSnapshot-\(date)"
        case .thinSnapshots(let amount, let urgency):
            return "thinSnapshots-\(amount)-\(urgency)"
        case .deleteBackupPaths(let paths):
            return "deleteBackupPaths-\(paths.joined(separator: "|"))"
        case .deleteInProgress:
            return "deleteInProgress"
        }
    }

    var buttonTitle: String {
        switch self {
        case .stopBackup:
            return "Stop Backup"
        case .removeDestination:
            return "Remove Destination"
        case .deleteSnapshot:
            return "Delete Snapshot"
        case .thinSnapshots:
            return "Thin Snapshots"
        case .deleteBackupPaths:
            return "Delete Backup Paths"
        case .deleteInProgress:
            return "Delete In-Progress Backup"
        }
    }

    var message: String {
        switch self {
        case .stopBackup:
            return "The currently running backup will be stopped."
        case .removeDestination(let destination):
            return "\(destination.name) will be removed from Time Machine destinations."
        case .deleteSnapshot(let date):
            return "Local snapshot \(date) will be deleted."
        case .thinSnapshots:
            return "Time Machine will purge local snapshots for the startup volume."
        case .deleteBackupPaths(let paths):
            return "\(paths.count) backup path\(paths.count == 1 ? "" : "s") will be deleted."
        case .deleteInProgress:
            return "The in-progress backup will be deleted."
        }
    }
}



private struct InlineCommandProgress: View {
    var title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimeMachineCommandResultCard: View {
    var result: TimeMachineCommandPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                    Text(result.summary)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            if result.hasDetail {
                DisclosureGroup("Details") {
                    Text(result.detail)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var systemImage: String {
        switch result.tone {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch result.tone {
        case .success:
            return .green
        case .warning:
            return .yellow
        case .failure:
            return .red
        }
    }
}

private struct DestinationSidebarRow: View {
    var destination: TimeMachineDestination

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.kind == "Network" ? "network" : "externaldrive")
                .foregroundStyle(.secondary)
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
