import Foundation

struct RegexRule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var pattern: String
    var kind: RuleKind
    var isEnabled: Bool
    var includeFiles: Bool
    var lastAIRequest: String
    var lastAIGeneratedPattern: String
    var lastAIGeneratedForRequest: String

    init(
        id: UUID = UUID(),
        name: String,
        pattern: String,
        kind: RuleKind = .pattern,
        isEnabled: Bool = true,
        includeFiles: Bool = false,
        lastAIRequest: String = "",
        lastAIGeneratedPattern: String = "",
        lastAIGeneratedForRequest: String = ""
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.kind = kind
        self.isEnabled = isEnabled
        self.includeFiles = includeFiles
        self.lastAIRequest = lastAIRequest
        self.lastAIGeneratedPattern = lastAIGeneratedPattern
        self.lastAIGeneratedForRequest = lastAIGeneratedForRequest
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case pattern
        case kind
        case isEnabled
        case includeFiles
        case lastAIRequest
        case lastAIGeneratedPattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        includeFiles = try container.decode(Bool.self, forKey: .includeFiles)
        lastAIRequest = (try? container.decodeIfPresent(String.self, forKey: .lastAIRequest)) ?? ""
        lastAIGeneratedPattern = (try? container.decodeIfPresent(String.self, forKey: .lastAIGeneratedPattern)) ?? ""
        lastAIGeneratedForRequest = ""

        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
        if rawKind == "folderName" {
            // Legacy migration: folder-name rules become path patterns (name/ format).
            kind = .pattern
            let rawPattern = try container.decode(String.self, forKey: .pattern)
            let tokens = rawPattern
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
                .filter { !$0.isEmpty }
            pattern = tokens.map { $0.contains("/") ? $0 : "\($0)/" }.joined(separator: "\n")
        } else {
            kind = RuleKind.fromPersistedRawValue(rawKind) ?? .regex
            pattern = try container.decode(String.self, forKey: .pattern)
        }
    }
}
