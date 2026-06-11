import XCTest
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
          "name": "TimeMachine++ 0.2.0",
          "tag_name": "v0.2.0",
          "body": "Changes",
          "html_url": "https://github.com/execOQ/TimeMachineAdvanced/releases/tag/v0.2.0",
          "prerelease": false,
          "assets": [
            {
              "name": "TimeMachine++-0.2.0.zip",
              "content_type": "application/zip"
            }
          ]
        }
        """

        let release = try JSONDecoder().decode(GitHubReleaseMetadata.self, from: Data(json.utf8))

        XCTAssertEqual(release.displayName, "TimeMachine++ 0.2.0")
        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.assets.first?.name, "TimeMachine++-0.2.0.zip")
    }
}
