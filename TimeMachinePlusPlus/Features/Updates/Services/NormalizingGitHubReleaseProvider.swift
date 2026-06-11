import AppUpdater
import Foundation

struct NormalizingGitHubReleaseProvider: ReleaseProvider {
    private static let stableDownloadAssetName = "TimeMachine++.zip"
    private static let appUpdaterReleasePrefix = "TimeMachine++"

    func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)

        let normalizedData = try Self.normalizedReleaseData(from: data)
        return try JSONDecoder().decode([Release].self, from: normalizedData)
    }

    func download(asset: Release.Asset, to saveLocation: URL, proxy: URLRequestProxy?) async throws -> AsyncThrowingStream<DownloadingState, Error> {
        AsyncThrowingStream { continuation in
            let task = URLSession.shared.downloadTask(with: asset.downloadUrl) { temporaryURL, response, error in
                do {
                    if let error {
                        throw error
                    }

                    guard let temporaryURL, let response else {
                        throw URLError(.badServerResponse)
                    }

                    try validate(response: response, data: nil)
                    try FileManager.default.moveItem(at: temporaryURL, to: saveLocation)
                    continuation.yield(.finished(saveLocation: saveLocation, response: response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.yield(.progress(task.progress))
            task.resume()

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func fetchAssetData(asset: Release.Asset, proxy: URLRequestProxy?) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: asset.downloadUrl)
        try validate(response: response, data: data)
        return data
    }

    static func normalizedReleaseData(from data: Data) throws -> Data {
        let json = try JSONSerialization.jsonObject(with: data)
        guard var releases = json as? [[String: Any]] else { return data }

        releases = releases.map { release in
            var release = release
            let normalizedTagName: String?
            if let tagName = release["tag_name"] as? String {
                let normalized = AppVersionComparator.normalizedVersion(tagName)
                release["tag_name"] = normalized
                normalizedTagName = normalized
            } else {
                normalizedTagName = nil
            }

            if let normalizedTagName {
                release["assets"] = normalizedAssets(release["assets"], tagName: normalizedTagName)
            }
            return release
        }

        return try JSONSerialization.data(withJSONObject: releases)
    }

    private static func normalizedAssets(_ assets: Any?, tagName: String) -> Any? {
        guard let assets = assets as? [[String: Any]] else { return assets }

        return assets.map { asset in
            var asset = asset
            if let name = asset["name"] as? String, name == stableDownloadAssetName {
                asset["name"] = "\(appUpdaterReleasePrefix)-\(tagName).zip"
            }
            return asset
        }
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLSessionError.badStatusCode(httpResponse.statusCode, data)
        }
    }
}

private enum URLSessionError: LocalizedError {
    case badStatusCode(Int, Data?)

    var errorDescription: String? {
        switch self {
        case .badStatusCode(let statusCode, _):
            return "GitHub returned HTTP \(statusCode)."
        }
    }
}
