struct RulePreviewResult: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var isDirectory: Bool
    var sizeBytes: Int64?
}
