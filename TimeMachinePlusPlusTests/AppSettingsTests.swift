import XCTest
@testable import TimeMachinePlusPlus

final class AppSettingsTests: XCTestCase {
    func testBackgroundHelperDefaultsToDaily() {
        XCTAssertEqual(AppSettings.defaults.scanIntervalMinutes, AppSettings.dailyScanIntervalMinutes)
    }

    func testQuickPreviewLimitDefaultsToTwentyFive() {
        XCTAssertEqual(AppSettings.defaults.previewResultLimit, 25)
    }

    func testAutomaticUpdateChecksDefaultToOn() {
        XCTAssertTrue(AppSettings.defaults.automaticallyChecksForUpdates)
    }

    func testSettingsDecodeOldStateWithoutNewSettings() throws {
        let json = """
        {
          "scanRoots": ["/Users/me"],
          "backgroundScanningEnabled": true,
          "scanIntervalMinutes": 1440,
          "maxDepth": 7
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.previewResultLimit, AppSettings.defaultPreviewResultLimit)
        XCTAssertTrue(settings.automaticallyChecksForUpdates)
    }
}
