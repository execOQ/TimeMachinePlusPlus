import AppKit
import Foundation

enum PathPicker {
    @MainActor
    static func pickFileOrFolder(initialPath: String, prompt: String = "Select") -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = prompt

        if !initialPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: initialPath).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func pickPaths(
        canChooseFiles: Bool,
        canChooseDirectories: Bool,
        allowsMultipleSelection: Bool = true,
        prompt: String = "Add"
    ) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = canChooseFiles
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = prompt

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
