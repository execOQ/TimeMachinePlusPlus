import Foundation

enum RuleKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case folderName
    case gitignore
    case regex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folderName: return "Folder"
        case .gitignore: return "Git-like"
        case .regex: return "Regex"
        }
    }

    var placeholder: String {
        switch self {
        case .folderName: return "node_modules"
        case .gitignore: return "node_modules/"
        case .regex: return #"/node_modules($|/)"#
        }
    }

    var help: String {
        switch self {
        case .folderName:
            return "Type one or more folder names, separated by commas or new lines."
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
        kind: RuleKind = .folderName,
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
        pattern = try container.decode(String.self, forKey: .pattern)
        kind = try container.decodeIfPresent(RuleKind.self, forKey: .kind) ?? .regex
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        includeFiles = try container.decode(Bool.self, forKey: .includeFiles)
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
        case manual

        var label: String {
            switch self {
            case .rule(let name):
                return name
            case .manual:
                return "Manual"
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

    static var defaults: PersistedState {
        PersistedState(
            rules: [
                RegexRule(name: "Node dependencies", pattern: "node_modules", kind: .folderName),
                RegexRule(name: "Python virtualenvs", pattern: ".venv, venv", kind: .folderName),
                RegexRule(name: "Xcode DerivedData", pattern: "DerivedData", kind: .folderName),
                RegexRule(name: "Ruby vendor bundle", pattern: "vendor/bundle/", kind: .gitignore),
                RegexRule(name: "Build directories", pattern: "build/\n.build/\ndist/", kind: .gitignore)
            ],
            manualExclusions: [],
            appliedExclusions: [],
            settings: .defaults
        )
    }
}
