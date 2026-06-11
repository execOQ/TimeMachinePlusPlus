import Foundation

struct PersistedState: Codable {
    var rules: [RegexRule]
    var manualExclusions: [ManualExclusion]
    var appliedExclusions: [AppliedExclusion]
    var settings: AppSettings
    var lastHelperScanDate: Date?
    var lastHelperScannedItemCount: Int
    var lastHelperAddedExclusionCount: Int
    var lastUpdateCheckDate: Date?
    var lastNotifiedUpdateVersion: String?

    private enum CodingKeys: String, CodingKey {
        case rules, manualExclusions, appliedExclusions, settings
        case lastHelperScanDate, lastHelperScannedItemCount, lastHelperAddedExclusionCount
        case lastUpdateCheckDate
        case lastNotifiedUpdateVersion
    }

    init(
        rules: [RegexRule],
        manualExclusions: [ManualExclusion],
        appliedExclusions: [AppliedExclusion],
        settings: AppSettings,
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
        lastHelperScanDate = try c.decodeIfPresent(Date.self, forKey: .lastHelperScanDate)
        lastHelperScannedItemCount = try c.decodeIfPresent(Int.self, forKey: .lastHelperScannedItemCount) ?? 0
        lastHelperAddedExclusionCount = try c.decodeIfPresent(Int.self, forKey: .lastHelperAddedExclusionCount) ?? 0
        lastUpdateCheckDate = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheckDate)
        lastNotifiedUpdateVersion = try c.decodeIfPresent(String.self, forKey: .lastNotifiedUpdateVersion)
    }

    static var defaults: PersistedState {
        PersistedState(
            rules: RuleTemplate.defaults.map(\.rule),
            manualExclusions: [],
            appliedExclusions: [],
            settings: .defaults
        )
    }
}
