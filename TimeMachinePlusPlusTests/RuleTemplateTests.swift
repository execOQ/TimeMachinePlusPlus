import XCTest
@testable import TimeMachinePlusPlus

final class RuleTemplateTests: XCTestCase {
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
}
