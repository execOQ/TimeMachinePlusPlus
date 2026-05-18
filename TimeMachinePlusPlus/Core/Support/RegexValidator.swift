import Foundation

enum RegexValidator {
    static func validate(_ pattern: String) -> String? {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Pattern cannot be empty."
        }

        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
