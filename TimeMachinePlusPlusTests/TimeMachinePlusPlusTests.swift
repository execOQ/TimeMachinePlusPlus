import XCTest
@testable import TimeMachinePlusPlus

final class TimeMachinePlusPlusTests: XCTestCase {
    func testRegexValidatorRejectsInvalidPattern() {
        let validRule = RegexRule(name: "Regex", pattern: #"/node_modules($|/)"#, kind: .regex)
        let invalidRule = RegexRule(name: "Broken", pattern: "[", kind: .regex)

        XCTAssertNil(RuleMatcher.validationError(for: validRule))
        XCTAssertNotNil(RuleMatcher.validationError(for: invalidRule))
    }

    func testScannerMatchesPatternDirectoryAndSkipsDescendants() throws {
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("TimeMachinePlusPlusTests-\(UUID().uuidString)", isDirectory: true)
        let nodeModules = root.appendingPathComponent("project/node_modules", isDirectory: true)
        let nested = nodeModules.appendingPathComponent("left-pad", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = AppSettings(
            scanRoots: [root.path],
            scanIntervalMinutes: AppSettings.dailyScanIntervalMinutes,
            maxDepth: 8
        )
        let rule = RegexRule(name: "Node", pattern: "node_modules/", kind: .pattern)

        let matches = FileSystemScanner().scan(settings: settings, rules: [rule])

        XCTAssertTrue(matches.keys.contains { $0.path == nodeModules.path })
        XCTAssertFalse(matches.keys.contains { $0.path == nested.path })
    }

    func testScannerCanPreviewOneRuleOnly() throws {
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("TimeMachinePlusPlusRulePreview-\(UUID().uuidString)", isDirectory: true)
        let nodeModules = root.appendingPathComponent("project/node_modules", isDirectory: true)
        let build = root.appendingPathComponent("project/build", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = AppSettings(
            scanRoots: [root.path],
            scanIntervalMinutes: AppSettings.dailyScanIntervalMinutes,
            maxDepth: 8
        )

        let matches = FileSystemScanner().scan(
            settings: settings,
            rule: RegexRule(name: "Build", pattern: "build/", kind: .pattern)
        )

        XCTAssertEqual(matches.map(\.path), [build.path])
    }

    func testPersistedDefaultsIncludeUsefulTemplates() {
        let names = PersistedState.defaults.rules.map(\.name)
        XCTAssertTrue(names.contains("Node dependencies"))
        XCTAssertTrue(names.contains("Xcode DerivedData"))
    }

    func testCommonRuleTemplatesCoverDeveloperStacks() {
        let categories = Set(RuleTemplate.common.map(\.category))

        XCTAssertTrue(categories.isSuperset(of: ["Node", "Python", "Ruby", "Xcode", "Swift", "Java", "Rust", "Go", "General"]))
    }

    func testCommonRuleTemplatesAreValid() {
        for template in RuleTemplate.common {
            XCTAssertNil(RuleMatcher.validationError(for: template.rule), template.name)
        }
    }

    func testPatternRuleMatchesDirectoryPattern() {
        let rule = RegexRule(name: "Build", pattern: "build/", kind: .pattern)

        XCTAssertTrue(RuleMatcher.matches(path: "/Users/me/project/build", isDirectory: true, rule: rule))
        XCTAssertFalse(RuleMatcher.matches(path: "/Users/me/project/build.log", isDirectory: false, rule: rule))
    }

    func testPatternRuleAcceptsMultipleDirectoryPatterns() {
        let rule = RegexRule(name: "Virtualenvs", pattern: ".venv/\nvenv/", kind: .pattern)

        XCTAssertTrue(RuleMatcher.matches(path: "/Users/me/app/.venv", isDirectory: true, rule: rule))
        XCTAssertTrue(RuleMatcher.matches(path: "/Users/me/app/venv", isDirectory: true, rule: rule))
        XCTAssertFalse(RuleMatcher.matches(path: "/Users/me/app/venv.txt", isDirectory: false, rule: rule))
    }

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

    func testUpdateMenuBarIconReflectsUpdateState() {
        XCTAssertEqual(AppUpdateStatus.idle.menuBarSystemImage, "clock.arrow.circlepath")
        XCTAssertEqual(AppUpdateStatus.checking.menuBarSystemImage, "arrow.triangle.2.circlepath")
        XCTAssertEqual(AppUpdateStatus.downloading.menuBarSystemImage, "arrow.triangle.2.circlepath")
        XCTAssertEqual(AppUpdateStatus.readyToInstall.menuBarSystemImage, "arrow.down.circle.fill")
        XCTAssertEqual(AppUpdateStatus.failed.menuBarSystemImage, "clock.arrow.circlepath")
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
