import ArgumentParser
import Foundation

@main
struct ScionCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scion",
        abstract: "電子決済手段（JPYC/USDC）取引管理ツール",
        subcommands: [
            AccountCommand.self,
            AddCommand.self,
            HoldingsCommand.self,
            PnLCommand.self,
            HistoryCommand.self,
        ]
    )

    mutating func run() async throws {
        let shell = InteractiveShell(executablePath: CommandLine.arguments[0])
        try await shell.run()
    }
}
