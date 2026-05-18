import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ManualExclusionsView: View {
    @ObservedObject var store: AppStateStore
    @State private var isDropTargeted = false

    private var acceptedDropTypes: [UTType] {
        [
            .fileURL,
            .url,
            .item,
            .directory,
            .package,
            .data
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                title: "Manual Exclusions",
                subtitle: "Add specific files or folders and verify their Time Machine status immediately."
            ) {
                Button {
                    pickManualPaths()
                } label: {
                    Label("Add", systemImage: "folder.badge.plus")
                }
                .disabled(!store.canEdit)
            }

            VStack(spacing: 12) {
                DropZoneView(isTargeted: isDropTargeted, canEdit: store.canEdit)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                List {
                    ForEach($store.manualExclusions) { $item in
                        HStack(spacing: 12) {
                            Toggle("", isOn: $item.isEnabled)
                                .labelsHidden()
                                .disabled(!store.canEdit)

                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                            Text(item.path)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button(role: .destructive) {
                                store.deleteManual(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!store.canEdit)
                            .help("Remove from TimeMachine++")
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.inset)
            }
            .onDrop(of: acceptedDropTypes, isTargeted: $isDropTargeted, perform: handleDrop(providers:))
            .onChange(of: store.manualExclusions) { _, _ in
                store.save()
            }
        }
    }

    private func pickManualPaths() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Add"

        guard panel.runModal() == .OK else { return }
        store.addManualPaths(panel.urls)
        store.startScanNow()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard store.canEdit else { return false }

        let acceptedProviders = providers.filter(\.mightResolveFileURL)
        guard !acceptedProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var droppedURLs: [URL] = []

        for provider in acceptedProviders {
            group.enter()
            provider.resolveFileURL { url in
                if let url {
                    lock.lock()
                    droppedURLs.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let uniqueURLs = Array(
                Dictionary(grouping: droppedURLs, by: { $0.standardizedFileURL.path })
                    .compactMap { $0.value.first }
            )

            guard !uniqueURLs.isEmpty else { return }

            DispatchQueue.main.async {
                guard store.canEdit else { return }
                store.addManualPaths(uniqueURLs)
                DispatchQueue.main.async {
                    store.startScanNow()
                }
            }
        }

        return true
    }
}

private extension NSItemProvider {
    var mightResolveFileURL: Bool {
        hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            || hasItemConformingToTypeIdentifier(UTType.url.identifier)
            || hasItemConformingToTypeIdentifier(UTType.item.identifier)
            || canLoadObject(ofClass: NSURL.self)
    }

    func resolveFileURL(_ completion: @escaping (URL?) -> Void) {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data, let url = Self.url(from: data) {
                    completion(url)
                    return
                }
                self.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    completion(Self.url(from: item))
                }
            }
            return
        }

        if hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                if let data, let url = Self.url(from: data) {
                    completion(url)
                    return
                }
                self.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    completion(Self.url(from: item))
                }
            }
            return
        }

        if canLoadObject(ofClass: NSURL.self) {
            _ = loadObject(ofClass: NSURL.self) { item, _ in
                completion((item as? NSURL) as URL?)
            }
            return
        }

        resolveFileURL(fromRegisteredTypes: registeredTypeIdentifiers, completion)
    }

    private func resolveFileURL(fromRegisteredTypes identifiers: [String], _ completion: @escaping (URL?) -> Void) {
        var identifiers = identifiers
        guard let identifier = identifiers.first else {
            completion(nil)
            return
        }

        identifiers.removeFirst()
        loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            if let url = Self.url(from: item) {
                completion(url)
            } else {
                self.resolveFileURL(fromRegisteredTypes: identifiers, completion)
            }
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url
            }

            if let string = String(data: data, encoding: .utf8) {
                return url(fromString: string)
            }
        }

        if let url = item as? URL {
            return url
        }

        if let url = item as? NSURL {
            return url as URL
        }

        if let string = item as? String {
            return url(fromString: string)
        }

        if let string = item as? NSString {
            return url(fromString: string as String)
        }

        return nil
    }

    private static func url(from data: Data) -> URL? {
        if let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }

        if let string = String(data: data, encoding: .utf8) {
            return url(fromString: string)
        }

        return nil
    }

    private static func url(fromString rawString: String) -> URL? {
        let string = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        if let url = URL(string: string), url.isFileURL {
            return url
        }

        if string.hasPrefix("/") {
            return URL(fileURLWithPath: string)
        }

        return nil
    }
}

private struct DropZoneView: View {
    var isTargeted: Bool
    var canEdit: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: canEdit ? "tray.and.arrow.down" : "lock")
                .font(.title3)
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(canEdit ? "Drop files or folders here" : "Editing is locked during the current operation")
                    .font(.headline)
                Text(canEdit ? "Dropped items are added as manual exclusions and scanned right away." : "Cancel or wait for the operation to finish before changing exclusions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(isTargeted ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }
}
