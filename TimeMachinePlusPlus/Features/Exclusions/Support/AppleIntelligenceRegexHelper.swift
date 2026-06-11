import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceRegexHelper {
    static var isSupportedOnCurrentOS: Bool {
        guard #available(macOS 26.0, *) else { return false }
        #if canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }

    static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        #if canImport(FoundationModels)
        return FoundationModelsRegexHelper.isAvailable
        #else
        return false
        #endif
    }

    static var availabilityMessage: String {
        guard #available(macOS 26.0, *) else {
            return "Apple Intelligence regex help requires macOS 26 or later."
        }
        #if canImport(FoundationModels)
        return FoundationModelsRegexHelper.availabilityMessage
        #else
        return "Apple Intelligence regex help requires an SDK with FoundationModels."
        #endif
    }

    static func generateRegex(for request: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw RegexGenerationError.unavailable("Apple Intelligence regex help requires macOS 26 or later.")
        }
        #if canImport(FoundationModels)
        return try await FoundationModelsRegexHelper.generateRegex(for: request)
        #else
        throw RegexGenerationError.unavailable("Apple Intelligence regex help requires an SDK with FoundationModels.")
        #endif
    }

    enum RegexGenerationError: LocalizedError {
        case unavailable(String)
        case emptyRequest
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let message):
                message
            case .emptyRequest:
                "Describe what the regex should match."
            case .invalidResponse(let message):
                message
            }
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelsRegexHelper {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    static var availabilityMessage: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Apple Intelligence is available."
        case .unavailable(.deviceNotEligible):
            return "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to use regex help."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing its on-device model. Try again later."
        case .unavailable:
            return "Apple Intelligence is not available right now."
        }
    }

    static func generateRegex(for request: String) async throws -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRequest.isEmpty else {
            throw AppleIntelligenceRegexHelper.RegexGenerationError.emptyRequest
        }
        guard isAvailable else {
            throw AppleIntelligenceRegexHelper.RegexGenerationError.unavailable(availabilityMessage)
        }

        let session = LanguageModelSession(instructions: """
        You generate macOS NSRegularExpression-compatible regex patterns for Time Machine exclusion rules.
        Return only the regex pattern. Do not wrap it in quotes, markdown, slashes, explanations, or prose.
        Prefer concise, anchored patterns when the request describes a path suffix or exact filename.
        Avoid constructs unsupported by NSRegularExpression.
        """)
        let response = try await session.respond(to: prompt(for: trimmedRequest))
        let pattern = sanitizedPattern(from: String(describing: response.content))

        if let validationIssue = RegexValidator.validateWithSuggestion(pattern) {
            throw AppleIntelligenceRegexHelper.RegexGenerationError.invalidResponse(
                "Apple Intelligence returned an invalid regex: \(validationIssue.message)"
            )
        }

        return pattern
    }

    private static func prompt(for request: String) -> String {
        return """
        Request: \(request)

        Create one complete regex pattern for matching filesystem paths or names to exclude from Time Machine backups.
        Return only the regex pattern.
        """
    }

    private static func sanitizedPattern(from response: String) -> String {
        var pattern = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if pattern.hasPrefix("```") {
            pattern = pattern
                .replacingOccurrences(of: "```regex", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1 {
            pattern.removeFirst()
            pattern.removeLast()
        }

        if pattern.hasPrefix("\"") && pattern.hasSuffix("\"") && pattern.count > 1 {
            pattern.removeFirst()
            pattern.removeLast()
        }

        return pattern
    }
}
#endif
