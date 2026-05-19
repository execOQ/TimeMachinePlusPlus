import Foundation

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
