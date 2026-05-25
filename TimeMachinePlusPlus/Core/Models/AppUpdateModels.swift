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

    var menuBarSystemImage: String {
        switch self {
        case .checking, .available, .downloading, .installing:
            return "arrow.triangle.2.circlepath"
        case .readyToInstall:
            return "arrow.down.circle.fill"
        case .idle, .upToDate, .failed:
            return "clock.arrow.circlepath"
        }
    }
}

enum AppBuildInfo {
    static var displayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }
}

enum AppUpdateNotificationPolicy {
    static func shouldNotify(version: String, lastNotifiedVersion: String?) -> Bool {
        lastNotifiedVersion != version
    }
}
