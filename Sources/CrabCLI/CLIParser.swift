import CrabCore
import Foundation

public enum CLICommand: Equatable, Sendable {
    case help
    case validate(ruleFile: URL)
    case scan(rulesDirectory: URL, home: URL)
    case plan(
        rulesDirectory: URL,
        home: URL,
        output: URL,
        selectedRuleIDs: [RuleID]
    )
}

public enum CLIParseError: Error, Equatable, CustomStringConvertible {
    case unsupportedCommand(String)
    case missingValue(String)
    case missingRequiredOption(String)
    case unexpectedArgument(String)

    public var description: String {
        switch self {
        case let .unsupportedCommand(command):
            return "Unsupported command: \(command). This build is read-only."
        case let .missingValue(option):
            return "Option \(option) requires a value."
        case let .missingRequiredOption(option):
            return "Missing required option \(option)."
        case let .unexpectedArgument(argument):
            return "Unexpected argument: \(argument)."
        }
    }
}

public struct CLIParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String]) throws -> CLICommand {
        guard let command = arguments.first else {
            return .help
        }

        switch command {
        case "--help", "-h", "help":
            return .help
        case "rules":
            guard arguments.count == 3, arguments[1] == "validate" else {
                throw CLIParseError.unexpectedArgument(arguments.dropFirst().joined(separator: " "))
            }
            return .validate(ruleFile: URL(fileURLWithPath: arguments[2]))
        case "scan":
            let options = try parseOptions(Array(arguments.dropFirst()), permitsSelection: false)
            return .scan(
                rulesDirectory: try options.requiredURL("--rules"),
                home: try options.requiredURL("--home")
            )
        case "plan":
            let options = try parseOptions(Array(arguments.dropFirst()), permitsSelection: true)
            return .plan(
                rulesDirectory: try options.requiredURL("--rules"),
                home: try options.requiredURL("--home"),
                output: try options.requiredURL("--output"),
                selectedRuleIDs: options.selections.map(RuleID.init(rawValue:))
            )
        default:
            throw CLIParseError.unsupportedCommand(command)
        }
    }

    private func parseOptions(
        _ arguments: [String],
        permitsSelection: Bool
    ) throws -> ParsedOptions {
        var values: [String: String] = [:]
        var selections: [String] = []
        var index = 0

        while index < arguments.count {
            let option = arguments[index]
            guard ["--rules", "--home", "--output", "--select"].contains(option) else {
                throw CLIParseError.unexpectedArgument(option)
            }
            guard index + 1 < arguments.count else {
                throw CLIParseError.missingValue(option)
            }
            let value = arguments[index + 1]

            if option == "--select" {
                guard permitsSelection else {
                    throw CLIParseError.unexpectedArgument(option)
                }
                selections.append(value)
            } else {
                guard values[option] == nil else {
                    throw CLIParseError.unexpectedArgument("duplicate \(option)")
                }
                values[option] = value
            }
            index += 2
        }

        return ParsedOptions(values: values, selections: selections)
    }
}

private struct ParsedOptions {
    let values: [String: String]
    let selections: [String]

    func requiredURL(_ option: String) throws -> URL {
        guard let value = values[option], !value.isEmpty else {
            throw CLIParseError.missingRequiredOption(option)
        }
        return URL(fileURLWithPath: value)
    }
}
