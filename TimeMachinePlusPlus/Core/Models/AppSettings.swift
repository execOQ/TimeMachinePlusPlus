import Foundation

struct AppSettings: Codable, Hashable {
    static let dailyScanIntervalMinutes = 24 * 60
    static let defaultPreviewResultLimit = 25

    var scanRoots: [String]
    var startButtonStartsBackup: Bool
    var backgroundScanningEnabled: Bool
    var scanIntervalMinutes: Int
    var maxDepth: Int
    var previewResultLimit: Int

    static var defaults: AppSettings {
        AppSettings(
            scanRoots: [FileManager.default.homeDirectoryForCurrentUser.path],
            startButtonStartsBackup: true,
            backgroundScanningEnabled: true,
            scanIntervalMinutes: dailyScanIntervalMinutes,
            maxDepth: 7,
            previewResultLimit: defaultPreviewResultLimit
        )
    }

    private enum CodingKeys: String, CodingKey {
        case scanRoots, startButtonStartsBackup, backgroundScanningEnabled, scanIntervalMinutes, maxDepth, previewResultLimit
    }

    init(
        scanRoots: [String],
        startButtonStartsBackup: Bool = true,
        backgroundScanningEnabled: Bool,
        scanIntervalMinutes: Int,
        maxDepth: Int,
        previewResultLimit: Int = defaultPreviewResultLimit
    ) {
        self.scanRoots = scanRoots
        self.startButtonStartsBackup = startButtonStartsBackup
        self.backgroundScanningEnabled = backgroundScanningEnabled
        self.scanIntervalMinutes = scanIntervalMinutes
        self.maxDepth = maxDepth
        self.previewResultLimit = previewResultLimit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scanRoots = try c.decode([String].self, forKey: .scanRoots)
        startButtonStartsBackup = try c.decodeIfPresent(Bool.self, forKey: .startButtonStartsBackup) ?? true
        backgroundScanningEnabled = try c.decode(Bool.self, forKey: .backgroundScanningEnabled)
        scanIntervalMinutes = try c.decode(Int.self, forKey: .scanIntervalMinutes)
        maxDepth = try c.decode(Int.self, forKey: .maxDepth)
        previewResultLimit = try c.decodeIfPresent(Int.self, forKey: .previewResultLimit) ?? Self.defaultPreviewResultLimit
    }
}
