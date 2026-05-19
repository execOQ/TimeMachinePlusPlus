import Foundation

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
