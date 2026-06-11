import Foundation

extension AppStateStore {
    func scanNow() async {
        updateOperation(detail: "Scanning rules", progress: isScanAndApplyOperation ? 0.12 : nil)

        let validRules = rules.filter { RuleMatcher.validationIssue(for: $0) == nil }

        updateOperation(detail: "Searching scan roots", progress: isScanAndApplyOperation ? 0.20 : nil)
        let scanned = await Task.detached(priority: .userInitiated) { [settings, scanner] in
            scanner.scan(settings: settings, rules: validRules)
        }.value
        guard !Task.isCancelled else { return }

        updateOperation(detail: "Collecting path rules", progress: isScanAndApplyOperation ? 0.34 : nil)
        let pathCandidates = ScanCandidateBuilder.pathRuleCandidates(
            from: validRules,
            excludingScannedPaths: Set(scanned.map(\.0.path))
        )
        guard !Task.isCancelled else { return }

        updateOperation(detail: "Checking Time Machine status", progress: isScanAndApplyOperation ? 0.48 : nil)
        let allPaths = scanned.map(\.0.path) + pathCandidates.map(\.path)
        let exclusionStatuses = await Task.detached(priority: .userInitiated) { [timeMachine] in
            await ExclusionStatusChecker.statuses(for: allPaths, timeMachine: timeMachine)
        }.value
        guard !Task.isCancelled else { return }

        var nextMatches: [ScanMatch] = []

        for (candidate, rule) in scanned {
            let excluded = exclusionStatuses[candidate.path] ?? false
            nextMatches.append(
                ScanMatch(
                    path: candidate.path,
                    source: .rule(rule.name),
                    isDirectory: candidate.isDirectory,
                    isExcluded: excluded,
                    sizeBytes: candidate.sizeBytes,
                    isSelected: !excluded
                )
            )
        }

        for item in pathCandidates {
            let excluded = exclusionStatuses[item.path] ?? false
            nextMatches.append(
                ScanMatch(
                    path: item.path,
                    source: .rule(item.rule.name),
                    isDirectory: item.isDirectory,
                    isExcluded: excluded,
                    sizeBytes: nil,
                    isSelected: !excluded
                )
            )
        }

        matches = nextMatches.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        lastScanDate = Date()
        statusMessage = "Found \(matches.count) candidate exclusions"
        rulesStatusMessage = statusMessage
        if isScanAndApplyOperation {
            updateOperation(detail: "Found \(matches.count) candidate exclusions", progress: 0.58)
        }
    }

    @discardableResult
    func applySelectedMatches(refreshAfterApply: Bool = true) async -> Int {
        let targets = matches.filter { $0.isSelected && !$0.isExcluded }
        guard !targets.isEmpty else {
            statusMessage = "Nothing new to exclude"
            rulesStatusMessage = statusMessage
            if isScanAndApplyOperation {
                updateOperation(detail: "No new exclusions to apply", progress: 0.72)
            }
            return 0
        }

        var applied = 0
        var failures: [String] = []
        let progressUpdateStride = max(1, targets.count / 20)

        for (offset, target) in targets.enumerated() {
            guard !Task.isCancelled else {
                statusMessage = "Cancelled after applying \(applied) exclusions"
                rulesStatusMessage = statusMessage
                save()
                return applied
            }

            if isScanAndApplyOperation, offset == 0 || offset == targets.count - 1 || offset.isMultiple(of: progressUpdateStride) {
                let fraction = Double(offset) / Double(max(targets.count, 1))
                updateOperation(
                    detail: "Applying exclusion \(offset + 1) of \(targets.count)",
                    progress: 0.60 + min(fraction, 1) * 0.28
                )
            }

            let result = await Task.detached(priority: .userInitiated) { [timeMachine] in
                Result { try timeMachine.addExclusion(path: target.path) }
            }.value

            switch result {
            case .success(let commandResult) where commandResult.isSuccess:
                applied += 1
                appliedExclusions.removeAll { $0.path == target.path }
                appliedExclusions.append(
                    AppliedExclusion(path: target.path, sourceDescription: target.source.label)
                )
            default:
                failures.append(target.path)
            }
        }

        save()
        statusMessage = failures.isEmpty
            ? "Applied \(applied) exclusions"
            : "Applied \(applied), failed \(failures.count)."
        rulesStatusMessage = statusMessage
        if isScanAndApplyOperation {
            updateOperation(detail: "Applied \(applied) exclusions", progress: 0.88)
        } else if refreshAfterApply {
            await scanNow()
        }
        return applied
    }
}
