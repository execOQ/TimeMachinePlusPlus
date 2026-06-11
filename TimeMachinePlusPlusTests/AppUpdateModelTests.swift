import XCTest
import AppUpdater
@testable import TimeMachinePlusPlus

final class AppUpdateModelTests: XCTestCase {
    func testUpdateMenuBarIconReflectsUpdateState() {
        XCTAssertEqual(AppUpdateStatus.idle.menuBarImage, "MenuIcon")
        XCTAssertEqual(AppUpdateStatus.checking.menuBarImage, "MenuIcon_Update")
        XCTAssertEqual(AppUpdateStatus.downloading.menuBarImage, "MenuIcon_Update")
        XCTAssertEqual(AppUpdateStatus.readyToInstall.menuBarImage, "MenuIcon_Update")
        XCTAssertEqual(AppUpdateStatus.failed.menuBarImage, "MenuIcon")
    }

    func testUpdateNotificationDedupesSameRelease() {
        XCTAssertTrue(AppUpdateNotificationPolicy.shouldNotify(version: "0.2.0", lastNotifiedVersion: nil))
        XCTAssertTrue(AppUpdateNotificationPolicy.shouldNotify(version: "0.2.1", lastNotifiedVersion: "0.2.0"))
        XCTAssertFalse(AppUpdateNotificationPolicy.shouldNotify(version: "0.2.0", lastNotifiedVersion: "0.2.0"))
    }

    func testUpdateVersionComparisonHandlesGitHubTagPrefix() {
        XCTAssertTrue(AppVersionComparator.isNewer("v0.2.0", than: "0.1.0"))
        XCTAssertTrue(AppVersionComparator.isNewer("0.2.1", than: "v0.2.0"))
        XCTAssertFalse(AppVersionComparator.isNewer("v0.1.0", than: "0.1.0"))
    }

    func testGitHubReleaseMetadataDecodesReleaseAPIShape() throws {
        let json = """
        {
          "name": "0.2.0",
          "tag_name": "v0.2.0",
          "body": "Changes",
          "html_url": "https://github.com/execOQ/TimeMachinePlusPlus/releases/tag/v0.2.0",
          "prerelease": false,
          "assets": [
            {
              "name": "TimeMachine++.zip",
              "content_type": "application/zip"
            }
          ]
        }
        """

        let release = try JSONDecoder().decode(GitHubReleaseMetadata.self, from: Data(json.utf8))

        XCTAssertEqual(release.displayName, "0.2.0")
        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.assets.first?.name, "TimeMachine++.zip")
    }

    func testNormalizedReleaseDataMakesStableDownloadZipCompatibleWithAppUpdaterPrefix() throws {
        let json = """
        [
          {
            "name": "0.2.0",
            "tag_name": "v0.2.0",
            "body": "Changes",
            "html_url": "https://github.com/execOQ/TimeMachinePlusPlus/releases/tag/v0.2.0",
            "prerelease": false,
            "assets": [
              {
                "name": "TimeMachine++.zip",
                "browser_download_url": "https://github.com/execOQ/TimeMachinePlusPlus/releases/latest/download/TimeMachine++.zip",
                "content_type": "application/zip"
              }
            ]
          }
        ]
        """

        let normalizedData = try NormalizingGitHubReleaseProvider.normalizedReleaseData(from: Data(json.utf8))
        let release = try JSONDecoder().decode([Release].self, from: normalizedData).first

        XCTAssertEqual(release?.tagName.description, "0.2.0")
        XCTAssertEqual(release?.assets.first?.name, "TimeMachine++-0.2.0.zip")
        XCTAssertEqual(
            release?.assets.first?.downloadUrl,
            URL(string: "https://github.com/execOQ/TimeMachinePlusPlus/releases/latest/download/TimeMachine++.zip")
        )
    }
}
