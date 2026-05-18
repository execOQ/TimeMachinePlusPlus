import Foundation

struct TimeMachineDestination: Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String
    var url: String?
    var mountPoint: String?
    var shareMountPoint: String?
    var sparsebundlePath: String?

    var detail: String {
        if let mountPoint, !mountPoint.isEmpty {
            return mountPoint
        }
        if let sparsebundlePath, !sparsebundlePath.isEmpty {
            return sparsebundlePath
        }
        if let shareMountPoint, !shareMountPoint.isEmpty {
            return shareMountPoint
        }
        if let url, !url.isEmpty {
            return url
        }
        return kind
    }
}

struct TimeMachineBackupHistory: Equatable {
    var destinationID: String
    var backups: [String]
    var machineDirectories: [String]
    var message: String?
    var requiresFullDiskAccess: Bool
    var noBackupsForCurrentHost: Bool

    static func empty(destinationID: String) -> TimeMachineBackupHistory {
        TimeMachineBackupHistory(
            destinationID: destinationID,
            backups: [],
            machineDirectories: [],
            message: nil,
            requiresFullDiskAccess: false,
            noBackupsForCurrentHost: false
        )
    }
}

struct TimeMachineBackupStatus: Equatable {
    var isRunning: Bool
    var rawOutput: String

    static let unknown = TimeMachineBackupStatus(isRunning: false, rawOutput: "")
}

enum TimeMachineStateParser {
    static func destinations(
        from result: CommandResult,
        mountOutput: String = "",
        diskImageOutput: String = ""
    ) -> [TimeMachineDestination] {
        guard let data = result.output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any],
              let destinations = root["Destinations"] as? [[String: Any]] else {
            return []
        }

        return destinations.compactMap { item in
            guard let id = item["ID"] as? String else { return nil }
            let kind = item["Kind"] as? String ?? "Unknown"
            let shareMountPoint = mountedNetworkSharePoint(for: item, mountOutput: mountOutput)
            return TimeMachineDestination(
                id: id,
                name: item["Name"] as? String ?? "Unnamed Destination",
                kind: kind,
                url: item["URL"] as? String,
                mountPoint: explicitMountPoint(for: item)
                    ?? mountPoint(for: item, mountOutput: mountOutput, diskImageOutput: diskImageOutput),
                shareMountPoint: shareMountPoint,
                sparsebundlePath: sparsebundlePath(for: item, shareMountPoint: shareMountPoint)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func backupStatus(from result: CommandResult) -> TimeMachineBackupStatus {
        let output = result.output + result.errorOutput
        let isRunning = output.contains("Running = 1") || output.contains("Running = true")
        return TimeMachineBackupStatus(isRunning: isRunning, rawOutput: output)
    }

    static func snapshotDates(from result: CommandResult) -> [String] {
        result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !line.localizedCaseInsensitiveContains("Snapshot dates")
            }
    }

    static func backupHistory(destinationID: String, from result: CommandResult) -> TimeMachineBackupHistory {
        let text = (result.output + result.errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
        let backups = result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return TimeMachineBackupHistory(
            destinationID: destinationID,
            backups: result.isSuccess ? backups : [],
            machineDirectories: [],
            message: result.isSuccess ? nil : text,
            requiresFullDiskAccess: text.localizedCaseInsensitiveContains("Full Disk Access"),
            noBackupsForCurrentHost: text.localizedCaseInsensitiveContains("No backups found for host")
                || text.localizedCaseInsensitiveContains("No machine directory found for host")
        )
    }

    static func machineDirectories(from result: CommandResult) -> [String] {
        guard result.isSuccess else { return [] }
        return result.output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func mountedBackupSnapshots(destinationMountPoint: String, mountOutput: String) -> [String] {
        let lines = mountOutput.components(separatedBy: .newlines)
        guard let destinationDevice = lines.compactMap({ line -> String? in
            guard line.contains(" on \(destinationMountPoint) ") else { return nil }
            return line.components(separatedBy: " on ").first
        }).first else {
            return []
        }

        return lines.compactMap { line in
            guard line.contains(".backup@\(destinationDevice)"),
                  let mountPoint = parseMountPoint(from: line) else {
                return nil
            }
            return mountPoint
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func sparsebundleSnapshots(sparsebundlePath: String) -> [String] {
        let historyURL = URL(fileURLWithPath: sparsebundlePath)
            .appendingPathComponent("com.apple.TimeMachine.SnapshotHistory.plist")
        guard let data = try? Data(contentsOf: historyURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any],
              let snapshots = root["Snapshots"] as? [[String: Any]] else {
            return []
        }

        return snapshots.compactMap { snapshot in
            guard let name = snapshot["com.apple.backupd.SnapshotName"] as? String else { return nil }
            return "\(sparsebundlePath)/\(name)"
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func explicitMountPoint(for item: [String: Any]) -> String? {
        guard item["Kind"] as? String != "Network",
              let mountPoint = item["MountPoint"] as? String,
              !mountPoint.isEmpty else {
            return nil
        }
        return mountPoint
    }

    private static func mountPoint(for item: [String: Any], mountOutput: String, diskImageOutput: String) -> String? {
        if let diskImageMountPoint = mountedDiskImagePoint(for: item, diskImageOutput: diskImageOutput) {
            return diskImageMountPoint
        }

        if item["Kind"] as? String == "Network" {
            return nil
        }

        let candidates = mountOutput
            .components(separatedBy: .newlines)
            .compactMap(parseMountPoint)
            .filter { mountPoint in
                !mountPoint.localizedCaseInsensitiveContains("/Volumes/com.apple.TimeMachine.localsnapshots/")
                    && (mountPoint.localizedCaseInsensitiveContains("timemachine")
                        || mountPoint.localizedCaseInsensitiveContains("backup"))
            }

        if let url = item["URL"] as? String,
           let shareName = URL(string: url)?.lastPathComponent,
           let match = candidates.first(where: { $0.localizedCaseInsensitiveContains(shareName) }) {
            return match
        }

        guard let name = item["Name"] as? String else { return nil }
        let nameTokens = tokens(in: name)
        return candidates.first { mountPoint in
            let mountTokens = tokens(in: mountPoint)
            guard !nameTokens.isEmpty else { return false }
            let overlap = nameTokens.filter { mountTokens.contains($0) }.count
            return overlap >= min(2, nameTokens.count)
        }
    }

    private static func mountedNetworkSharePoint(for item: [String: Any], mountOutput: String) -> String? {
        guard item["Kind"] as? String == "Network",
              let url = item["URL"] as? String,
              let shareName = URL(string: url)?.lastPathComponent else {
            return nil
        }

        return mountOutput
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.contains("smbfs"),
                      line.localizedCaseInsensitiveContains(shareName) else {
                    return nil
                }
                return parseMountPoint(from: line)
            }
            .first
    }

    private static func sparsebundlePath(for item: [String: Any], shareMountPoint: String?) -> String? {
        guard item["Kind"] as? String == "Network",
              let shareMountPoint else {
            return nil
        }

        let shareURL = URL(fileURLWithPath: shareMountPoint)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: shareURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let destinationName = item["Name"] as? String
        let bundles = contents.filter { $0.pathExtension.localizedCaseInsensitiveCompare("sparsebundle") == .orderedSame }
        if let destinationName,
           let match = bundles.first(where: { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(destinationName) }) {
            return match.path
        }
        return bundles.first?.path
    }

    private static func mountedDiskImagePoint(for item: [String: Any], diskImageOutput: String) -> String? {
        guard item["Kind"] as? String == "Network" else { return nil }

        let shareName = (item["URL"] as? String).flatMap { URL(string: $0)?.lastPathComponent }
        let destinationName = item["Name"] as? String
        let sections = diskImageOutput.components(separatedBy: "================================================")

        for section in sections {
            let lines = section.components(separatedBy: .newlines)
            guard let imagePathLine = lines.first(where: { $0.hasPrefix("image-path") }) else { continue }
            let imagePath = imagePathLine
                .replacingOccurrences(of: "image-path", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let matchesShare = shareName.map { imagePath.localizedCaseInsensitiveContains($0) } ?? false
            let matchesName = destinationName.map { imagePath.localizedCaseInsensitiveContains($0) } ?? false
            guard matchesShare || matchesName else { continue }

            if let mountLine = lines.last(where: { $0.contains("/Volumes/") }),
               let mountRange = mountLine.range(of: "/Volumes/") {
                return String(mountLine[mountRange.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private static func parseMountPoint(from line: String) -> String? {
        guard let onRange = line.range(of: " on "),
              let optionsRange = line.range(of: " (", range: onRange.upperBound..<line.endIndex) else {
            return nil
        }
        return String(line[onRange.upperBound..<optionsRange.lowerBound])
    }

    private static func tokens(in value: String) -> Set<String> {
        Set(
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && $0 != "the" && $0 != "backup" && $0 != "backups" }
        )
    }
}
