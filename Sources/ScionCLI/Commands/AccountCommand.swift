import ArgumentParser
import Foundation
import WalletConnectSign

struct AccountCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "account",
        abstract: "アカウント管理",
        subcommands: [Add.self, Connect.self, List.self, Delete.self]
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

    // MARK: - Connect (WalletConnect)

    struct Connect: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "connect",
            abstract: "WalletConnect でウォレットを接続・登録"
        )

        @Option(name: .long, help: "ラベル（省略可）")
        var label: String?

        @Option(name: .long, help: "WalletConnect Project ID（環境変数 WALLETCONNECT_PROJECT_ID でも設定可）")
        var projectId: String = ProcessInfo.processInfo.environment["WALLETCONNECT_PROJECT_ID"] ?? ""

        mutating func run() async throws {
            guard !projectId.isEmpty else {
                fputs("エラー: --project-id または環境変数 WALLETCONNECT_PROJECT_ID を設定してください\n", stderr)
                throw ExitCode.failure
            }

            let service = WalletConnectCLIService()
            service.configure(projectId: projectId)

            print("\nWalletConnect でウォレットを接続します...")
            print("接続URIを生成中...\n")

            let uri = try await service.generateURI()
            let uriString = uri.absoluteString

            // URI表示
            let separator = String(repeating: "─", count: 70)
            print(separator)
            print(uriString)
            print(separator)
            print()
            print("↑ このURIをMetaMask等のウォレットアプリに貼り付けてください")
            print("  （WalletConnect対応アプリの「接続」→「WalletConnect」→「URIを貼り付け」）")
            print()
            print("接続待機中... (120秒でタイムアウト)")

            // 接続待機
            let address: String
            do {
                address = try await service.waitForConnection(timeout: 120)
            } catch WCError.timeout {
                print("\n⚠ タイムアウトしました。再度 scion account connect を実行してください。")
                throw ExitCode.failure
            }

            print("\n✓ 接続しました！")
            print("  アドレス: \(address)")

            // ラベルを決定
            let resolvedLabel: String
            if let l = label, !l.isEmpty {
                resolvedLabel = l
            } else {
                print("ラベルを入力してください（Enter でスキップ）: ", terminator: "")
                let input = readLine() ?? ""
                resolvedLabel = input.isEmpty ? "WalletConnect" : input
            }

            // DB に登録（Ethereum/Polygon/Avalanche の3チェーン共通アドレスとして保存）
            let db = try DatabaseManager(path: DatabaseManager.defaultPath())
            let repo = AccountRepository(db: db)

            let account = Account(
                id: UUID().uuidString,
                type: AccountType.wallet.rawValue,
                label: resolvedLabel,
                url: nil,
                contractAddress: nil
            )
            try repo.insert(account)

            // EVM アドレスは3チェーン共通
            for chain in ["ethereum", "polygon", "avalanche"] {
                let depositAddr = DepositAddress(
                    id: UUID().uuidString,
                    accountId: account.id,
                    chain: chain,
                    address: address
                )
                try repo.insertDepositAddress(depositAddr)
            }

            print("  ラベル: \(resolvedLabel)")
            print()
            print("✓ ウォレットを登録しました。以下のコマンドで利用できます:")
            print("  scion holdings          → 保有明細を表示")
            print("  scion pnl               → 損益サマリーを表示")
            print("  scion add buy           → 購入を記録")
            print("  scion history           → 取引履歴を表示")
            print()
        }
    }

    // MARK: - List

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

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete", abstract: "アカウントを削除")

        @Argument(help: "削除するアカウントのID")
        var id: String

        mutating func run() async throws {
            let db = try DatabaseManager(path: DatabaseManager.defaultPath())
            let repo = AccountRepository(db: db)

            guard let account = try repo.fetch(id: id) else {
                print("エラー: アカウントが見つかりません: \(id)")
                throw ExitCode.failure
            }

            print("削除するアカウント: \(account.label) (\(account.type))")
            print("本当に削除しますか？ [y/N]: ", terminator: "")
            let confirm = readLine() ?? ""
            guard confirm.lowercased() == "y" else {
                print("キャンセルしました")
                return
            }

            try repo.delete(id: id)
            print("✓ アカウントを削除しました: \(account.label)")
        }
    }
}

func prompt(_ message: String) throws -> String {
    print(message, terminator: "")
    return readLine() ?? ""
}
