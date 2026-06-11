import Foundation

enum AppUpdateStatus: String, Codable, Equatable {
    case idle
    case checking
    case available
    case downloading
    case readyToInstall
    case installing
    case upToDate
    case failed

    var menuBarImage: String {
        switch self {
        case .checking, .available, .downloading, .installing:
            return "MenuIcon_Update"
        case .readyToInstall:
            return "MenuIcon_Update"
        case .idle, .upToDate, .failed:
            return "MenuIcon"
        }
    }

    var settingsIcon: String {
        switch self {
        case .idle, .upToDate:
            return "checkmark.circle"
        case .checking, .installing:
            return "arrow.triangle.2.circlepath"
        case .available, .downloading:
            return "arrow.down.circle"
        case .readyToInstall:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

enum AppBuildInfo {
    static var displayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

enum AppUpdateNotificationPolicy {
    static func shouldNotify(version: String, lastNotifiedVersion: String?) -> Bool {
        lastNotifiedVersion != version
    }
}

struct GitHubReleaseMetadata: Decodable, Equatable {
    let name: String
    let tagName: String
    let body: String
    let htmlURL: URL
    let isPrerelease: Bool
    let assets: [Asset]

    var displayName: String {
        name.isEmpty ? tagName : name
    }

    var version: String {
        AppVersionComparator.normalizedVersion(tagName)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case isPrerelease = "prerelease"
        case assets
    }

    struct Asset: Decodable, Equatable {
        let name: String
        let contentType: String

        enum CodingKeys: String, CodingKey {
            case name
            case contentType = "content_type"
        }
    }
}

enum AppVersionComparator {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .trimmingPrefix("V")
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftComponent = index < left.count ? left[index] : 0
            let rightComponent = index < right.count ? right[index] : 0

            if leftComponent > rightComponent { return .orderedDescending }
            if leftComponent < rightComponent { return .orderedAscending }
        }

        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: "-", maxSplits: 1)
            .first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
