import CrabCLI
import CrabCore
import Darwin
import Foundation

do {
    let command = try CLIParser().parse(Array(CommandLine.arguments.dropFirst()))
    for line in try CLIApplication().execute(command) {
        print(line)
    }
} catch {
    fputs("crab: \(error)\n", stderr)
    fputs("Run 'crab --help' for usage.\n", stderr)
    exit(EXIT_FAILURE)
}
