import AppUpdater
import Foundation

extension AppStateStore {
    func capture(release: Release) {
        updateReleaseVersion = release.tagName.description
        updateReleaseName = release.name
        updateReleaseURL = URL(string: release.htmlUrl)

        updateReleaseNotesTask?.cancel()
        updateReleaseNotesTask = Task { @MainActor in
            let notes = await appUpdater.localizedChangelog(for: release) ?? release.body
            guard !Task.isCancelled else { return }
            updateReleaseNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func capture(metadata release: GitHubReleaseMetadata) {
        updateReleaseVersion = release.version
        updateReleaseName = release.displayName
        updateReleaseURL = release.htmlURL
        updateReleaseNotes = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchAvailableGitHubRelease() async -> GitHubReleaseMetadata? {
        do {
            let releases = try await fetchGitHubReleases()
                .filter { !$0.isPrerelease }
                .sorted { AppVersionComparator.isNewer($0.version, than: $1.version) }

            return releases.first {
                AppVersionComparator.isNewer($0.version, than: AppBuildInfo.version)
            }
        } catch {
            updateLastError = String(describing: error)
            return nil
        }
    }

    private func fetchGitHubReleases() async throws -> [GitHubReleaseMetadata] {
        let url = URL(string: "https://api.github.com/repos/execOQ/TimeMachinePlusPlus/releases")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([GitHubReleaseMetadata].self, from: data)
    }
}
