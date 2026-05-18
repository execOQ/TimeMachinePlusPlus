import Foundation

struct FileSystemScanner {
    struct Candidate: Hashable {
        var path: String
        var isDirectory: Bool
        var sizeBytes: Int64?
    }

    func scan(settings: AppSettings, rules: [RegexRule]) -> [Candidate: RegexRule] {
        let enabledRules = rules.filter { $0.isEnabled && $0.kind != .specific && RuleMatcher.validationError(for: $0) == nil }

        guard !enabledRules.isEmpty else { return [:] }

        var matches: [Candidate: RegexRule] = [:]
        let fileManager = FileManager.default

        for root in settings.scanRoots where fileManager.fileExists(atPath: root) {
            let rootURL = URL(fileURLWithPath: root)
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                let depth = relativeDepth(of: url, from: rootURL)
                if depth > settings.maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                let values = try? url.resourceValues(forKeys: Set(keys))
                let isDirectory = values?.isDirectory ?? false
                let path = url.standardizedFileURL.path

                for rule in enabledRules {
                    guard isDirectory || rule.includeFiles else { continue }
                    guard RuleMatcher.matches(path: path, isDirectory: isDirectory, rule: rule) else { continue }

                    let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                    matches[Candidate(path: path, isDirectory: isDirectory, sizeBytes: size > 0 ? size : nil)] = rule
                    if isDirectory {
                        enumerator.skipDescendants()
                    }
                    break
                }
            }
        }

        return matches
    }

    private func relativeDepth(of url: URL, from root: URL) -> Int {
        let relative = url.path.replacingOccurrences(of: root.path, with: "")
        return relative.split(separator: "/").count
    }
}
