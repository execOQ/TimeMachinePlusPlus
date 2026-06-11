import Foundation

enum ExclusionStatusChecker {
    private static let defaultConcurrencyLimit = 6

    static func statuses(
        for paths: [String],
        timeMachine: TimeMachineClient,
        concurrencyLimit: Int = defaultConcurrencyLimit
    ) async -> [String: Bool] {
        guard !paths.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, Bool).self) { group in
            let limit = min(max(concurrencyLimit, 1), paths.count)
            var nextIndex = 0
            var statuses: [String: Bool] = [:]

            func enqueueNext() {
                guard nextIndex < paths.count else { return }
                let path = paths[nextIndex]
                nextIndex += 1
                group.addTask {
                    let excluded = (try? timeMachine.isExcluded(path: path)) ?? false
                    return (path, excluded)
                }
            }

            for _ in 0..<limit {
                enqueueNext()
            }

            while let (path, excluded) = await group.next() {
                statuses[path] = excluded
                enqueueNext()
            }

            return statuses
        }
    }
}
