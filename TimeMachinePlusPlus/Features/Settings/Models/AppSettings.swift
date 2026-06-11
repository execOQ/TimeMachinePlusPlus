import Foundation

struct AppSettings: Codable, Hashable {
    static let dailyScanIntervalMinutes = 24 * 60
    static let defaultPreviewResultLimit = 25

    var scanRoots: [String]
    var startButtonStartsBackup: Bool
    var scanIntervalMinutes: Int
    var maxDepth: Int
    var previewResultLimit: Int
    var automaticallyChecksForUpdates: Bool

    static var defaults: AppSettings {
        AppSettings(
            scanRoots: [FileManager.default.homeDirectoryForCurrentUser.path],
            startButtonStartsBackup: false,
            scanIntervalMinutes: dailyScanIntervalMinutes,
            maxDepth: 7,
            previewResultLimit: defaultPreviewResultLimit,
            automaticallyChecksForUpdates: true
        )
    }

    private enum CodingKeys: String, CodingKey {
        case scanRoots, startButtonStartsBackup, scanIntervalMinutes, maxDepth, previewResultLimit
        case automaticallyChecksForUpdates
    }

    init(
        scanRoots: [String],
        startButtonStartsBackup: Bool = false,
        scanIntervalMinutes: Int,
        maxDepth: Int,
        previewResultLimit: Int = defaultPreviewResultLimit,
        automaticallyChecksForUpdates: Bool = true
    ) {
        self.scanRoots = scanRoots
        self.startButtonStartsBackup = startButtonStartsBackup
        self.scanIntervalMinutes = scanIntervalMinutes
        self.maxDepth = maxDepth
        self.previewResultLimit = previewResultLimit
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scanRoots = try c.decode([String].self, forKey: .scanRoots)
        startButtonStartsBackup = try c.decodeIfPresent(Bool.self, forKey: .startButtonStartsBackup) ?? false
        scanIntervalMinutes = try c.decode(Int.self, forKey: .scanIntervalMinutes)
        maxDepth = try c.decode(Int.self, forKey: .maxDepth)
        previewResultLimit = try c.decodeIfPresent(Int.self, forKey: .previewResultLimit) ?? Self.defaultPreviewResultLimit
        automaticallyChecksForUpdates = try c.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? true
    }
}
