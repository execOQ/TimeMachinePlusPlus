import Foundation

enum Formatters {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func fileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unknown" }
        return Self.bytes.string(fromByteCount: bytes)
    }
}
