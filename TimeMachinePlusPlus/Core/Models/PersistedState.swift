import Foundation

struct PersistedState: Codable {
    var rules: [RegexRule]
    var manualExclusions: [ManualExclusion]
    var appliedExclusions: [AppliedExclusion]
    var settings: AppSettings
    var snapshotSizeCache: [String: Int64]
    var lastHelperScanDate: Date?
    var lastHelperScannedItemCount: Int
    var lastHelperAddedExclusionCount: Int
    var lastUpdateCheckDate: Date?
    var lastNotifiedUpdateVersion: String?

    private enum CodingKeys: String, CodingKey {
        case rules, manualExclusions, appliedExclusions, settings, snapshotSizeCache
        case lastHelperScanDate, lastHelperScannedItemCount, lastHelperAddedExclusionCount
        case lastUpdateCheckDate
        case lastNotifiedUpdateVersion
    }

    init(
        rules: [RegexRule],
        manualExclusions: [ManualExclusion],
        appliedExclusions: [AppliedExclusion],
        settings: AppSettings,
        snapshotSizeCache: [String: Int64] = [:],
        lastHelperScanDate: Date? = nil,
        lastHelperScannedItemCount: Int = 0,
        lastHelperAddedExclusionCount: Int = 0,
        lastUpdateCheckDate: Date? = nil,
        lastNotifiedUpdateVersion: String? = nil
    ) {
        self.rules = rules
        self.manualExclusions = manualExclusions
        self.appliedExclusions = appliedExclusions
        self.settings = settings
        self.snapshotSizeCache = snapshotSizeCache
        self.lastHelperScanDate = lastHelperScanDate
        self.lastHelperScannedItemCount = lastHelperScannedItemCount
        self.lastHelperAddedExclusionCount = lastHelperAddedExclusionCount
        self.lastUpdateCheckDate = lastUpdateCheckDate
        self.lastNotifiedUpdateVersion = lastNotifiedUpdateVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decode([RegexRule].self, forKey: .rules)
        manualExclusions = try c.decodeIfPresent([ManualExclusion].self, forKey: .manualExclusions) ?? []
        appliedExclusions = try c.decode([AppliedExclusion].self, forKey: .appliedExclusions)
        settings = try c.decode(AppSettings.self, forKey: .settings)
        snapshotSizeCache = try c.decodeIfPresent([String: Int64].self, forKey: .snapshotSizeCache) ?? [:]
        lastHelperScanDate = try c.decodeIfPresent(Date.self, forKey: .lastHelperScanDate)
        lastHelperScannedItemCount = try c.decodeIfPresent(Int.self, forKey: .lastHelperScannedItemCount) ?? 0
        lastHelperAddedExclusionCount = try c.decodeIfPresent(Int.self, forKey: .lastHelperAddedExclusionCount) ?? 0
        lastUpdateCheckDate = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheckDate)
        lastNotifiedUpdateVersion = try c.decodeIfPresent(String.self, forKey: .lastNotifiedUpdateVersion)
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
