import Foundation

enum TimeMachineCommandCategory: String, CaseIterable, Identifiable {
    case backups = "Backups"
    case destinations = "Destinations"
    case exclusions = "Exclusions"
    case snapshots = "Snapshots"
    case restoreCompare = "Restore & Compare"
    case adoption = "Adoption"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }
}

enum TimeMachineCommandInputKind: Hashable {
    case text
    case path
    case paths
    case number
}

struct TimeMachineCommandOption: Identifiable, Hashable {
    enum ValueKind: Hashable {
        case flag
        case value(TimeMachineCommandInputKind)
    }

    var id: String
    var label: String
    var help: String
    var arguments: [String]
    var valueKind: ValueKind
    var placeholder: String

    init(
        id: String,
        label: String,
        help: String,
        arguments: [String],
        valueKind: ValueKind = .flag,
        placeholder: String = ""
    ) {
        self.id = id
        self.label = label
        self.help = help
        self.arguments = arguments
        self.valueKind = valueKind
        self.placeholder = placeholder
    }
}

struct TimeMachineCommandArgument: Identifiable, Hashable {
    var id: String
    var label: String
    var help: String
    var placeholder: String
    var kind: TimeMachineCommandInputKind
    var isRequired: Bool

    init(
        id: String,
        label: String,
        help: String,
        placeholder: String,
        kind: TimeMachineCommandInputKind = .text,
        isRequired: Bool = true
    ) {
        self.id = id
        self.label = label
        self.help = help
        self.placeholder = placeholder
        self.kind = kind
        self.isRequired = isRequired
    }
}

struct TimeMachineCommandDefinition: Identifiable, Hashable {
    var id: String
    var title: String
    var verb: String
    var category: TimeMachineCommandCategory
    var summary: String
    var usage: String
    var requiresAdministrator: Bool
    var isDestructive: Bool
    var options: [TimeMachineCommandOption]
    var arguments: [TimeMachineCommandArgument]

    init(
        id: String,
        title: String,
        verb: String? = nil,
        category: TimeMachineCommandCategory,
        summary: String,
        usage: String,
        requiresAdministrator: Bool = false,
        isDestructive: Bool = false,
        options: [TimeMachineCommandOption] = [],
        arguments: [TimeMachineCommandArgument] = []
    ) {
        self.id = id
        self.title = title
        self.verb = verb ?? id
        self.category = category
        self.summary = summary
        self.usage = usage
        self.requiresAdministrator = requiresAdministrator
        self.isDestructive = isDestructive
        self.options = options
        self.arguments = arguments
    }
}

struct TimeMachineCommandForm: Equatable {
    var selectedOptions: Set<String> = []
    var optionValues: [String: String] = [:]
    var argumentValues: [String: String] = [:]
    var runAsAdministrator = false
}

enum TimeMachineCommandBuildError: LocalizedError, Equatable {
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let label):
            return "Enter \(label) before running this command."
        }
    }
}

enum TimeMachineCommandBuilder {
    static func arguments(for definition: TimeMachineCommandDefinition, form: TimeMachineCommandForm) throws -> [String] {
        var arguments = [definition.verb]

        for option in definition.options where form.selectedOptions.contains(option.id) {
            arguments.append(contentsOf: option.arguments)

            if case .value(let kind) = option.valueKind {
                let values = parsedValues(form.optionValues[option.id] ?? "", kind: kind)
                guard !values.isEmpty else { throw TimeMachineCommandBuildError.missingValue(option.label) }
                arguments.append(contentsOf: values)
            }
        }

        for argument in definition.arguments {
            let values = parsedValues(form.argumentValues[argument.id] ?? "", kind: argument.kind)
            if argument.isRequired, values.isEmpty {
                throw TimeMachineCommandBuildError.missingValue(argument.label)
            }
            arguments.append(contentsOf: values)
        }

        return arguments
    }

    static func previewCommand(for definition: TimeMachineCommandDefinition, form: TimeMachineCommandForm) -> String {
        do {
            return try shellCommand(arguments: arguments(for: definition, form: form))
        } catch {
            return shellCommand(arguments: [definition.verb])
        }
    }

    static func shellCommand(arguments: [String]) -> String {
        (["tmutil"] + arguments).map(quoteForShell).joined(separator: " ")
    }

    private static func parsedValues(_ rawValue: String, kind: TimeMachineCommandInputKind) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        switch kind {
        case .paths:
            return trimmed
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .text, .path, .number:
            return [trimmed]
        }
    }

    private static func quoteForShell(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-./:=,@%")
        if value.rangeOfCharacter(from: safeCharacters.inverted) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
