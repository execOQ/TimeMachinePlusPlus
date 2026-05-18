import AppKit
import Foundation

enum FullDiskAccessStatus: Equatable {
    case granted
    case missing
    case sandboxed

    var isGranted: Bool {
        self == .granted
    }

    var label: String {
        switch self {
        case .granted:
            return "Full Disk Access granted"
        case .missing:
            return "Full Disk Access needed"
        case .sandboxed:
            return "Full Disk Access unavailable in sandbox"
        }
    }
}

enum FullDiskAccessSupport {
    static var status: FullDiskAccessStatus {
        guard !isSandboxed else { return .sandboxed }
        return canReadProtectedDirectory ? .granted : .missing
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static var canReadProtectedDirectory: Bool {
        protectedProbePaths.contains { path in
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: expandedPath(path))
                return true
            } catch {
                return false
            }
        }
    }

    private static var protectedProbePaths: [String] {
        [
            "~/Library/Containers/com.apple.stocks",
            "~/Library/Safari"
        ]
    }

    private static func expandedPath(_ path: String) -> String {
        guard let pw = getpwuid(getuid()) else { return path }
        let homeURL = URL(
            fileURLWithFileSystemRepresentation: pw.pointee.pw_dir,
            isDirectory: true,
            relativeTo: nil
        )
        return path.replacingOccurrences(of: "~", with: homeURL.path)
    }
}
