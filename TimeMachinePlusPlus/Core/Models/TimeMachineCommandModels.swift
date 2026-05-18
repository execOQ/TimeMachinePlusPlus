import Foundation

enum TimeMachineCommandCategory: String, CaseIterable, Identifiable {
    case backups = "Backups"
    case destinations = "Destinations"
    case exclusions = "Exclusions"
    case snapshots = "Snapshots"
    case restoreCompare = "Restore & Compare"
    case adoption = "Adoption"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
}

enum TimeMachineCommandInputKind: Hashable {
    case text
    case path
    case paths
    case number
}

struct TimeMachineCommandOption: Identifiable, Hashable {
    enum ValueKind: Hashable {
        case flag
        case value(TimeMachineCommandInputKind)
    }

    var id: String
    var label: String
    var help: String
    var arguments: [String]
    var valueKind: ValueKind
    var placeholder: String

    init(
        id: String,
        label: String,
        help: String,
        arguments: [String],
        valueKind: ValueKind = .flag,
        placeholder: String = ""
    ) {
        self.id = id
        self.label = label
        self.help = help
        self.arguments = arguments
        self.valueKind = valueKind
        self.placeholder = placeholder
    }
}

struct TimeMachineCommandArgument: Identifiable, Hashable {
    var id: String
    var label: String
    var help: String
    var placeholder: String
    var kind: TimeMachineCommandInputKind
    var isRequired: Bool

    init(
        id: String,
        label: String,
        help: String,
        placeholder: String,
        kind: TimeMachineCommandInputKind = .text,
        isRequired: Bool = true
    ) {
        self.id = id
        self.label = label
        self.help = help
        self.placeholder = placeholder
        self.kind = kind
        self.isRequired = isRequired
    }
}

struct TimeMachineCommandDefinition: Identifiable, Hashable {
    var id: String
    var title: String
    var verb: String
    var category: TimeMachineCommandCategory
    var summary: String
    var usage: String
    var requiresAdministrator: Bool
    var isDestructive: Bool
    var options: [TimeMachineCommandOption]
    var arguments: [TimeMachineCommandArgument]

    init(
        id: String,
        title: String,
        verb: String? = nil,
        category: TimeMachineCommandCategory,
        summary: String,
        usage: String,
        requiresAdministrator: Bool = false,
        isDestructive: Bool = false,
        options: [TimeMachineCommandOption] = [],
        arguments: [TimeMachineCommandArgument] = []
    ) {
        self.id = id
        self.title = title
        self.verb = verb ?? id
        self.category = category
        self.summary = summary
        self.usage = usage
        self.requiresAdministrator = requiresAdministrator
        self.isDestructive = isDestructive
        self.options = options
        self.arguments = arguments
    }
}

struct TimeMachineCommandForm: Equatable {
    var selectedOptions: Set<String> = []
    var optionValues: [String: String] = [:]
    var argumentValues: [String: String] = [:]
    var runAsAdministrator = false
}

enum TimeMachineCommandBuildError: LocalizedError, Equatable {
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let label):
            return "Enter \(label) before running this command."
        }
    }
}

enum TimeMachineCommandBuilder {
    static func arguments(for definition: TimeMachineCommandDefinition, form: TimeMachineCommandForm) throws -> [String] {
        var arguments = [definition.verb]

        for option in definition.options where form.selectedOptions.contains(option.id) {
            arguments.append(contentsOf: option.arguments)

            if case .value(let kind) = option.valueKind {
                let values = parsedValues(form.optionValues[option.id] ?? "", kind: kind)
                guard !values.isEmpty else { throw TimeMachineCommandBuildError.missingValue(option.label) }
                arguments.append(contentsOf: values)
            }
        }

        for argument in definition.arguments {
            let values = parsedValues(form.argumentValues[argument.id] ?? "", kind: argument.kind)
            if argument.isRequired, values.isEmpty {
                throw TimeMachineCommandBuildError.missingValue(argument.label)
            }
            arguments.append(contentsOf: values)
        }

        return arguments
    }

    static func previewCommand(for definition: TimeMachineCommandDefinition, form: TimeMachineCommandForm) -> String {
        do {
            return try shellCommand(arguments: arguments(for: definition, form: form))
        } catch {
            return shellCommand(arguments: [definition.verb])
        }
    }

    static func shellCommand(arguments: [String]) -> String {
        (["tmutil"] + arguments).map(quoteForShell).joined(separator: " ")
    }

    private static func parsedValues(_ rawValue: String, kind: TimeMachineCommandInputKind) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        switch kind {
        case .paths:
            return trimmed
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .text, .path, .number:
            return [trimmed]
        }
    }

    private static func quoteForShell(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-./:=,@%")
        if value.rangeOfCharacter(from: safeCharacters.inverted) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension TimeMachineCommandDefinition {
    static let catalog: [TimeMachineCommandDefinition] = [
        TimeMachineCommandDefinition(
            id: "startbackup",
            title: "Start Backup",
            category: .backups,
            summary: "Start a Time Machine backup.",
            usage: "tmutil startbackup [-a|--auto] [-b|--block] [-r|--rotation] [-d|--destination id]",
            options: [
                TimeMachineCommandOption(id: "auto", label: "Automatic mode", help: "Ask Time Machine to behave like an automatic scheduled backup.", arguments: ["--auto"]),
                TimeMachineCommandOption(id: "block", label: "Wait until finished", help: "Keep the command running until the backup completes.", arguments: ["--block"]),
                TimeMachineCommandOption(id: "rotation", label: "Allow destination rotation", help: "Allow Time Machine to choose among configured destinations.", arguments: ["--rotation"]),
                TimeMachineCommandOption(id: "destination", label: "Destination ID", help: "Run the backup to one destination ID from destinationinfo.", arguments: ["--destination"], valueKind: .value(.text), placeholder: "Destination UUID")
            ]
        ),
        TimeMachineCommandDefinition(
            id: "stopbackup",
            title: "Stop Backup",
            category: .backups,
            summary: "Cancel the backup currently in progress.",
            usage: "tmutil stopbackup",
            isDestructive: true
        ),
        TimeMachineCommandDefinition(
            id: "enable",
            title: "Enable Automatic Backups",
            category: .backups,
            summary: "Turn on automatic Time Machine backups.",
            usage: "tmutil enable",
            requiresAdministrator: true
        ),
        TimeMachineCommandDefinition(
            id: "disable",
            title: "Disable Automatic Backups",
            category: .backups,
            summary: "Turn off automatic Time Machine backups.",
            usage: "tmutil disable",
            requiresAdministrator: true
        ),
        TimeMachineCommandDefinition(
            id: "destinationinfo",
            title: "Destination Info",
            category: .destinations,
            summary: "Show configured Time Machine destinations.",
            usage: "tmutil destinationinfo [-X]",
            options: [
                TimeMachineCommandOption(id: "xml", label: "XML output", help: "Print the result as an XML property list.", arguments: ["-X"])
            ]
        ),
        TimeMachineCommandDefinition(
            id: "setdestination",
            title: "Set Destination",
            category: .destinations,
            summary: "Replace or add a local volume or AFP share as a backup destination.",
            usage: "tmutil setdestination [-a] mount_point | tmutil setdestination [-ap] afp://user[:pass]@host/share",
            requiresAdministrator: true,
            options: [
                TimeMachineCommandOption(id: "add", label: "Add to existing destinations", help: "Append this destination instead of replacing the current list.", arguments: ["-a"]),
                TimeMachineCommandOption(id: "passwordPrompt", label: "Prompt for AFP password", help: "Use tmutil's password prompt for AFP destinations.", arguments: ["-p"])
            ],
            arguments: [
                TimeMachineCommandArgument(id: "destination", label: "Destination", help: "Volume mount point or AFP URL.", placeholder: "/Volumes/Backup Disk or afp://user@host/share", kind: .path)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "removedestination",
            title: "Remove Destination",
            category: .destinations,
            summary: "Remove a configured backup destination by ID.",
            usage: "tmutil removedestination destination_id",
            requiresAdministrator: true,
            isDestructive: true,
            arguments: [
                TimeMachineCommandArgument(id: "destinationID", label: "Destination ID", help: "Unique destination identifier from destinationinfo.", placeholder: "Destination UUID")
            ]
        ),
        TimeMachineCommandDefinition(
            id: "setquota",
            title: "Set Destination Quota",
            category: .destinations,
            summary: "Set a destination quota in gigabytes.",
            usage: "tmutil setquota destination_id quota_in_gigabytes",
            requiresAdministrator: true,
            arguments: [
                TimeMachineCommandArgument(id: "destinationID", label: "Destination ID", help: "Unique destination identifier from destinationinfo.", placeholder: "Destination UUID"),
                TimeMachineCommandArgument(id: "quota", label: "Quota in GB", help: "Maximum storage for this destination.", placeholder: "500", kind: .number)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "addexclusion",
            title: "Add Exclusion",
            category: .exclusions,
            summary: "Exclude files, folders, or volumes from future backups.",
            usage: "tmutil addexclusion [-p|-v] item ...",
            options: [
                TimeMachineCommandOption(id: "fixedPath", label: "Fixed path exclusion", help: "Exclude the path rather than the current file identity.", arguments: ["-p"]),
                TimeMachineCommandOption(id: "volume", label: "Volume exclusion", help: "Apply volume-style exclusion behavior.", arguments: ["-v"])
            ],
            arguments: [
                TimeMachineCommandArgument(id: "items", label: "Items", help: "One path per line.", placeholder: "/Users/me/Library/Caches", kind: .paths)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "removeexclusion",
            title: "Remove Exclusion",
            category: .exclusions,
            summary: "Allow files, folders, or volumes to be backed up again.",
            usage: "tmutil removeexclusion [-p|-v] item ...",
            options: [
                TimeMachineCommandOption(id: "fixedPath", label: "Fixed path exclusion", help: "Remove a fixed-path exclusion.", arguments: ["-p"]),
                TimeMachineCommandOption(id: "volume", label: "Volume exclusion", help: "Remove a volume-style exclusion.", arguments: ["-v"])
            ],
            arguments: [
                TimeMachineCommandArgument(id: "items", label: "Items", help: "One path per line.", placeholder: "/Users/me/Library/Caches", kind: .paths)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "isexcluded",
            title: "Check Exclusion",
            category: .exclusions,
            summary: "Check whether paths are included or excluded.",
            usage: "tmutil isexcluded [-X] item ...",
            options: [
                TimeMachineCommandOption(id: "xml", label: "XML output", help: "Print the result as an XML property list.", arguments: ["-X"])
            ],
            arguments: [
                TimeMachineCommandArgument(id: "items", label: "Items", help: "One path per line.", placeholder: "/Users/me/Documents", kind: .paths)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "localsnapshot",
            title: "Create Local Snapshot",
            category: .snapshots,
            summary: "Create a new local Time Machine snapshot.",
            usage: "tmutil localsnapshot"
        ),
        TimeMachineCommandDefinition(
            id: "listlocalsnapshots",
            title: "List Local Snapshots",
            category: .snapshots,
            summary: "List local snapshots for a mount point.",
            usage: "tmutil listlocalsnapshots mount_point",
            arguments: [
                TimeMachineCommandArgument(id: "mountPoint", label: "Mount Point", help: "Usually / for the startup volume.", placeholder: "/", kind: .path)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "listlocalsnapshotdates",
            title: "List Local Snapshot Dates",
            category: .snapshots,
            summary: "List local snapshot dates for a mount point.",
            usage: "tmutil listlocalsnapshotdates [mount_point]",
            arguments: [
                TimeMachineCommandArgument(id: "mountPoint", label: "Mount Point", help: "Optional mount point.", placeholder: "/", kind: .path, isRequired: false)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "deletelocalsnapshots",
            title: "Delete Local Snapshots",
            category: .snapshots,
            summary: "Delete local snapshots by mount point or snapshot date.",
            usage: "tmutil deletelocalsnapshots [mount_point | snapshot_date]",
            requiresAdministrator: true,
            isDestructive: true,
            arguments: [
                TimeMachineCommandArgument(id: "target", label: "Mount Point or Date", help: "Use a mount point or a snapshot date from listlocalsnapshotdates.", placeholder: "/ or 2026-05-17-120000", kind: .path, isRequired: false)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "thinlocalsnapshots",
            title: "Thin Local Snapshots",
            category: .snapshots,
            summary: "Ask Time Machine to purge local snapshots.",
            usage: "tmutil thinlocalsnapshots mount_point [purgeamount] [urgency]",
            isDestructive: true,
            arguments: [
                TimeMachineCommandArgument(id: "mountPoint", label: "Mount Point", help: "Usually / for the startup volume.", placeholder: "/", kind: .path),
                TimeMachineCommandArgument(id: "purgeAmount", label: "Purge Amount", help: "Optional byte amount to purge.", placeholder: "10000000000", kind: .number, isRequired: false),
                TimeMachineCommandArgument(id: "urgency", label: "Urgency", help: "Optional urgency value from 1 to 4.", placeholder: "4", kind: .number, isRequired: false)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "delete",
            title: "Delete Backup Snapshot",
            category: .snapshots,
            summary: "Delete backup snapshots or a backup at a destination timestamp.",
            usage: "tmutil delete snapshot_path ... OR tmutil delete -d mount_point -t timestamp [-p path]",
            requiresAdministrator: true,
            isDestructive: true,
            options: [
                TimeMachineCommandOption(id: "mountPoint", label: "Backup mount point", help: "Use with timestamp deletion.", arguments: ["-d"], valueKind: .value(.path), placeholder: "/Volumes/Backup Disk"),
                TimeMachineCommandOption(id: "timestamp", label: "Timestamp", help: "Use with backup mount point.", arguments: ["-t"], valueKind: .value(.text), placeholder: "2026-05-17-120000"),
                TimeMachineCommandOption(id: "path", label: "Path", help: "Optional path for timestamp deletion.", arguments: ["-p"], valueKind: .value(.path), placeholder: "/Users/me/Documents")
            ],
            arguments: [
                TimeMachineCommandArgument(id: "snapshots", label: "Snapshot Paths", help: "One snapshot path per line. Leave blank when using -d and -t.", placeholder: "/Volumes/Backup/Backups.backupdb/Mac/2026-05-17-120000", kind: .paths, isRequired: false)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "deleteinprogress",
            title: "Delete In-Progress Backup",
            category: .snapshots,
            summary: "Delete an in-progress backup in a machine directory.",
            usage: "tmutil deleteinprogress machine_directory",
            requiresAdministrator: true,
            isDestructive: true,
            arguments: [
                TimeMachineCommandArgument(id: "machineDirectory", label: "Machine Directory", help: "Machine directory inside Backups.backupdb.", placeholder: "/Volumes/Backup/Backups.backupdb/Mac", kind: .path)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "latestbackup",
            title: "Latest Backup",
            category: .snapshots,
            summary: "Print the latest backup path for this Mac.",
            usage: "tmutil latestbackup [-m] [-t] [-d mount_point]",
            options: [
                TimeMachineCommandOption(id: "machine", label: "Machine directory", help: "Print the machine directory.", arguments: ["-m"]),
                TimeMachineCommandOption(id: "timestamp", label: "Timestamp only", help: "Print the timestamp only.", arguments: ["-t"]),
                TimeMachineCommandOption(id: "destination", label: "Destination mount point", help: "Limit to a destination mount point.", arguments: ["-d"], valueKind: .value(.path), placeholder: "/Volumes/Backup Disk")
            ]
        ),
        TimeMachineCommandDefinition(
            id: "listbackups",
            title: "List Backups",
            category: .snapshots,
            summary: "Print completed backup paths for this Mac.",
            usage: "tmutil listbackups [-m] [-t] [-d mount_point]",
            options: [
                TimeMachineCommandOption(id: "machine", label: "Machine directory", help: "Print machine directories.", arguments: ["-m"]),
                TimeMachineCommandOption(id: "timestamp", label: "Timestamp only", help: "Print timestamps only.", arguments: ["-t"]),
                TimeMachineCommandOption(id: "destination", label: "Destination mount point", help: "Limit to a destination mount point.", arguments: ["-d"], valueKind: .value(.path), placeholder: "/Volumes/Backup Disk")
            ]
        ),
        TimeMachineCommandDefinition(
            id: "machinedirectory",
            title: "Machine Directory",
            category: .snapshots,
            summary: "Print the current machine directory for this Mac.",
            usage: "tmutil machinedirectory"
        ),
        TimeMachineCommandDefinition(
            id: "restore",
            title: "Restore",
            category: .restoreCompare,
            summary: "Restore one or more snapshot items to a destination.",
            usage: "tmutil restore [-v] src ... dst",
            options: [
                TimeMachineCommandOption(id: "verbose", label: "Verbose", help: "Print more restore details.", arguments: ["-v"])
            ],
            arguments: [
                TimeMachineCommandArgument(id: "sources", label: "Source Paths", help: "Snapshot source paths, one per line.", placeholder: "/Volumes/Backup/.../file.txt", kind: .paths),
                TimeMachineCommandArgument(id: "destination", label: "Destination", help: "Restore destination path.", placeholder: "/Users/me/Desktop/Restored", kind: .path)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "compare",
            title: "Compare",
            category: .restoreCompare,
            summary: "Compare the Mac with a backup, or compare two paths.",
            usage: "tmutil compare [-@acdefghlmnstuEX] [-D depth] [-I name] [snapshot_path | path1 path2]",
            options: [
                TimeMachineCommandOption(id: "all", label: "All metadata", help: "Compare all supported metadata.", arguments: ["-a"]),
                TimeMachineCommandOption(id: "xattrs", label: "Extended attributes", help: "Compare extended attributes.", arguments: ["-@"]),
                TimeMachineCommandOption(id: "acl", label: "ACLs", help: "Compare access control lists.", arguments: ["-e"]),
                TimeMachineCommandOption(id: "size", label: "Sizes", help: "Compare file sizes.", arguments: ["-s"]),
                TimeMachineCommandOption(id: "mode", label: "Modes", help: "Compare file modes.", arguments: ["-m"]),
                TimeMachineCommandOption(id: "uid", label: "UIDs", help: "Compare user IDs.", arguments: ["-u"]),
                TimeMachineCommandOption(id: "gid", label: "GIDs", help: "Compare group IDs.", arguments: ["-g"]),
                TimeMachineCommandOption(id: "mtime", label: "Modification times", help: "Compare modification times.", arguments: ["-t"]),
                TimeMachineCommandOption(id: "data", label: "File data", help: "Compare file data forks.", arguments: ["-d"]),
                TimeMachineCommandOption(id: "noExclusions", label: "Ignore exclusions", help: "Do not account for exclusions.", arguments: ["-E"]),
                TimeMachineCommandOption(id: "xml", label: "XML output", help: "Print XML property list output.", arguments: ["-X"]),
                TimeMachineCommandOption(id: "depth", label: "Traversal depth", help: "Limit traversal depth.", arguments: ["-D"], valueKind: .value(.number), placeholder: "2"),
                TimeMachineCommandOption(id: "ignore", label: "Ignore name", help: "Ignore paths containing this component name.", arguments: ["-I"], valueKind: .value(.text), placeholder: "node_modules")
            ],
            arguments: [
                TimeMachineCommandArgument(id: "paths", label: "Optional Paths", help: "Leave blank, enter one snapshot path, or enter two paths on separate lines.", placeholder: "/Volumes/Backup/.../Latest", kind: .paths, isRequired: false)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "inheritbackup",
            title: "Inherit Backup",
            category: .adoption,
            summary: "Claim a machine directory or sparsebundle for this Mac.",
            usage: "tmutil inheritbackup machine_directory | sparse_bundle",
            requiresAdministrator: true,
            arguments: [
                TimeMachineCommandArgument(id: "item", label: "Machine Directory or Sparsebundle", help: "Existing backup history to claim.", placeholder: "/Volumes/Backup/Backups.backupdb/Old Mac", kind: .path)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "associatedisk",
            title: "Associate Disk",
            category: .adoption,
            summary: "Bind a source volume to an existing snapshot volume history.",
            usage: "tmutil associatedisk [-a] mount_point snapshot_volume",
            requiresAdministrator: true,
            options: [
                TimeMachineCommandOption(id: "all", label: "Apply to matching snapshots", help: "Associate all matching snapshot volumes in the same machine directory.", arguments: ["-a"])
            ],
            arguments: [
                TimeMachineCommandArgument(id: "mountPoint", label: "Mount Point", help: "Current source volume mount point.", placeholder: "/Volumes/MyDisk", kind: .path),
                TimeMachineCommandArgument(id: "snapshotVolume", label: "Snapshot Volume", help: "Snapshot volume path from backup history.", placeholder: "/Volumes/Backup/Backups.backupdb/Mac/Latest/MyDisk", kind: .path)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "calculatedrift",
            title: "Calculate Drift",
            category: .diagnostics,
            summary: "Analyze change between snapshots in a machine directory.",
            usage: "tmutil calculatedrift machine_directory",
            arguments: [
                TimeMachineCommandArgument(id: "machineDirectory", label: "Machine Directory", help: "Machine directory inside Backups.backupdb.", placeholder: "/Volumes/Backup/Backups.backupdb/Mac", kind: .path)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "uniquesize",
            title: "Unique Size",
            category: .diagnostics,
            summary: "Calculate data that only exists at the specified paths.",
            usage: "tmutil uniquesize path ...",
            arguments: [
                TimeMachineCommandArgument(id: "paths", label: "Paths", help: "One path per line.", placeholder: "/Volumes/Backup/.../Latest", kind: .paths)
            ]
        ),
        TimeMachineCommandDefinition(
            id: "verifychecksums",
            title: "Verify Checksums",
            category: .diagnostics,
            summary: "Verify checksums under a backup path.",
            usage: "tmutil verifychecksums path ...",
            arguments: [
                TimeMachineCommandArgument(id: "paths", label: "Paths", help: "One path per line.", placeholder: "/Volumes/Backup/.../Latest", kind: .paths)
            ]
        )
    ]
}
