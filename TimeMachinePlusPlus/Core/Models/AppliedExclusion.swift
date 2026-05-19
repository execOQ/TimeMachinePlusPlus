import Foundation

struct AppliedExclusion: Identifiable, Codable, Hashable {
    var id: UUID
    var path: String
    var appliedAt: Date
    var sourceDescription: String

    init(id: UUID = UUID(), path: String, appliedAt: Date = Date(), sourceDescription: String) {
        self.id = id
        self.path = path
        self.appliedAt = appliedAt
        self.sourceDescription = sourceDescription
    }
}
