import AppKit
import SwiftUI

struct RulesView: View {
    @ObservedObject var store: AppStateStore
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HeaderView(
                    title: "Rules",
                    subtitle: "Exclude by pattern (git-like, regex) or add specific files and folders."
                ) {
                    Button {
                        store.addRule()
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .disabled(!store.canEdit)

                    Button {
                        pickSpecificPaths(store: store)
                    } label: {
                        Label("Add Specific", systemImage: "folder.badge.plus")
                    }
                    .disabled(!store.canEdit)
                }
            }

            List {
                ForEach($store.rules) { $rule in
                    RuleRow(rule: $rule, store: store) {
                        store.deleteRule(rule)
                    }
                }
            }
            .listStyle(.inset)
            .disabled(!store.canEdit)
            .onChange(of: store.rules) { _, _ in
                store.save()
            }
        }
    }
}

@MainActor
private func pickSpecificPaths(store: AppStateStore) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = true
    panel.prompt = "Add"
    guard panel.runModal() == .OK else { return }
    store.addSpecificPaths(panel.urls)
}

private struct RuleRow: View {
    @Binding var rule: RegexRule
    @ObservedObject var store: AppStateStore
    var onDelete: () -> Void
    @State private var isExpanded = false
    @State private var isLoadingPreview = false
    @State private var previewResults: [RulePreviewResult] = []
    @State private var previewTask: Task<Void, Never>?
    @State private var previewKey: RulePreviewKey?
    @State private var hasRequestedPreview = false

    private var validationError: String? {
        RuleMatcher.validationError(for: rule)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if rule.kind == .specific {
                    HStack(spacing: 8) {
                        TextField(rule.kind.placeholder, text: $rule.pattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            pickSpecificPath(into: $rule)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Browse for a file or folder")
                    }
                } else {
                    TextField(rule.kind.placeholder, text: $rule.pattern, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1...4)
                }

                Text(rule.kind.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                RulePreviewPanel(
                    isLoading: isLoadingPreview,
                    results: previewResults,
                    resultLimit: store.settings.previewResultLimit,
                    hasRequestedPreview: hasRequestedPreview,
                    isDisabled: !rule.isEnabled,
                    validationError: validationError
                ) {
                    refreshPreview(debounce: false)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()
                    .onTapGesture {}

                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)

                Picker("Mode", selection: $rule.kind) {
                    ForEach(RuleKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                if rule.kind != .specific {
                    Toggle("Files", isOn: $rule.includeFiles)
                        .help("Allow this rule to match files as well as folders.")
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete rule")
            }
        }
        .padding(.vertical, 8)
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                previewKey = RulePreviewKey(rule: rule)
            } else {
                previewTask?.cancel()
                isLoadingPreview = false
            }
        }
        .onChange(of: rule) { _, _ in
            guard isExpanded else { return }
            let nextKey = RulePreviewKey(rule: rule)
            guard nextKey != previewKey else { return }
            previewKey = nextKey
            refreshPreview(debounce: true)
        }
        .onChange(of: store.settings.scanRoots) { _, _ in
            if isExpanded, hasRequestedPreview {
                refreshPreview(debounce: true)
            }
        }
        .onChange(of: store.settings.maxDepth) { _, _ in
            if isExpanded, hasRequestedPreview {
                refreshPreview(debounce: true)
            }
        }
        .onDisappear {
            previewTask?.cancel()
        }
    }

    private func pickSpecificPath(into rule: Binding<RegexRule>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Select"
        if !rule.wrappedValue.pattern.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: rule.wrappedValue.pattern).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rule.wrappedValue.pattern = url.path
        if rule.wrappedValue.name == "New rule" || rule.wrappedValue.name.isEmpty {
            rule.wrappedValue.name = url.lastPathComponent
        }
    }

    private func refreshPreview(debounce: Bool) {
        previewTask?.cancel()
        hasRequestedPreview = true
        guard rule.isEnabled, validationError == nil else {
            previewResults = []
            isLoadingPreview = false
            return
        }

        let ruleSnapshot = rule
        isLoadingPreview = true
        previewTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
            }
            let results = await store.previewMatches(for: ruleSnapshot)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewResults = results
                isLoadingPreview = false
            }
        }
    }
}

private struct RulePreviewKey: Equatable {
    var kind: RuleKind
    var pattern: String
    var isEnabled: Bool
    var includeFiles: Bool

    init(rule: RegexRule) {
        kind = rule.kind
        pattern = rule.pattern
        isEnabled = rule.isEnabled
        includeFiles = rule.includeFiles
    }
}

private struct RulePreviewPanel: View {
    var isLoading: Bool
    var results: [RulePreviewResult]
    var resultLimit: Int
    var hasRequestedPreview: Bool
    var isDisabled: Bool
    var validationError: String?
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Quick Results", systemImage: "bolt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isDisabled || validationError != nil || isLoading)
                .help("Refresh quick results for this rule")
            }

            if isDisabled {
                Text("Enable this rule to preview matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if validationError != nil {
                Text("Fix the rule before previewing matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking this rule...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !hasRequestedPreview {
                Text("Edit this rule to preview matches, or refresh manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty {
                Text("No matches for this rule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(results) { result in
                        RulePreviewRow(result: result)
                        if result.id != results.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.15))
                )

                if results.count >= resultLimit {
                    Text("Showing first \(resultLimit) matches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RulePreviewRow: View {
    var result: RulePreviewResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.isDirectory ? "folder" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(result.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let sizeBytes = result.sizeBytes {
                Text(Formatters.fileSize(sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Label(result.status.label, systemImage: statusImage)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var statusImage: String {
        switch result.status {
        case .excluded: return "checkmark.circle.fill"
        case .included: return "circle"
        case .missing: return "questionmark.circle"
        case .matched: return "line.3.horizontal.decrease.circle"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .excluded: return .green
        case .included: return .secondary
        case .missing: return .orange
        case .matched: return .blue
        }
    }
}
