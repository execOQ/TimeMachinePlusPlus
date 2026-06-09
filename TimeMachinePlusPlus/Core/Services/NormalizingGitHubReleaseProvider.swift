import AppUpdater
import Foundation

struct NormalizingGitHubReleaseProvider: ReleaseProvider {
    func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)

        let normalizedData = try normalizeReleaseTags(in: data)
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

    private func normalizeReleaseTags(in data: Data) throws -> Data {
        let json = try JSONSerialization.jsonObject(with: data)
        guard var releases = json as? [[String: Any]] else { return data }

        releases = releases.map { release in
            var release = release
            if let tagName = release["tag_name"] as? String {
                release["tag_name"] = AppVersionComparator.normalizedVersion(tagName)
            }
            return release
        }

        return try JSONSerialization.data(withJSONObject: releases)
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
