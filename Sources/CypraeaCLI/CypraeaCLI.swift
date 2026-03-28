import ArgumentParser
import Foundation

@main
struct CypraeaCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cypraea",
        abstract: "電子決済手段（JPYC/USDC）取引管理ツール",
        subcommands: [
            AccountCommand.self,
            AddCommand.self,
            HoldingsCommand.self,
            PnLCommand.self,
            HistoryCommand.self,
        ]
    )
}
