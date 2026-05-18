import Foundation

enum RuleKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case specific
    case gitignore
    case regex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .specific: return "Specific"
        case .gitignore: return "Git-like"
        case .regex: return "Regex"
        }
    }

    var placeholder: String {
        switch self {
        case .specific: return "/Users/you/path/to/file-or-folder"
        case .gitignore: return "node_modules/"
        case .regex: return #"/node_modules($|/)"#
        }
    }

    var help: String {
        switch self {
        case .specific:
            return "Exact absolute path to a file or folder. Use the browse button or type the path directly."
        case .gitignore:
            return "Use simple gitignore-style globs like node_modules/, **/.venv/, build/, or *.xcactivitylog."
        case .regex:
            return "Match the full absolute path with a regular expression."
        }
    }
}

struct RegexRule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var pattern: String
    var kind: RuleKind
    var isEnabled: Bool
    var includeFiles: Bool

    init(
        id: UUID = UUID(),
        name: String,
        pattern: String,
        kind: RuleKind = .gitignore,
        isEnabled: Bool = true,
        includeFiles: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.kind = kind
        self.isEnabled = isEnabled
        self.includeFiles = includeFiles
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case pattern
        case kind
        case isEnabled
        case includeFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        includeFiles = try container.decode(Bool.self, forKey: .includeFiles)

        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
        if rawKind == "folderName" {
            // Legacy migration: folder-name rules become gitignore patterns (name/ format)
            kind = .gitignore
            let rawPattern = try container.decode(String.self, forKey: .pattern)
            let tokens = rawPattern
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                .filter { !$0.isEmpty }
            pattern = tokens.map { $0.contains("/") ? $0 : "\($0)/" }.joined(separator: "\n")
        } else {
            kind = rawKind.flatMap(RuleKind.init(rawValue:)) ?? .regex
            pattern = try container.decode(String.self, forKey: .pattern)
        }
    }
}

struct ManualExclusion: Identifiable, Codable, Hashable {
    var id: UUID
    var path: String
    var isEnabled: Bool

    init(id: UUID = UUID(), path: String, isEnabled: Bool = true) {
        self.id = id
        self.path = path
        self.isEnabled = isEnabled
    }
}

struct AppSettings: Codable, Hashable {
    var scanRoots: [String]
    var backgroundScanningEnabled: Bool
    var scanIntervalMinutes: Int
    var maxDepth: Int

    static var defaults: AppSettings {
        AppSettings(
            scanRoots: [FileManager.default.homeDirectoryForCurrentUser.path],
            backgroundScanningEnabled: true,
            scanIntervalMinutes: 30,
            maxDepth: 7
        )
    }
}

struct AppliedExclusion: Identifiable, Codable, Hashable {
    var id: UUID
    var path: String
    var appliedAt: Date
    var sourceDescription: String

    init(id: UUID = UUID(), path: String, appliedAt: Date = Date(), sourceDescription: String) {
        self.id = id
        self.path = path
        self.appliedAt = appliedAt
        self.sourceDescription = sourceDescription
    }
}

struct ScanMatch: Identifiable, Hashable {
    enum Source: Hashable {
        case rule(String)

        var label: String {
            switch self {
            case .rule(let name):
                return name
            }
        }
    }

    var id: String { path }
    var path: String
    var source: Source
    var isDirectory: Bool
    var isExcluded: Bool
    var sizeBytes: Int64?
    var isSelected: Bool

    var plannedAction: String {
        isExcluded ? "Already excluded" : (isSelected ? "Will exclude" : "Skipped")
    }
}

struct PersistedState: Codable {
    var rules: [RegexRule]
    var manualExclusions: [ManualExclusion]
    var appliedExclusions: [AppliedExclusion]
    var settings: AppSettings
    var snapshotSizeCache: [String: Int64]

    private enum CodingKeys: String, CodingKey {
        case rules, manualExclusions, appliedExclusions, settings, snapshotSizeCache
    }

    init(rules: [RegexRule], manualExclusions: [ManualExclusion], appliedExclusions: [AppliedExclusion], settings: AppSettings, snapshotSizeCache: [String: Int64] = [:]) {
        self.rules = rules
        self.manualExclusions = manualExclusions
        self.appliedExclusions = appliedExclusions
        self.settings = settings
        self.snapshotSizeCache = snapshotSizeCache
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decode([RegexRule].self, forKey: .rules)
        manualExclusions = try c.decodeIfPresent([ManualExclusion].self, forKey: .manualExclusions) ?? []
        appliedExclusions = try c.decode([AppliedExclusion].self, forKey: .appliedExclusions)
        settings = try c.decode(AppSettings.self, forKey: .settings)
        snapshotSizeCache = try c.decodeIfPresent([String: Int64].self, forKey: .snapshotSizeCache) ?? [:]
    }

    static var defaults: PersistedState {
        PersistedState(
            rules: [
                RegexRule(name: "Node dependencies", pattern: "node_modules/", kind: .gitignore),
                RegexRule(name: "Python virtualenvs", pattern: ".venv/\nvenv/", kind: .gitignore),
                RegexRule(name: "Xcode DerivedData", pattern: "DerivedData/", kind: .gitignore),
                RegexRule(name: "Ruby vendor bundle", pattern: "vendor/bundle/", kind: .gitignore),
                RegexRule(name: "Build directories", pattern: "build/\n.build/\ndist/", kind: .gitignore)
            ],
            manualExclusions: [],
            appliedExclusions: [],
            settings: .defaults
        )
    }
}
