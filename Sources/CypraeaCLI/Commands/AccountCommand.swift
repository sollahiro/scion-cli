import ArgumentParser
import Foundation

struct AccountCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "account",
        abstract: "アカウント管理",
        subcommands: [Add.self, List.self]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "アカウントを追加")

        @Option(name: .long, help: "種別: wallet / exchange / lendingPlatform")
        var type: String?

        @Option(name: .long, help: "ラベル（例: メインウォレット）")
        var label: String?

        @Option(name: .long, help: "チェーン（walletのみ）: ethereum / polygon / avalanche")
        var chain: String?

        @Option(name: .long, help: "アドレス（walletのみ）")
        var address: String?

        @Option(name: .long, help: "URL（exchange / lendingPlatform）")
        var url: String?

        @Option(name: .long, help: "コントラクトアドレス（lendingPlatformのみ）")
        var contract: String?

        mutating func run() async throws {
            let db = try DatabaseManager(path: DatabaseManager.defaultPath())
            let repo = AccountRepository(db: db)

            let resolvedType = try type ?? prompt("種別 (wallet / exchange / lendingPlatform): ")
            let resolvedLabel = try label ?? prompt("ラベル: ")

            let account = Account(
                id: UUID().uuidString,
                type: resolvedType,
                label: resolvedLabel,
                url: url,
                contractAddress: contract
            )
            try repo.insert(account)

            // wallet の場合は入金アドレスを追加
            if resolvedType == AccountType.wallet.rawValue {
                let resolvedChain = try chain ?? prompt("チェーン (ethereum / polygon / avalanche): ")
                let resolvedAddress = try address ?? prompt("アドレス: ")
                let depositAddr = DepositAddress(
                    id: UUID().uuidString,
                    accountId: account.id,
                    chain: resolvedChain,
                    address: resolvedAddress
                )
                try repo.insertDepositAddress(depositAddr)
            } else if resolvedType == AccountType.exchange.rawValue, address != nil || chain != nil {
                // exchange の入金アドレス（任意）
                let resolvedChain = try chain ?? prompt("入金アドレスのチェーン（スキップはEnter）: ")
                if !resolvedChain.isEmpty {
                    let resolvedAddress = try address ?? prompt("入金アドレス: ")
                    let depositAddr = DepositAddress(
                        id: UUID().uuidString,
                        accountId: account.id,
                        chain: resolvedChain,
                        address: resolvedAddress
                    )
                    try repo.insertDepositAddress(depositAddr)
                }
            }

            print("✓ アカウントを追加しました: \(resolvedLabel) (\(resolvedType))")
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "アカウント一覧")

        mutating func run() async throws {
            let db = try DatabaseManager(path: DatabaseManager.defaultPath())
            let repo = AccountRepository(db: db)
            let accounts = try repo.fetchAll()

            if accounts.isEmpty {
                print("アカウントが登録されていません")
                return
            }

            print("\(pad("ID", 36))  \(pad("種別", 16))  ラベル")
            print(String(repeating: "-", count: 70))
            for account in accounts {
                print("\(pad(account.id, 36))  \(pad(account.type, 16))  \(account.label)")
                let addrs = try repo.fetchDepositAddresses(accountId: account.id)
                for addr in addrs {
                    print("  \(pad(addr.chain, 16))  \(addr.address)")
                }
            }
        }
    }
}

func prompt(_ message: String) throws -> String {
    print(message, terminator: "")
    return readLine() ?? ""
}
