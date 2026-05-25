import Foundation

enum TimeMachineCommandResultTone: Equatable {
    case success
    case warning
    case failure
}

struct TimeMachineCommandPresentation: Equatable {
    var title: String
    var summary: String
    var detail: String
    var tone: TimeMachineCommandResultTone
    var exitCode: Int32?

    var hasDetail: Bool {
        !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TimeMachineCommandActivity: Equatable {
    var title: String
    var context: TimeMachineCommandContext
    var detail: String?
    var canCancel: Bool = false
    var representedPath: String?
}

enum TimeMachineCommandContext: Hashable {
    case backups
    case addDestination
    case destinationActions(String)
    case destinationSnapshots(String)
    case snapshots
    case exclusions
    case diagnostics
    case pathDiagnostics
    case compare
    case deleteBackups
    case adoption
    case machineDirectory
}

enum TimeMachineCommandPresentationFormatter {
    static func presentation(
        title: String,
        arguments: [String],
        result: CommandResult
    ) -> TimeMachineCommandPresentation {
        let rawText = combinedOutput(result)
        guard result.isSuccess else {
            let firstError = firstUsefulLine(in: result.errorOutput)
                ?? firstUsefulLine(in: result.output)
            let summary = firstError ?? "tmutil failed with exit \(result.exitCode)."
            return TimeMachineCommandPresentation(
                title: title,
                summary: summary,
                detail: rawText.isEmpty ? "Exit \(result.exitCode). No output." : rawText,
                tone: .failure,
                exitCode: result.exitCode
            )
        }

        let command = arguments.first ?? ""
        let summary: String
        switch command {
        case "compare":
            summary = compareSummary(argumentCount: max(arguments.count - 1, 0), output: rawText)
        case "startbackup":
            summary = "Backup request was sent to Time Machine."
        case "stopbackup":
            summary = "Stop backup request was sent."
        case "setdestination":
            summary = arguments.contains("-a") ? "Destination was added." : "Destinations were updated."
        case "removedestination":
            summary = "Destination was removed."
        case "setquota":
            summary = "Destination quota was updated."
        case "localsnapshot":
            summary = firstUsefulLine(in: rawText) ?? "Local snapshot was created."
        case "deletelocalsnapshots":
            summary = "Local snapshot was deleted."
        case "thinlocalsnapshots":
            summary = firstUsefulLine(in: rawText) ?? "Local snapshots were thinned."
        case "latestbackup":
            return latestBackupPresentation(title: title, rawText: rawText, result: result)
        case "listbackups":
            return listBackupsPresentation(title: title, rawText: rawText, result: result)
        case "delete":
            summary = "Backup snapshot deletion finished."
        case "deleteinprogress":
            summary = "In-progress backup deletion finished."
        case "addexclusion":
            summary = "Exclusions were added."
        case "removeexclusion":
            summary = "Exclusions were removed."
        case "isexcluded":
            summary = exclusionSummary(output: rawText)
        case "inheritbackup":
            summary = "Backup history was inherited."
        case "associatedisk":
            summary = "Disk association finished."
        case "calculatedrift":
            summary = firstUsefulLine(in: rawText) ?? "Drift calculation finished."
        default:
            summary = firstUsefulLine(in: rawText) ?? "\(title) finished."
        }

        return TimeMachineCommandPresentation(
            title: title,
            summary: summary,
            detail: rawText.isEmpty ? "Exit 0. No output." : rawText,
            tone: rawText.localizedCaseInsensitiveContains("warning") ? .warning : .success,
            exitCode: result.exitCode
        )
    }

    static func failure(title: String, error: Error) -> TimeMachineCommandPresentation {
        TimeMachineCommandPresentation(
            title: title,
            summary: error.localizedDescription,
            detail: error.localizedDescription,
            tone: .failure,
            exitCode: nil
        )
    }

    private static func combinedOutput(_ result: CommandResult) -> String {
        [result.output, result.errorOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func firstUsefulLine(in text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func latestBackupPresentation(
        title: String,
        rawText: String,
        result: CommandResult
    ) -> TimeMachineCommandPresentation {
        let latestPath = firstUsefulLine(in: rawText)
        let detail = rawText.isEmpty ? "Exit 0. No output." : rawText

        guard let latestPath else {
            return TimeMachineCommandPresentation(
                title: title,
                summary: "No latest backup path was returned.",
                detail: detail,
                tone: .warning,
                exitCode: result.exitCode
            )
        }

        let exists = FileManager.default.fileExists(atPath: latestPath)
        return TimeMachineCommandPresentation(
            title: title,
            summary: exists ? "Latest mounted backup." : "Latest backup history record is not mounted.",
            detail: exists ? latestPath : "\(latestPath)\n\nThis path was returned by tmutil, but it does not currently exist on disk. Attach or remount the backup image before browsing, comparing, or measuring this snapshot.",
            tone: exists ? .success : .warning,
            exitCode: result.exitCode
        )
    }

    private static func listBackupsPresentation(
        title: String,
        rawText: String,
        result: CommandResult
    ) -> TimeMachineCommandPresentation {
        let paths = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let mountedCount = paths.filter { FileManager.default.fileExists(atPath: $0) }.count
        let historyOnlyCount = paths.count - mountedCount
        let detail = rawText.isEmpty ? "Exit 0. No output." : rawText

        if paths.isEmpty {
            return TimeMachineCommandPresentation(
                title: title,
                summary: "No backup records were returned.",
                detail: detail,
                tone: .warning,
                exitCode: result.exitCode
            )
        }

        if historyOnlyCount > 0 {
            return TimeMachineCommandPresentation(
                title: title,
                summary: "Listed \(paths.count) backup history record\(paths.count == 1 ? "" : "s"); \(historyOnlyCount) not mounted.",
                detail: "\(detail)\n\nPaths marked as not mounted were returned by tmutil, but they do not currently exist on disk.",
                tone: .warning,
                exitCode: result.exitCode
            )
        }

        return TimeMachineCommandPresentation(
            title: title,
            summary: "Listed \(mountedCount) mounted backup\(mountedCount == 1 ? "" : "s").",
            detail: detail,
            tone: .success,
            exitCode: result.exitCode
        )
    }

    private static func compareSummary(argumentCount: Int, output: String) -> String {
        let counts = compareCounts(output: output)
        let target = argumentCount == 0 ? "backup data" : "\(argumentCount) path\(argumentCount == 1 ? "" : "s")"
        let parts = [
            counts.added > 0 ? "\(counts.added) added" : nil,
            counts.removed > 0 ? "\(counts.removed) removed" : nil,
            counts.changed > 0 ? "\(counts.changed) changed" : nil
        ].compactMap { $0 }

        if parts.isEmpty {
            return "Compared \(target)."
        }
        return "Compared \(target): \(parts.joined(separator: ", "))."
    }

    private static func compareCounts(output: String) -> (added: Int, removed: Int, changed: Int) {
        var added = 0
        var removed = 0
        var changed = 0

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("+") || line.localizedCaseInsensitiveContains("added") {
                added += 1
            } else if line.hasPrefix("-") || line.localizedCaseInsensitiveContains("removed") {
                removed += 1
            } else if line.hasPrefix("!") || line.localizedCaseInsensitiveContains("changed") {
                changed += 1
            }
        }

        return (added, removed, changed)
    }

    private static func exclusionSummary(output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let excluded = lines.filter { $0.localizedCaseInsensitiveContains("[Excluded]") }.count
        let included = lines.filter { $0.localizedCaseInsensitiveContains("[Included]") }.count

        if excluded == 0 && included == 0 {
            return firstUsefulLine(in: output) ?? "Exclusion status was checked."
        }

        return "Checked exclusions: \(excluded) excluded, \(included) included."
    }
}
