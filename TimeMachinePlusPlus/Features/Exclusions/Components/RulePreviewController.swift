import Foundation
import Observation

@MainActor
@Observable
final class RulePreviewController {
    var isLoading = false
    var results: [RulePreviewResult] = []
    var hasRequestedPreview = false

    @ObservationIgnored
    private var task: Task<Void, Never>?
    @ObservationIgnored
    private var key: RulePreviewKey?

    func expand(with rule: RegexRule) {
        key = RulePreviewKey(rule: rule)
    }

    func collapse() {
        cancel()
        isLoading = false
    }

    func registerRuleChange(_ rule: RegexRule) -> Bool {
        let nextKey = RulePreviewKey(rule: rule)
        guard nextKey != key else { return false }
        key = nextKey
        return true
    }

    func refresh(
        debounce: Bool,
        rule: RegexRule,
        validationIssue: RuleValidationIssue?,
        store: AppStateStore
    ) {
        task?.cancel()
        hasRequestedPreview = true

        guard rule.isEnabled, validationIssue == nil else {
            results = []
            isLoading = false
            return
        }

        let ruleSnapshot = rule
        isLoading = true
        task = Task { @MainActor [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
            }

            let results = await store.previewMatches(for: ruleSnapshot)
            guard !Task.isCancelled else { return }

            self?.results = results
            self?.isLoading = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
